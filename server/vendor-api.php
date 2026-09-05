<?php
/**
 * vendor-api.php — Standalone Vendor API (bypasses WordPress REST entirely)
 * =========================================================================
 * Upload to your WordPress ROOT directory (same folder as wp-config.php).
 *
 * This file loads only wp-load.php (WordPress core + plugins), NOT the REST
 * API machinery. It handles JWT auth manually and returns JSON directly,
 * so it is immune to any security plugin, CDN rule, or firewall that blocks
 * /wp-json/ paths.
 *
 * Usage (no auth):
 *   GET /vendor-api.php?action=ping
 *
 * Usage (with JWT):
 *   curl -H "Authorization: Bearer <token>" \
 *        "https://yoursite.com/vendor-api.php?action=get_store"
 *
 * Supported actions:
 *   ping              — diagnostic (no auth)
 *   get_store         — vendor store/profile info
 *   get_reports       — dashboard stats (sales, orders, earnings)
 *   get_products      — vendor products (supports ?per_page= & ?page=)
 *   get_orders        — vendor orders (supports ?status=, ?per_page=, ?page=)
 *   get_balance       — vendor balance + withdrawal info
 *   get_coupons       — vendor coupons
 *   get_reviews       — vendor product reviews
 *   get_announcements — admin announcements for vendors
 *   update_store      — update vendor store settings (POST with JSON body)
 */

// ── Bootstrap WordPress (no REST, no theme, no redirects) ──────────────
define( 'WP_USE_THEMES', false );
define( 'SHORTINIT', false ); // We need full WP for Dokan

// Walk up directories to find wp-load.php — handles any upload location
$wp_load = null;
$dir = __DIR__;
for ( $i = 0; $i < 10; $i++ ) {
    $candidate = $dir . '/wp-load.php';
    if ( file_exists( $candidate ) ) {
        $wp_load = $candidate;
        break;
    }
    $parent = dirname( $dir );
    if ( $parent === $dir ) break; // reached filesystem root
    $dir = $parent;
}

if ( ! $wp_load ) {
    // Last resort: try common WordPress root paths
    $common_paths = [
        $_SERVER['DOCUMENT_ROOT'] . '/wp-load.php',
        dirname( __DIR__ ) . '/wp-load.php',
        dirname( __DIR__, 2 ) . '/wp-load.php',
        dirname( __DIR__, 3 ) . '/wp-load.php',
    ];
    foreach ( $common_paths as $path ) {
        if ( file_exists( $path ) ) {
            $wp_load = $path;
            break;
        }
    }
}

if ( ! $wp_load ) {
    header( 'Content-Type: application/json; charset=utf-8', true, 500 );
    echo json_encode( [
        'error'    => 'wp-load.php not found.',
        'cwd'      => __DIR__,
        'doc_root' => $_SERVER['DOCUMENT_ROOT'] ?? 'unknown',
        'hint'     => 'Upload vendor-api.php to your WordPress root directory (same folder as wp-config.php).',
    ] );
    exit;
}

require_once $wp_load;

// ── Always return JSON ─────────────────────────────────────────────────
header( 'Content-Type: application/json; charset=utf-8' );
header( 'Access-Control-Allow-Origin: *' );
header( 'Access-Control-Allow-Headers: Authorization, Content-Type' );
header( 'Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS' );

// Handle preflight
if ( $_SERVER['REQUEST_METHOD'] === 'OPTIONS' ) {
    http_response_code( 200 );
    exit;
}

// ── JWT Authentication ─────────────────────────────────────────────────
function vendor_api_authenticate(): ?int {
    $auth_header = '';

    // Try standard server var
    if ( ! empty( $_SERVER['HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif ( ! empty( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    } elseif ( function_exists( 'getallheaders' ) ) {
        $headers = getallheaders();
        $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }

    // Also check query param fallback (some servers strip the header)
    if ( empty( $auth_header ) && ! empty( $_GET['token'] ) ) {
        $auth_header = 'Bearer ' . $_GET['token'];
    }

    if ( empty( $auth_header ) || ! preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $matches ) ) {
        return null;
    }

    $jwt_token = $matches[1];

    // Method 1: Use JWT Auth plugin's built-in validation
    if ( function_exists( 'jwt_auth_get_user_from_token' ) ) {
        try {
            $user = jwt_auth_get_user_from_token( $jwt_token );
            if ( $user && ! is_wp_error( $user ) && isset( $user->ID ) && $user->ID > 0 ) {
                wp_set_current_user( $user->ID );
                return $user->ID;
            }
        } catch ( \Exception $e ) {
            // Fall through to manual decode
        }
    }

    // Method 2: Manual JWT decode using Firebase\JWT (bundled with JWT Auth plugin)
    if ( defined( 'JWT_AUTH_SECRET_KEY' ) ) {
        // Try Firebase\JWT\JWT first (newer namespace)
        if ( class_exists( '\Firebase\JWT\JWT' ) ) {
            try {
                $decoded = \Firebase\JWT\JWT::decode( $jwt_token, new \Firebase\JWT\Key( JWT_AUTH_SECRET_KEY, 'HS256' ) );
                $user_id = $decoded->data->user->id ?? null;
                if ( $user_id ) {
                    wp_set_current_user( (int) $user_id );
                    return (int) $user_id;
                }
            } catch ( \Exception $e ) {}
        }

        // Try legacy JWT class
        if ( class_exists( 'JWT' ) ) {
            try {
                $decoded = \JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
                $user_id = $decoded->data->user->id ?? null;
                if ( $user_id ) {
                    wp_set_current_user( (int) $user_id );
                    return (int) $user_id;
                }
            } catch ( \Exception $e ) {}
        }
    }

    // All signature-verified methods failed — reject the token
    return null;
}

// ── Helper: check vendor status ────────────────────────────────────────
function vendor_api_require_vendor( int $user_id ): void {
    if ( ! function_exists( 'dokan_is_user_seller' ) || ! dokan_is_user_seller( $user_id ) ) {
        http_response_code( 403 );
        echo json_encode( [ 'error' => 'Not a vendor.', 'code' => 'not_vendor' ] );
        exit;
    }
}

// ── Helper: send JSON response ─────────────────────────────────────────
function vendor_api_respond( $data, int $code = 200 ): void {
    http_response_code( $code );
    echo json_encode( $data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE );
    exit;
}

// ── Helper: resolve WC customer ID from WP user ID ────────────────────
// WooCommerce customer IDs and WP user IDs are separate — this bridges them.
function vendor_api_find_customer_id( int $user_id ): int {
    // Method 1: Check the mapping meta key
    $cid = get_user_meta( $user_id, '_woocommerce_customer_id', true );
    if ( $cid ) return (int) $cid;

    // Method 2: Search WC orders for this user
    if ( function_exists( 'wc_get_orders' ) ) {
        $order_ids = wc_get_orders( [
            'customer' => $user_id,
            'limit'    => 1,
            'return'   => 'ids',
        ] );
        if ( ! empty( $order_ids ) ) {
            $order   = wc_get_order( $order_ids[0] );
            $cid     = $order->get_customer_id();
            if ( $cid > 0 ) {
                update_user_meta( $user_id, '_woocommerce_customer_id', $cid );
                return $cid;
            }
        }
    }

    // Method 3: Search users table for matching record
    global $wpdb;
    $cid = $wpdb->get_var( $wpdb->prepare(
        "SELECT ID FROM {$wpdb->prefix}wc_customer_lookup WHERE user_id = %d LIMIT 1",
        $user_id
    ) );
    if ( $cid ) {
        update_user_meta( $user_id, '_woocommerce_customer_id', (int) $cid );
        return (int) $cid;
    }

    // Fallback: assume they're synced
    return $user_id;
}

// ═══════════════════════════════════════════════════════════════════════
// ROUTER
// ═══════════════════════════════════════════════════════════════════════

$action = $_GET['action'] ?? '';

// ── ping (no auth) ─────────────────────────────────────────────────────
if ( $action === 'ping' ) {
    // Check if Authorization header is reaching PHP
    $auth_received = ! empty( $_SERVER['HTTP_AUTHORIZATION'] )
        || ! empty( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] )
        || ( function_exists( 'getallheaders' ) && ! empty( getallheaders()['Authorization'] ?? '' ) )
        || ! empty( $_SERVER['PHP_AUTH_PW'] )
        || ! empty( $_GET['token'] );

    vendor_api_respond( [
        'status'       => 'ok',
        'wp_loaded'    => true,
        'wp_version'   => get_bloginfo( 'version' ),
        'site_url'     => get_site_url(),
        'dokan'        => function_exists( 'dokan' ),
        'dokan_pro'    => defined( 'DOKAN_PRO_VERSION' ) ? DOKAN_PRO_VERSION : false,
        'is_seller'    => function_exists( 'dokan_is_user_seller' ),
        'jwt_func'     => function_exists( 'jwt_auth_get_user_from_token' ),
        'jwt_class'    => class_exists( '\Firebase\JWT\JWT' ) || class_exists( 'JWT' ),
        'jwt_secret'   => defined( 'JWT_AUTH_SECRET_KEY' ),
        'wc_active'    => class_exists( 'WooCommerce' ),
        'php_version'  => PHP_VERSION,
        'time'         => current_time( 'mysql' ),
        'memory'       => round( memory_get_usage( true ) / 1024 / 1024, 1 ) . ' MB',
        'auth_header_received' => $auth_received,
        'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'unknown',
    ] );
}

// ── test-auth (no pre-auth — tests the auth chain itself) ──────────────
if ( $action === 'test-auth' ) {
    $debug = [
        'server_software'        => $_SERVER['SERVER_SOFTWARE'] ?? 'unknown',
        'http_auth_set'          => ! empty( $_SERVER['HTTP_AUTHORIZATION'] ),
        'redirect_auth_set'      => ! empty( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ),
        'php_auth_pw_set'        => ! empty( $_SERVER['PHP_AUTH_PW'] ),
        'token_param_set'        => ! empty( $_GET['token'] ),
        'getallheaders_exists'   => function_exists( 'getallheaders' ),
    ];

    if ( function_exists( 'getallheaders' ) ) {
        $all = getallheaders();
        $debug['getallheaders_keys'] = array_keys( $all );
        $debug['auth_from_headers']  = ! empty( $all['Authorization'] ?? $all['authorization'] ?? '' );
    }

    // Attempt authentication and report which method succeeded
    $result = vendor_api_authenticate();
    $debug['auth_success']  = $result !== null;
    $debug['auth_user_id']  = $result;

    // Check what's available
    $debug['jwt_func_available']  = function_exists( 'jwt_auth_get_user_from_token' );
    $debug['firebase_jwt_avail']  = class_exists( '\Firebase\JWT\JWT' );
    $debug['legacy_jwt_avail']    = class_exists( 'JWT' );
    $debug['jwt_secret_defined']  = defined( 'JWT_AUTH_SECRET_KEY' );

    // Try to decode token manually for diagnostics
    $header_found = false;
    $auth_header = '';
    if ( ! empty( $_SERVER['HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'];
        $header_found = true;
    } elseif ( ! empty( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
        $header_found = true;
    } elseif ( function_exists( 'getallheaders' ) ) {
        $headers = getallheaders();
        $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        $header_found = ! empty( $auth_header );
    } elseif ( ! empty( $_GET['token'] ) ) {
        $auth_header = 'Bearer ' . $_GET['token'];
        $header_found = true;
    }

    $debug['auth_header_found'] = $header_found;
    if ( $header_found && preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $m ) ) {
        $parts = explode( '.', $m[1] );
        $debug['token_parts'] = count( $parts );
        if ( count( $parts ) >= 2 ) {
            $payload = json_decode( base64_decode( strtr( $parts[1], '-_', '+/' ) ), true );
            $debug['token_payload'] = $payload;
            $debug['token_user_id'] = $payload['data']['user']['id'] ?? null;
            $debug['token_exp']     = $payload['exp'] ?? null;
            $debug['token_iat']     = $payload['iat'] ?? null;
            if ( ! empty( $debug['token_exp'] ) ) {
                $debug['token_expired'] = $debug['token_exp'] < time();
                $debug['token_exp_date'] = date( 'Y-m-d H:i:s', $debug['token_exp'] );
                $debug['server_time']    = date( 'Y-m-d H:i:s', time() );
            }
        }
    } else {
        $debug['auth_header_preview'] = substr( $auth_header, 0, 50 ) . '...';
    }

    vendor_api_respond( $debug );
}

// ── get_store_public (no auth — customer-facing vendor profile) ─────────
// GET /vendor-api.php?action=get_store_public&store_id=N
if ( $action === 'get_store_public' ) {
    $store_id = absint( $_GET['store_id'] ?? 0 );
    if ( ! $store_id ) {
        vendor_api_respond( [ 'error' => 'store_id is required.', 'code' => 'bad_request' ], 400 );
    }

    if ( ! function_exists( 'dokan' ) ) {
        vendor_api_respond( [ 'error' => 'Dokan is not available.', 'code' => 'no_dokan' ], 500 );
    }

    $vendor = dokan()->vendor->get( $store_id );
    if ( ! $vendor || ! $vendor->get_id() ) {
        vendor_api_respond( [ 'error' => 'Store not found.', 'code' => 'no_store' ], 404 );
    }

    $owner_id = (int) $vendor->get_owner_id();
    if ( ! $owner_id && function_exists( 'dokan_get_store_admin_id' ) ) {
        $owner_id = (int) dokan_get_store_admin_id( $store_id );
    }
    $profile  = get_user_meta( $owner_id, 'dokan_profile_settings', true ) ?: [];

    vendor_api_respond( [
        'id'               => (int) $vendor->get_id(),
        'user_id'          => $owner_id,
        'store_name'       => $vendor->get_shop_name(),
        'slug'             => $vendor->get_slug(),
        'phone'            => $vendor->get_phone(),
        'banner'           => $vendor->get_banner(),
        'gravatar'         => $vendor->get_avatar(),
        'address'          => method_exists( $vendor, 'get_address' ) ? $vendor->get_address() : [],
        'description'      => $vendor->get_shop_description(),
        'biography'        => get_user_meta( $owner_id, 'vendor_biography', true ),
        'social'           => is_array( $profile['social'] ?? null ) ? $profile['social'] : [],
        'store_open_close' => is_array( $profile['store_open_close'] ?? null ) ? $profile['store_open_close'] : [],
        'rating'           => function_exists( 'dokan_get_seller_rating' ) ? dokan_get_seller_rating( $owner_id ) : 0,
        'rating_count'     => function_exists( 'dokan_get_seller_review_count' ) ? dokan_get_seller_review_count( $owner_id ) : 0,
    ] );
}

// ── get_store_reviews (no auth — customer-facing vendor reviews) ────────
// GET /vendor-api.php?action=get_store_reviews&store_id=N
//
// DATABASE SCHEMA EVIDENCE (zzmore.store u910292103_0z5JM.sql):
//   Dokan store reviews live in TWO places:
//   1) wp_posts post_type='dokan_store_reviews' with postmeta (store_id=589, rating=5)
//      → Example DB row (sql line 427982): ID=31093 post_author=1 post_title='Absolutely impressive'
//        post_content='I love their services', post_date='2026-09-04 05:34:26', post_status='publish'
//      → wp_postmeta (lines 416313-416314): 31093 store_id='589', 31093 rating='5'
//   2) wp_comments comment_type='store_review' (e.g. comment_ID=4631 comment_author='Tayo'
//      comment_content='amazing' date='2026-04-13')
//   3) wp_comments comment_type='review' on vendor's products (product review comments — keep
//      for aggregating product reviews when explicit store reviews are empty)
if ( $action === 'get_store_reviews' ) {
    $store_id = absint( $_GET['store_id'] ?? 0 );
    if ( ! $store_id ) {
        vendor_api_respond( [ 'error' => 'store_id is required.', 'code' => 'bad_request' ], 400 );
    }

    if ( ! function_exists( 'dokan' ) ) {
        vendor_api_respond( [ 'error' => 'Dokan is not available.', 'code' => 'no_dokan' ], 500 );
    }

    $vendor = dokan()->vendor->get( $store_id );
    if ( ! $vendor || ! $vendor->get_id() ) {
        vendor_api_respond( [ 'error' => 'Store not found.', 'code' => 'no_store' ], 404 );
    }

    $owner_id = (int) $vendor->get_owner_id();
    if ( ! $owner_id && function_exists( 'dokan_get_store_admin_id' ) ) {
        $owner_id = (int) dokan_get_store_admin_id( $store_id );
    }

    global $wpdb;
    $reviews = [];
    $seen_ids = []; // dedup

    // ── Source 1: wp_posts CPT dokan_store_reviews (PRIMARY STORE REVIEWS) ─
    // NOTE: 2026-09-04 FIX — join wp_postmeta directly in SQL to filter by
    // the requested store_id AT THE DATABASE LAYER instead of pulling all
    // published store reviews and discarding non-matching ones in PHP. This
    // eliminates cross-vendor review leakage entirely (the old path pulled
    // 500 rows from all stores — now it pulls ONLY rows for this store).
    $store_review_posts = $wpdb->get_results( $wpdb->prepare(
        "SELECT p.ID, p.post_author, p.post_date, p.post_title, p.post_content,
                p.post_excerpt, u.display_name AS author_name, u.user_email AS author_email,
                COALESCE(pm_rating.meta_value, '0') AS rating_raw
         FROM {$wpdb->posts} p
         INNER JOIN {$wpdb->postmeta} pm_store
                 ON pm_store.post_id = p.ID
                AND pm_store.meta_key = 'store_id'
         LEFT JOIN {$wpdb->postmeta} pm_rating
                ON pm_rating.post_id = p.ID
               AND pm_rating.meta_key = 'rating'
         LEFT JOIN {$wpdb->users} u ON u.ID = p.post_author
         WHERE p.post_type = 'dokan_store_reviews'
           AND p.post_status = 'publish'
           AND pm_store.meta_value = %s
         ORDER BY p.post_date DESC LIMIT 500",
        (string) $store_id
    ) );
    foreach ( $store_review_posts as $sr ) {
        $rating_val = is_numeric( $sr->rating_raw ) ? (float) $sr->rating_raw : 0;
        $reviews[] = [
            'id'            => (int) $sr->ID,
            'source'        => 'dokan_store_reviews_cpt',
            'store_id'      => (int) $store_id,
            'vendor_owner_id' => $owner_id,
            'product_id'    => null,
            'rating'        => $rating_val,
            'author'        => $sr->author_name ?: ( $sr->post_author ? get_user_by( 'id', $sr->post_author )->display_name ?? 'Customer' : 'Customer' ),
            'author_email'  => $sr->author_email,
            'title'         => $sr->post_title,
            'content'       => $sr->post_content,
            'date'          => $sr->post_date,
        ];
        $seen_ids[ 'p' . $sr->ID ] = true;
    }

    // ── Source 2: wp_comments comment_type='store_review' (old-style Dokan reviews) ─
    // IMPORTANT: pull with meta_query store_id FIRST (this is the ONLY
    // supported legacy way to link a store review to a store).
    $comment_store_reviews = get_comments( [
        'type'       => 'store_review',
        'status'     => 'approve',
        'orderby'    => 'comment_date_gmt',
        'order'      => 'DESC',
        'number'     => 200,
        'meta_query' => [
            [
                'key'     => 'store_id',
                'value'   => $store_id,
                'compare' => '=',
                'type'    => 'NUMERIC',
            ],
        ],
    ] );
    // 2026-09-04 FIX — REMOVED the INCORRECT 'user_id' => $owner_id fallback.
    // That parameter filtered comments WHERE comment_author (the person who
    // WROTE the review) = the vendor owner. That pulled reviews WRITTEN BY
    // the vendor about OTHER products/vendors — not reviews FOR this store.
    // When no explicit store_id meta exists, we DO NOT add unfiltered
    // store_review comments; we skip source 2 entirely for this vendor and
    // rely on source 3 product comments (strictly scoped to vendor products)
    // for aggregated display.
    foreach ( $comment_store_reviews as $c ) {
        if ( isset( $seen_ids[ 'c' . $c->comment_ID ] ) ) continue;
        $rating = get_comment_meta( $c->comment_ID, 'rating', true );
        $reviews[] = [
            'id'            => (int) $c->comment_ID,
            'source'        => 'wp_comments_store_review',
            'store_id'      => $store_id,
            'vendor_owner_id' => $owner_id,
            'product_id'    => null,
            'rating'        => is_numeric( $rating ) ? (float) $rating : 0,
            'author'        => $c->comment_author,
            'author_email'  => $c->comment_author_email,
            'title'         => '',
            'content'       => $c->comment_content,
            'date'          => $c->comment_date,
        ];
        $seen_ids[ 'c' . $c->comment_ID ] = true;
    }

    // ── Source 3: wp_comments comment_type='review' on vendor products (product reviews
    //    aggregated into store profile "what customers say" section). ─
    // NOTE: explicitly scoped via 'post__in' → vendor products ONLY
    // (L477 get_posts author=$owner_id) — no cross-vendor leakage possible.
    $product_ids = get_posts( [
        'author'         => $owner_id,
        'post_type'      => 'product',
        'post_status'    => 'publish',
        'fields'         => 'ids',
        'posts_per_page' => -1,
    ] );
    if ( ! empty( $product_ids ) ) {
        $product_comments = get_comments( [
            'post__in' => $product_ids,
            'status'   => 'approve',
            'type'     => 'review',
            'orderby'  => 'comment_date_gmt',
            'order'    => 'DESC',
            'number'   => 50,
        ] );
        foreach ( $product_comments as $c ) {
            if ( isset( $seen_ids[ 'c' . $c->comment_ID ] ) ) continue;
            // Double guard: ensure the comment's product's post_author IS
            // indeed the current vendor (belt + suspenders, in case a plugin
            // filters get_comments and leaks rows).
            $_comment_prod_author = (int) get_post_field( 'post_author', (int) $c->comment_post_ID );
            if ( $_comment_prod_author !== 0 && $_comment_prod_author !== $owner_id ) {
                continue;
            }
            $rating = get_comment_meta( $c->comment_ID, 'rating', true );
            $reviews[] = [
                'id'            => (int) $c->comment_ID,
                'source'        => 'wp_comments_product_review',
                'store_id'      => $store_id,
                'vendor_owner_id' => $owner_id,
                'product_id'    => (int) $c->comment_post_ID,
                'rating'        => is_numeric( $rating ) ? (float) $rating : 0,
                'author'        => $c->comment_author,
                'author_email'  => $c->comment_author_email,
                'title'         => '',
                'content'       => $c->comment_content,
                'date'          => $c->comment_date,
            ];
            $seen_ids[ 'c' . $c->comment_ID ] = true;
        }
    }

    // ── Aggregate summary rating/count ────────────────────────────────────
    $rating_sum   = 0.0;
    $rating_count = 0;
    foreach ( $reviews as $r ) {
        if ( ! empty( $r['rating'] ) && $r['rating'] > 0 ) {
            $rating_sum += (float) $r['rating'];
            $rating_count++;
        }
    }
    $avg_rating = $rating_count > 0 ? round( $rating_sum / $rating_count, 2 ) : 0;

    // Sort: newest first (preserving source order within same second is fine)
    usort( $reviews, function( $a, $b ) {
        return strcmp( $b['date'], $a['date'] );
    } );

    vendor_api_respond( [
        'reviews'      => $reviews,
        'count'        => count( $reviews ),
        'rating'       => $avg_rating,
        'rating_count' => $rating_count,
        'sources'      => [
            'store_cpt'        => count( array_filter( $reviews, fn($r) => $r['source'] === 'dokan_store_reviews_cpt' ) ),
            'store_comments'   => count( array_filter( $reviews, fn($r) => $r['source'] === 'wp_comments_store_review' ) ),
            'product_comments' => count( array_filter( $reviews, fn($r) => $r['source'] === 'wp_comments_product_review' ) ),
        ],
    ] );
}

// ── All other actions require auth ─────────────────────────────────────
$user_id = vendor_api_authenticate();

if ( ! $user_id ) {
    http_response_code( 401 );
    echo json_encode( [ 'error' => 'Invalid or missing JWT token.', 'code' => 'unauthorized' ] );
    exit;
}

// ── get_store ──────────────────────────────────────────────────────────
if ( $action === 'get_store' ) {
    vendor_api_require_vendor( $user_id );

    $vendor = dokan()->vendor->get( $user_id );
    if ( ! $vendor || ! $vendor->get_id() ) {
        vendor_api_respond( [ 'error' => 'No store found.', 'code' => 'no_store' ], 404 );
    }

    $profile = get_user_meta( $user_id, 'dokan_profile_settings', true ) ?: [];

    // Also read the individual user meta that Dokan's form saves directly
    $company_name = get_user_meta( $user_id, 'dokan_company_name', true ) ?: ( $profile['company_name'] ?? '' );
    $company_id   = get_user_meta( $user_id, 'dokan_company_id_number', true ) ?: ( $profile['company_id_number'] ?? '' );
    $vat_number   = get_user_meta( $user_id, 'dokan_vat_number', true ) ?: ( $profile['vat_number'] ?? '' );
    $categories   = wp_get_object_terms( $vendor->get_id(), 'store_category', [ 'fields' => 'id=>name' ] );

    vendor_api_respond( [
        'id'                   => $vendor->get_id(),
        'user_id'              => $user_id,
        'store_name'           => $vendor->get_shop_name(),
        'slug'                 => $vendor->get_slug(),
        'email'                => get_userdata( $user_id )->user_email ?? '',
        'phone'                => $vendor->get_phone(),
        'banner'               => $vendor->get_banner(),
        'gravatar'             => $vendor->get_avatar(),
        'address'              => method_exists( $vendor, 'get_address' ) ? $vendor->get_address() : [],
        'is_open'              => $vendor->is_store_open(),
        'description'          => $vendor->get_shop_description(),
        'social'               => $profile['social'] ?? [],
        'payment'              => $profile['payment'] ?? [],
        'company_name'         => $company_name,
        'company_id_number'    => $company_id,
        'vat_number'           => $vat_number,
        'store_categories'     => is_array( $categories ) ? $categories : [],
        'store_open_close'     => $profile['store_open_close'] ?? [],
        'funnel_id'            => get_user_meta( $user_id, 'dokan_custom_funnel_id', true ) ?: '',
        'tnc_enabled'          => ( $profile['dokan_store_tnc_enable'] ?? get_user_meta( $user_id, 'dokan_store_tnc_enable', true ) ) === 'on',
        'min_amount_to_order'  => get_user_meta( $user_id, 'dokan_min_amount_to_order', true ) ?: '0',
        'max_amount_to_order'  => get_user_meta( $user_id, 'dokan_max_amount_to_order', true ) ?: '0',
    ] );
}

// ── get_reports (dashboard stats) ──────────────────────────────────────
// DATABASE EVIDENCE-BASED (u910292103_0z5JM.sql):
//   - wp_dokan_order_stats: each order has vendor_id + vendor_earning (line 131804)
//     → DB example: vendor_id=89 (vendor) has rows: 9370=18500, 10901=3000, 10926=24500,
//       10978=12000, 11073=2000, 11351=13000, ... (SUM for total earnings)
//   - wp_wc_order_stats: order_id FK → total_sales = order gross (line 486273)
//   - wp_dokan_vendor_balance: balance_date trn_type='dokan_withdraw'/'dokan_orders'
//     → per vendor credit(debits) balance ledger (line 132894)
//   - dokan reviews: wp_posts post_type='dokan_store_reviews' + postmeta store_id+rating
if ( $action === 'get_reports' ) {
    vendor_api_require_vendor( $user_id );

    $vendor     = dokan()->vendor->get( $user_id );
    $store_id   = $vendor->get_id();
    $owner_id   = (int) $vendor->get_owner_id();
    if ( ! $owner_id && function_exists( 'dokan_get_store_admin_id' ) ) {
        $owner_id = (int) dokan_get_store_admin_id( $store_id );
    }
    $results    = [];

    global $wpdb;

    // ═══════════════════════════════════════════════════════════════════
    // 1. PRIMARY — wp_dokan_order_stats direct SQL aggregate (smoking-gun)
    //    This table is ALWAYS populated by Dokan for every order — no
    //    Dokan REST or cache involved.
    // ═══════════════════════════════════════════════════════════════════
    $order_stats_rows = $wpdb->get_results( $wpdb->prepare(
        "SELECT order_id, vendor_id, order_type,
                vendor_earning, vendor_gateway_fee, vendor_shipping_fee,
                vendor_shipping_tax, vendor_order_tax,
                admin_commission, admin_earning
         FROM {$wpdb->prefix}dokan_order_stats
         WHERE vendor_id = %d
           AND order_type IN (0,1,2,8)
         ORDER BY order_id DESC",
        $store_id
    ) );

    $vendor_earning_sum = 0.0;
    $vendor_order_rows  = [];
    $by_status_count    = [
        'pending'    => 0, 'processing' => 0, 'on-hold'    => 0,
        'completed'  => 0, 'cancelled'  => 0, 'refunded'   => 0, 'failed' => 0,
    ];
    $order_ids_for_stats  = [];
    $order_ids_for_status = [];

    foreach ( $order_stats_rows as $os ) {
        $vendor_earning_sum += (float) $os->vendor_earning;
        $order_ids_for_stats[] = (int) $os->order_id;
        $vendor_order_rows[] = [
            'order_id'       => (int) $os->order_id,
            'vendor_earning' => (float) $os->vendor_earning,
            'vendor_shipping'=> (float) $os->vendor_shipping_fee,
            'vendor_tax'     => (float) $os->vendor_order_tax + (float) $os->vendor_shipping_tax,
            'admin_commission'=> (float) $os->admin_commission,
        ];
    }
    $results['vendor_earning_total'] = (string) $vendor_earning_sum;
    $results['vendor_order_rows']     = count( $vendor_order_rows );

    // 2. wp_wc_order_stats JOIN for gross total_sales per vendor's orders
    $wc_gross = 0.0;
    $unique_customers = [];
    if ( ! empty( $order_ids_for_stats ) ) {
        $ids_in = implode( ',', array_map( 'intval', $order_ids_for_stats ) );
        $wc_rows = $wpdb->get_results(
            "SELECT order_id, total_sales, net_total, date_created, status, customer_id
             FROM {$wpdb->prefix}wc_order_stats
             WHERE order_id IN ($ids_in)"
        );
        $status_lookup = [
            'wc-pending' => 'pending',      'wc-processing' => 'processing',
            'wc-on-hold' => 'on-hold',      'wc-completed'  => 'completed',
            'wc-cancelled' => 'cancelled',  'wc-refunded'   => 'refunded',
            'wc-failed' => 'failed',        'wc-trash' => 'cancelled',
        ];
        foreach ( $wc_rows as $wr ) {
            $wc_gross += (float) $wr->total_sales;
            if ( ! empty( $wr->customer_id ) && (int) $wr->customer_id > 0 ) {
                $unique_customers[ (int)$wr->customer_id ] = true;
            }
            $status_short = $status_lookup[ $wr->status ] ?? null;
            if ( $status_short ) {
                $by_status_count[ $status_short ] = ($by_status_count[ $status_short ] ?? 0) + 1;
            }
        }
        $results['total_sales']   = (string) $wc_gross;      // gross (customer total paid)
        $results['total_earnings']= (string) $vendor_earning_sum; // vendor net
        $results['orders']        = count( $order_ids_for_stats );
        $results['customers']     = count( $unique_customers );
    } else {
        $results['total_sales']   = '0';
        $results['total_earnings']= '0';
        $results['orders']        = 0;
        $results['customers']     = 0;
    }

    // Merge the by_status_count into response (overrides legacy wc_get_orders counts below)
    foreach ( $by_status_count as $k => $v ) $results[ $k ] = $v;

    // 3. Dokan built-in reports (fallback only; DB values above are canonical)
    if ( empty( $results['total_sales'] ) || (float)$results['total_sales'] === 0.0 ) {
        if ( function_exists( 'dokan_get_sales_report_data' ) ) {
            try {
                $report = dokan_get_sales_report_data( $store_id );
                if ( isset( $report['sales'] ) && (float)$results['total_sales'] === 0.0 ) {
                    $results['total_sales'] = (string) $report['sales'];
                }
                $earn_candidate = $report['earning'] ?? $report['earnings'] ?? null;
                if ( $earn_candidate !== null && (float)$results['total_earnings'] === 0.0 ) {
                    $results['total_earnings'] = (string) $earn_candidate;
                }
                if ( isset( $report['orders'] ) && $results['orders'] === 0 ) {
                    $results['orders'] = (int) $report['orders'];
                }
            } catch ( \Exception $e ) {}
        }
    }

    // 4. Legacy wc_get_orders status counts fallback (for rare orphan orders)
    if ( class_exists( 'WooCommerce' ) && array_sum( $by_status_count ) === 0 ) {
        $statuses = [ 'wc-pending' => 'pending', 'wc-processing' => 'processing',
                      'wc-on-hold' => 'on-hold', 'wc-completed' => 'completed',
                      'wc-cancelled' => 'cancelled', 'wc-refunded' => 'refunded',
                      'wc-failed'  => 'failed' ];
        $total_orders = 0;
        foreach ( $statuses as $wc_status => $short ) {
            if ( isset( $by_status_count[ $short ] ) && $by_status_count[ $short ] > 0 ) continue;
            try {
                $count = count( wc_get_orders( [
                    'limit'     => -1, 'return'   => 'ids',
                    'meta_key'  => '_dokan_vendor_id', 'meta_value'=> $store_id,
                    'type'      => 'shop_order', 'status'   => $wc_status,
                ] ) );
                $results[ $short ] = $count;
                $total_orders += $count;
            } catch ( \Exception $e ) { $results[ $short ] = 0; }
        }
        if ( $results['orders'] === 0 ) $results['orders'] = $total_orders;
    }

    // 5. Product count (always needed)
    try {
        $product_args = [
            'author'      => $user_id,
            'post_type'   => 'product',
            'post_status' => [ 'publish', 'draft', 'pending' ],
            'posts_per_page' => -1,
            'fields'      => 'ids',
        ];
        $product_query = new WP_Query( $product_args );
        $results['products'] = (int) $product_query->found_posts;
    } catch ( \Exception $e ) { $results['products'] = 0; }

    // 6. Balance from wp_dokan_vendor_balance direct SQL (canonical per DB)
    try {
        $balance_rows = $wpdb->get_results( $wpdb->prepare(
            "SELECT SUM(credit) AS credits, SUM(debit) AS debits, status
             FROM {$wpdb->prefix}dokan_vendor_balance
             WHERE vendor_id = %d AND trn_type = 'dokan_orders'
             GROUP BY status",
            $store_id
        ) );
        $credit = 0.0;
        $debit  = 0.0;
        foreach ( (array) $balance_rows as $br ) {
            $credit += (float) $br->credits;
            $debit  += (float) $br->debits;
        }
        $withdrawn_rows = $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(credit), 0)
             FROM {$wpdb->prefix}dokan_vendor_balance
             WHERE vendor_id = %d
               AND trn_type = 'dokan_withdraw'
               AND status = 'approved'",
            $store_id
        ) );
        $withdrawn = (float) $withdrawn_rows;
        $pending_withdraw_rows = $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(credit), 0)
             FROM {$wpdb->prefix}dokan_vendor_balance
             WHERE vendor_id = %d
               AND trn_type = 'dokan_withdraw'
               AND status <> 'approved'",
            $store_id
        ) );
        $pending_withdraw = (float) $pending_withdraw_rows;
        $calculated_balance = max( 0.0, $credit - $debit - $withdrawn - $pending_withdraw );
        // Fallback to Dokan function if DB sums look empty
        if ( $calculated_balance > 0 ) {
            $results['current_balance'] = (string) $calculated_balance;
        } elseif ( function_exists( 'dokan_get_seller_balance' ) ) {
            $results['current_balance'] = (string) dokan_get_seller_balance( $user_id, false );
        } else {
            $results['current_balance'] = '0';
        }
        $results['withdrawn_total']   = (string) $withdrawn;
        $results['pending_withdrawal']= (string) $pending_withdraw;
    } catch ( \Exception $e ) {
        if ( function_exists( 'dokan_get_seller_balance' ) ) {
            $results['current_balance'] = (string) dokan_get_seller_balance( $user_id, false );
        } else {
            $results['current_balance'] = '0';
        }
    }

    // 7. Page views (Dokan Pro)
    if ( function_exists( 'dokan_get_store_pageviews' ) ) {
        $results['pageviews'] = dokan_get_store_pageviews( $store_id );
    } else {
        $results['pageviews'] = 0;
    }

    // 8. Rating & reviews count (using same dokan_store_reviews CPT + product comments as get_store_reviews)
    $rating_sum   = 0.0;
    $rating_count = 0;
    // 8a. dokan_store_reviews CPT
    $cpt_reviews = $wpdb->get_col( $wpdb->prepare(
        "SELECT p.ID FROM {$wpdb->posts} p
         INNER JOIN {$wpdb->postmeta} pm ON pm.post_id = p.ID AND pm.meta_key = 'store_id'
         WHERE p.post_type = 'dokan_store_reviews'
           AND p.post_status = 'publish'
           AND pm.meta_value = %s",
        (string) $store_id
    ) );
    foreach ( (array) $cpt_reviews as $rid ) {
        $r = get_post_meta( $rid, 'rating', true );
        if ( is_numeric( $r ) && (float) $r > 0 ) {
            $rating_sum += (float) $r;
            $rating_count++;
        }
    }
    // 8b. wp_comments comment_type='store_review' + product review comments for this vendor
    $product_ids = get_posts( [ 'author' => $user_id, 'post_type' => 'product', 'post_status' => 'publish', 'fields' => 'ids', 'posts_per_page' => -1 ] );
    if ( ! empty( $product_ids ) ) {
        $prod_comments = get_comments( [
            'post__in' => $product_ids, 'status' => 'approve', 'type' => 'review',
            'number' => 200,
        ] );
        foreach ( $prod_comments as $pc ) {
            $r = get_comment_meta( $pc->comment_ID, 'rating', true );
            if ( is_numeric( $r ) && (float) $r > 0 ) {
                $rating_sum += (float) $r;
                $rating_count++;
            }
        }
    }
    $avg_rating = $rating_count > 0 ? round( $rating_sum / $rating_count, 2 ) : 0;
    $results['average_rating'] = (string) $avg_rating;
    $results['review_count']   = $rating_count;
    // Customer engagement = orders count + unique customers + reviews count + pageviews (simple aggregate)
    $results['customer_engagement'] = (int) ( $results['orders'] + $results['customers'] + $rating_count + (int) ( $results['pageviews'] ?? 0 ) );
    $results['engagement_breakdown'] = [
        'orders'    => (int) $results['orders'],
        'customers' => (int) $results['customers'],
        'reviews'   => (int) $rating_count,
        'pageviews' => (int) ( $results['pageviews'] ?? 0 ),
    ];

    // Legacy alias compatibility (vendor_provider.dart reads these keys too)
    $results['sales_total']   = $results['total_sales'];
    $results['sales_earning'] = $results['total_earnings'];
    $results['earning']       = $results['total_earnings'];
    $results['balance']       = $results['current_balance'];
    $results['avg_rating']    = $results['average_rating'];

    vendor_api_respond( $results );
}

// ── get_products ───────────────────────────────────────────────────────
if ( $action === 'get_products' ) {
    vendor_api_require_vendor( $user_id );

    $vendor   = dokan()->vendor->get( $user_id );
    $per_page = max( 1, min( 100, (int) ( $_GET['per_page'] ?? 20 ) ) );
    $page     = max( 1, (int) ( $_GET['page'] ?? 1 ) );

    // Use Dokan's vendor product query
    $args = [
        'author'   => $user_id,
        'post_type'=> 'product',
        'posts_per_page' => $per_page,
        'paged'    => $page,
        'post_status' => [ 'publish', 'draft', 'pending' ],
    ];

    $query  = new WP_Query( $args );
    $products = [];

    foreach ( $query->posts as $post ) {
        $product = wc_get_product( $post );
        if ( ! $product ) continue;

        $p = [
            'id'             => $product->get_id(),
            'name'           => $product->get_name(),
            'slug'           => $product->get_slug(),
            'permalink'      => get_permalink( $product->get_id() ),
            'status'         => $product->get_status(),
            'price'          => $product->get_price(),
            'regular_price'  => $product->get_regular_price(),
            'sale_price'     => $product->get_sale_price(),
            'on_sale'        => $product->is_on_sale(),
            'stock_status'   => $product->get_stock_status(),
            'stock_quantity' => $product->get_stock_quantity(),
            'total_sales'    => $product->get_total_sales(),
            'average_rating' => $product->get_average_rating(),
            'rating_count'   => $product->get_rating_count(),
            'images'         => array_map( function( $id ) {
                $src = wp_get_attachment_image_url( $id, 'woocommerce_thumbnail' );
                return [ 'id' => $id, 'src' => $src ];
            }, array_merge( [ $product->get_image_id() ], $product->get_gallery_image_ids() ) ),
            'categories'     => array_map( function( $term ) {
                return [ 'id' => $term->term_id, 'name' => $term->name, 'slug' => $term->slug ];
            }, get_the_terms( $post->ID, 'product_cat' ) ?: [] ),
        ];

        // WooCommerce Subscriptions — append fields when available
        $sub_period = '';
        if ( class_exists( 'WC_Subscriptions_Product' ) ) {
            try {
                $sub_period = (string) WC_Subscriptions_Product::get_period( $product );
                if ( ! empty( $sub_period ) ) {
                    $p['is_subscription']              = true;
                    $p['subscription_price']           = (string) WC_Subscriptions_Product::get_price( $product );
                    $p['subscription_period']          = $sub_period;
                    $p['subscription_period_interval'] = (string) WC_Subscriptions_Product::get_interval( $product );
                    $p['subscription_length']          = (string) WC_Subscriptions_Product::get_length( $product );
                    $p['subscription_trial_length']    = (string) WC_Subscriptions_Product::get_trial_length( $product );
                    $p['subscription_trial_period']    = (string) WC_Subscriptions_Product::get_trial_period( $product );
                    $p['subscription_sign_up_fee']     = (string) WC_Subscriptions_Product::get_sign_up_fee( $product );
                    $p['type']                         = $product->get_type();
                }
            } catch ( \Exception $e ) {
                $sub_period = '';
            }
        }
        if ( empty( $sub_period ) ) {
            $sub_period = get_post_meta( $product->get_id(), '_subscription_period', true );
            if ( ! empty( $sub_period ) ) {
                $p['is_subscription']              = true;
                $p['subscription_price']           = get_post_meta( $product->get_id(), '_subscription_price', true );
                $p['subscription_period']          = $sub_period;
                $p['subscription_period_interval'] = get_post_meta( $product->get_id(), '_subscription_period_interval', true );
                $p['subscription_length']          = get_post_meta( $product->get_id(), '_subscription_length', true );
                $p['subscription_trial_length']    = get_post_meta( $product->get_id(), '_subscription_trial_length', true );
                $p['subscription_trial_period']    = get_post_meta( $product->get_id(), '_subscription_trial_period', true );
                $p['subscription_sign_up_fee']     = get_post_meta( $product->get_id(), '_subscription_sign_up_fee', true );
                $p['type']                         = $product->get_type();
            }
        }

        $products[] = $p;
    }

    vendor_api_respond( [
        'products'    => $products,
        'total'       => $query->found_posts,
        'total_pages' => $query->max_num_pages,
        'page'        => $page,
        'per_page'    => $per_page,
    ] );
}

// ── get_orders ─────────────────────────────────────────────────────────
if ( $action === 'get_orders' ) {
    vendor_api_require_vendor( $user_id );

    $vendor    = dokan()->vendor->get( $user_id );
    $store_id  = $vendor->get_id();
    $per_page  = max( 1, min( 100, (int) ( $_GET['per_page'] ?? 20 ) ) );
    $page      = max( 1, (int) ( $_GET['page'] ?? 1 ) );
    $status    = $_GET['status'] ?? '';

    $args = [
        'limit'     => $per_page,
        'page'      => $page,
        'meta_key'  => '_dokan_vendor_id',
        'meta_value'=> $store_id,
        'type'      => 'shop_order',
        'orderby'   => 'date',
        'order'     => 'DESC',
    ];

    if ( ! empty( $status ) ) {
        $args['status'] = 'wc-' . $status;
    }

    // Try Dokan's helper first
    if ( function_exists( 'dokan_get_seller_orders' ) ) {
        $order_ids = dokan_get_seller_orders( $user_id, $args );
    } else {
        $order_ids = wc_get_orders( array_merge( $args, [ 'return' => 'ids' ] ) );
    }

    $orders = [];
    foreach ( $order_ids as $oid ) {
        $order = wc_get_order( $oid );
        if ( ! $order ) continue;

        $orders[] = [
            'id'           => $order->get_id(),
            'order_number' => $order->get_order_number(),
            'status'       => $order->get_status(),
            'date_created' => $order->get_date_created() ? $order->get_date_created()->format( 'Y-m-d H:i:s' ) : '',
            'total'        => $order->get_total(),
            'currency'     => $order->get_currency(),
            'customer'     => [
                'id'          => $order->get_customer_id(),
                'first_name'  => $order->get_billing_first_name(),
                'last_name'   => $order->get_billing_last_name(),
                'email'       => $order->get_billing_email(),
            ],
            'items_count'  => count( $order->get_items() ),
        ];
    }

    vendor_api_respond( [ 'orders' => $orders ] );
}

// ── get_balance ────────────────────────────────────────────────────────
if ( $action === 'get_balance' ) {
    vendor_api_require_vendor( $user_id );

    $vendor  = dokan()->vendor->get( $user_id );
    $balance = 0;

    if ( function_exists( 'dokan_get_seller_balance' ) ) {
        $balance = dokan_get_seller_balance( $user_id, false );
    } else {
        // Manual calculation from completed orders
        $args = [
            'limit'     => -1,
            'meta_key'  => '_dokan_vendor_id',
            'meta_value'=> $vendor->get_id(),
            'status'    => [ 'wc-completed', 'wc-processing' ],
            'type'      => 'shop_order',
            'return'    => 'ids',
        ];
        $order_ids = wc_get_orders( $args );
        foreach ( $order_ids as $oid ) {
            // Get vendor earning from order meta
            $earning = get_post_meta( $oid, '_dokan_vendor_earning', true );
            $balance += floatval( $earning );
        }
    }

    // Withdrawal history
    $withdrawals = [];
    if ( function_exists( 'dokan_get_withdraw_requests' ) ) {
        $withdrawals = dokan_get_withdraw_requests( [ 'user_id' => $user_id ] );
    }

    vendor_api_respond( [
        'current_balance' => $balance,
        'withdrawals'     => $withdrawals,
    ] );
}

// ── get_coupons ────────────────────────────────────────────────────────
if ( $action === 'get_coupons' ) {
    vendor_api_require_vendor( $user_id );

    $args = [
        'post_type'   => 'shop_coupon',
        'author'      => $user_id,
        'posts_per_page' => -1,
        'post_status' => 'publish',
    ];

    $query   = new WP_Query( $args );
    $coupons = [];

    foreach ( $query->posts as $post ) {
        $c = new WC_Coupon( $post->ID );
        $coupons[] = [
            'id'               => $c->get_id(),
            'code'             => $c->get_code(),
            'amount'           => $c->get_amount(),
            'discount_type'    => $c->get_discount_type(),
            'date_expires'     => $c->get_date_expires() ? $c->get_date_expires()->format( 'Y-m-d' ) : null,
            'usage_count'      => $c->get_usage_count(),
            'usage_limit'      => $c->get_usage_limit(),
            'minimum_amount'   => $c->get_minimum_amount(),
        ];
    }

    vendor_api_respond( [ 'coupons' => $coupons ] );
}

// ── get_reviews ────────────────────────────────────────────────────────
if ( $action === 'get_reviews' ) {
    vendor_api_require_vendor( $user_id );

    $vendor  = dokan()->vendor->get( $user_id );
    $reviews = [];

    if ( method_exists( $vendor, 'get_reviews' ) ) {
        $reviews = $vendor->get_reviews();
    } else {
        // Fallback: get all vendor product IDs, then their reviews
        $product_ids = get_posts( [
            'author'    => $user_id,
            'post_type' => 'product',
            'fields'    => 'ids',
            'posts_per_page' => -1,
        ] );

        $comments = get_comments( [
            'post__in' => $product_ids,
            'status'   => 'approve',
            'type'     => 'review',
        ] );

        foreach ( $comments as $c ) {
            $reviews[] = [
                'id'         => $c->comment_ID,
                'product_id' => $c->comment_post_ID,
                'rating'     => get_comment_meta( $c->comment_ID, 'rating', true ),
                'author'     => $c->comment_author,
                'content'    => $c->comment_content,
                'date'       => $c->comment_date,
            ];
        }
    }

    vendor_api_respond( [ 'reviews' => $reviews ] );
}

// ── get_announcements ─────────────────────────────────────────────────
if ( $action === 'get_announcements' ) {
    vendor_api_require_vendor( $user_id );

    // Dokan stores announcements in dokan_announcement post type
    $args = [
        'post_type'      => 'dokan_announcement',
        'posts_per_page' => 20,
        'post_status'    => 'publish',
        'orderby'        => 'date',
        'order'          => 'DESC',
    ];

    $query  = new WP_Query( $args );
    $announcements = [];

    foreach ( $query->posts as $post ) {
        $sender_ids = get_post_meta( $post->ID, '_announcement_selected_user', true );
        // Show if sent to all vendors or this specific vendor
        if ( empty( $sender_ids ) || in_array( $user_id, (array) $sender_ids ) ) {
            $announcements[] = [
                'id'      => $post->ID,
                'title'   => $post->post_title,
                'content' => $post->post_content,
                'date'    => $post->post_date,
                'status'  => get_post_meta( $post->ID, '_announcement_status', true ) ?: 'read',
            ];
        }
    }

    vendor_api_respond( [ 'announcements' => $announcements ] );
}

// ── update_store ──────────────────────────────────────────────────────
if ( $action === 'update_store' ) {
    vendor_api_require_vendor( $user_id );

    if ( $_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'PUT' ) {
        vendor_api_respond( [ 'error' => 'Use POST or PUT.', 'code' => 'bad_method' ], 405 );
    }

    $body  = file_get_contents( 'php://input' );
    $input = json_decode( $body, true );

    if ( ! $input ) {
        vendor_api_respond( [ 'error' => 'Invalid JSON body.', 'code' => 'bad_json' ], 400 );
    }

    $vendor  = dokan()->vendor->get( $user_id );
    $profile = get_user_meta( $user_id, 'dokan_profile_settings', true ) ?: [];

    // Update store name
    if ( isset( $input['store_name'] ) ) {
        $profile['store_name'] = sanitize_text_field( $input['store_name'] );
        wp_update_term( $vendor->get_id(), 'store', [ 'name' => $profile['store_name'] ] );
    }

    // Update phone
    if ( isset( $input['phone'] ) ) {
        $profile['phone'] = sanitize_text_field( $input['phone'] );
        update_user_meta( $user_id, 'dokan_phone', sanitize_text_field( $input['phone'] ) );
    }

    // Update address (Dokan uses dokan_address[street_1], etc.)
    if ( isset( $input['address'] ) && is_array( $input['address'] ) ) {
        $profile['address'] = [
            'street_1' => sanitize_text_field( $input['address']['street_1'] ?? $profile['address']['street_1'] ?? '' ),
            'street_2' => sanitize_text_field( $input['address']['street_2'] ?? $profile['address']['street_2'] ?? '' ),
            'city'     => sanitize_text_field( $input['address']['city'] ?? $profile['address']['city'] ?? '' ),
            'state'    => sanitize_text_field( $input['address']['state'] ?? $profile['address']['state'] ?? '' ),
            'zip'      => sanitize_text_field( $input['address']['zip'] ?? $profile['address']['zip'] ?? '' ),
            'country'  => sanitize_text_field( $input['address']['country'] ?? $profile['address']['country'] ?? '' ),
        ];
    }

    // Update company details (matches form: settings_dokan_company_name, etc.)
    if ( isset( $input['company_name'] ) ) {
        $profile['company_name'] = sanitize_text_field( $input['company_name'] );
        update_user_meta( $user_id, 'dokan_company_name', sanitize_text_field( $input['company_name'] ) );
    }
    if ( isset( $input['company_id_number'] ) ) {
        $profile['company_id_number'] = sanitize_text_field( $input['company_id_number'] );
        update_user_meta( $user_id, 'dokan_company_id_number', sanitize_text_field( $input['company_id_number'] ) );
    }
    if ( isset( $input['vat_number'] ) ) {
        $profile['vat_number'] = sanitize_text_field( $input['vat_number'] );
        update_user_meta( $user_id, 'dokan_vat_number', sanitize_text_field( $input['vat_number'] ) );
    }

    // Update store categories (taxonomy: store_category)
    if ( isset( $input['store_categories'] ) && is_array( $input['store_categories'] ) ) {
        $cat_ids = array_map( 'absint', $input['store_categories'] );
        wp_set_object_terms( $vendor->get_id(), $cat_ids, 'store_category' );
        $profile['store_categories'] = $cat_ids;
    }

    // Update custom funnel ID
    if ( isset( $input['funnel_id'] ) ) {
        update_user_meta( $user_id, 'dokan_custom_funnel_id', sanitize_text_field( $input['funnel_id'] ) );
    }

    // Update terms & conditions
    if ( isset( $input['tnc_enabled'] ) ) {
        $tnc = $input['tnc_enabled'] ? 'on' : '';
        update_user_meta( $user_id, 'dokan_store_tnc_enable', $tnc );
        $profile['dokan_store_tnc_enable'] = $tnc;
    }

    // Update min/max order amounts
    if ( isset( $input['min_amount_to_order'] ) ) {
        update_user_meta( $user_id, 'dokan_min_amount_to_order', sanitize_text_field( $input['min_amount_to_order'] ) );
    }
    if ( isset( $input['max_amount_to_order'] ) ) {
        update_user_meta( $user_id, 'dokan_max_amount_to_order', sanitize_text_field( $input['max_amount_to_order'] ) );
    }

    // Update payment details
    if ( isset( $input['payment'] ) && is_array( $input['payment'] ) ) {
        $profile['payment'] = array_merge( $profile['payment'] ?? [], [
            'bank'   => [
                'bank_name' => sanitize_text_field( $input['payment']['bank']['bank_name'] ?? $profile['payment']['bank']['bank_name'] ?? '' ),
                'iban'      => sanitize_text_field( $input['payment']['bank']['iban'] ?? $profile['payment']['bank']['iban'] ?? '' ),
                'ac_name'   => sanitize_text_field( $input['payment']['bank']['ac_name'] ?? $profile['payment']['bank']['ac_name'] ?? '' ),
                'ac_number' => sanitize_text_field( $input['payment']['bank']['ac_number'] ?? $profile['payment']['bank']['ac_number'] ?? '' ),
            ],
            'paypal' => [
                'email' => sanitize_email( $input['payment']['paypal']['email'] ?? $profile['payment']['paypal']['email'] ?? '' ),
            ],
        ] );
    }

    // Update social links
    if ( isset( $input['social'] ) && is_array( $input['social'] ) ) {
        $profile['social'] = array_merge( $profile['social'] ?? [], [
            'fb'        => sanitize_text_field( $input['social']['fb'] ?? $profile['social']['fb'] ?? '' ),
            'twitter'   => sanitize_text_field( $input['social']['twitter'] ?? $profile['social']['twitter'] ?? '' ),
            'instagram' => sanitize_text_field( $input['social']['instagram'] ?? $profile['social']['instagram'] ?? '' ),
            'youtube'   => sanitize_text_field( $input['social']['youtube'] ?? $profile['social']['youtube'] ?? '' ),
            'linkedin'  => sanitize_text_field( $input['social']['linkedin'] ?? $profile['social']['linkedin'] ?? '' ),
        ] );
    }

    // Update store open/close
    if ( isset( $input['store_open_close'] ) && is_array( $input['store_open_close'] ) ) {
        $profile['store_open_close'] = [
            'open_notice'  => sanitize_text_field( $input['store_open_close']['open_notice'] ?? $profile['store_open_close']['open_notice'] ?? '' ),
            'close_notice' => sanitize_text_field( $input['store_open_close']['close_notice'] ?? $profile['store_open_close']['close_notice'] ?? '' ),
        ];
        if ( isset( $input['store_open_close']['is_open'] ) ) {
            update_user_meta( $user_id, 'dokan_enable_selling', $input['store_open_close']['is_open'] ? 'yes' : 'no' );
        }
    }

    if ( function_exists( 'dokan_update_store_settings' ) ) {
        dokan_update_store_settings( $user_id, $profile );
    } else {
        update_user_meta( $user_id, 'dokan_profile_settings', $profile );
    }

    // Return updated store
    vendor_api_respond( [
        'success' => true,
        'store'   => array_merge(
            [ 'id' => $vendor->get_id(), 'store_name' => $vendor->get_shop_name() ],
            $profile
        ),
    ] );
}

// ── get_store_products ────────────────────────────────────────────────
// GET /?action=get_store_products&store_id=N&per_page=50
// Public (no auth).  Returns products belonging to the store owner.
if ( 'get_store_products' === $action ) {
    $store_id  = isset( $_GET['store_id'] ) ? absint( $_GET['store_id'] ) : 0;
    $per_page  = isset( $_GET['per_page'] ) ? absint( $_GET['per_page'] ) : 50;

    if ( ! $store_id ) {
        vendor_api_respond( [ 'error' => 'store_id is required.' ], 400 );
    }

    $owner_id  = 0;
    $vendor    = dokan()->vendor->get( $store_id );
    if ( $vendor && $vendor->get_id() ) {
        $owner_id = $vendor->get_owner_id();
    }

    // Fallback: try dokan_get_store_admin_id
    if ( ! $owner_id && function_exists( 'dokan_get_store_admin_id' ) ) {
        $owner_id = dokan_get_store_admin_id( $store_id );
    }

    if ( ! $owner_id ) {
        vendor_api_respond( [ 'error' => 'Store not found or has no owner.' ], 404 );
    }

    $args = [
        'post_type'      => 'product',
        'post_status'    => 'publish',
        'author'         => $owner_id,
        'posts_per_page' => min( $per_page, 100 ),
        'paged'          => isset( $_GET['page'] ) ? absint( $_GET['page'] ) : 1,
    ];

    $query    = new WP_Query( $args );
    $products = [];

    if ( $query->have_posts() ) {
        $wc_product = function_exists( 'wc_get_product' );
        while ( $query->have_posts() ) {
            $query->the_post();
            $pid   = get_the_ID();
            $pdata = [
                'id'             => $pid,
                'name'           => get_the_title(),
                'slug'           => get_post_field( 'post_name', $pid ),
                'permalink'      => get_permalink( $pid ),
                'status'         => get_post_status( $pid ),
                'description'    => get_the_content(),
                'short_description' => get_the_excerpt(),
                'sku'            => get_post_meta( $pid, '_sku', true ),
                'price'          => get_post_meta( $pid, '_price', true ),
                'regular_price'  => get_post_meta( $pid, '_regular_price', true ),
                'sale_price'     => get_post_meta( $pid, '_sale_price', true ),
                'on_sale'        => get_post_meta( $pid, '_sale_price', true ) ? true : false,
                'stock_status'   => get_post_meta( $pid, '_stock_status', true ) ?: 'instock',
                'stock_quantity' => get_post_meta( $pid, '_stock', true ),
                'average_rating' => get_post_meta( $pid, '_wc_average_rating', true ) ?: '0',
                'rating_count'   => (int) get_post_meta( $pid, '_wc_review_count', true ) ?: 0,
                'images'         => [],
            ];

            // Featured image
            $thumb_id = get_post_thumbnail_id( $pid );
            if ( $thumb_id ) {
                $img = wp_get_attachment_image_src( $thumb_id, 'woocommerce_thumbnail' );
                if ( $img ) {
                    $pdata['images'][] = [ 'id' => $thumb_id, 'src' => $img[0] ];
                }
            }

            // Gallery images
            $gallery_ids = get_post_meta( $pid, '_product_image_gallery', true );
            if ( $gallery_ids ) {
                foreach ( explode( ',', $gallery_ids ) as $gid ) {
                    $gid  = absint( trim( $gid ) );
                    $gimg = wp_get_attachment_image_src( $gid, 'woocommerce_thumbnail' );
                    if ( $gimg ) {
                        $pdata['images'][] = [ 'id' => $gid, 'src' => $gimg[0] ];
                    }
                }
            }

            // Categories
            $terms = get_the_terms( $pid, 'product_cat' );
            if ( $terms && ! is_wp_error( $terms ) ) {
                $pdata['categories'] = array_map( function ( $t ) {
                    return [ 'id' => $t->term_id, 'name' => $t->name, 'slug' => $t->slug ];
                }, $terms );
            }

            // WooCommerce Subscriptions — append fields when available
            $sub_period = '';
            if ( $wc_product && class_exists( 'WC_Subscriptions_Product' ) ) {
                $wc_prod = wc_get_product( $pid );
                if ( $wc_prod ) {
                    try {
                        $sub_period = (string) WC_Subscriptions_Product::get_period( $wc_prod );
                        if ( ! empty( $sub_period ) ) {
                            $pdata['is_subscription']              = true;
                            $pdata['subscription_price']           = (string) WC_Subscriptions_Product::get_price( $wc_prod );
                            $pdata['subscription_period']          = $sub_period;
                            $pdata['subscription_period_interval'] = (string) WC_Subscriptions_Product::get_interval( $wc_prod );
                            $pdata['subscription_length']          = (string) WC_Subscriptions_Product::get_length( $wc_prod );
                            $pdata['subscription_trial_length']    = (string) WC_Subscriptions_Product::get_trial_length( $wc_prod );
                            $pdata['subscription_trial_period']    = (string) WC_Subscriptions_Product::get_trial_period( $wc_prod );
                            $pdata['subscription_sign_up_fee']     = (string) WC_Subscriptions_Product::get_sign_up_fee( $wc_prod );
                            $pdata['type']                         = $wc_prod->get_type();
                        }
                    } catch ( \Exception $e ) {
                        $sub_period = '';
                    }
                }
            }
            if ( empty( $sub_period ) ) {
                $sub_period = get_post_meta( $pid, '_subscription_period', true );
                if ( ! empty( $sub_period ) ) {
                    $pdata['is_subscription']              = true;
                    $pdata['subscription_price']           = get_post_meta( $pid, '_subscription_price', true );
                    $pdata['subscription_period']          = $sub_period;
                    $pdata['subscription_period_interval'] = get_post_meta( $pid, '_subscription_period_interval', true );
                    $pdata['subscription_length']          = get_post_meta( $pid, '_subscription_length', true );
                    $pdata['subscription_trial_length']    = get_post_meta( $pid, '_subscription_trial_length', true );
                    $pdata['subscription_trial_period']    = get_post_meta( $pid, '_subscription_trial_period', true );
                    $pdata['subscription_sign_up_fee']     = get_post_meta( $pid, '_subscription_sign_up_fee', true );
                    $pdata['type']                         = get_post_meta( $pid, '_product_type', true ) ?: 'subscription';
                }
            }

            $products[] = $pdata;
        }
        wp_reset_postdata();
    }

    vendor_api_respond( [ 'products' => $products, 'store_id' => $store_id, 'count' => count( $products ) ] );
}

// ── get_user ───────────────────────────────────────────────────────────
// GET /?action=get_user
// Returns WordPress user profile data — the same data the my-account
// dashboard shows (display_name, username, email, capabilities).
if ( $action === 'get_user' ) {
    $user = get_userdata( $user_id );
    if ( ! $user ) {
        vendor_api_respond( [ 'error' => 'User not found.' ], 404 );
    }

    $is_vendor = function_exists( 'dokan_is_user_seller' ) && dokan_is_user_seller( $user_id );

    vendor_api_respond( [
        'id'           => $user_id,
        'username'     => $user->user_login,
        'display_name' => $user->display_name,
        'first_name'   => get_user_meta( $user_id, 'first_name', true ) ?: '',
        'last_name'    => get_user_meta( $user_id, 'last_name', true ) ?: '',
        'email'        => $user->user_email,
        'is_vendor'    => $is_vendor,
        'avatar_url'   => get_avatar_url( $user_id ),
        'registered'   => $user->user_registered,
    ] );
}

// ── get_customer ──────────────────────────────────────────────────────
// GET /?action=get_customer
// Returns WC customer data (billing, shipping) for the authenticated user.
if ( $action === 'get_customer' ) {
    $user      = get_userdata( $user_id );
    $cust_data = [];

    // Resolve WC customer ID from WP user ID (they are NOT the same).
    $customer_id = vendor_api_find_customer_id( $user_id );

    if ( $customer_id && class_exists( 'WC_Customer' ) ) {
        $customer = new WC_Customer( $customer_id );
        if ( $customer && $customer->get_id() ) {
            $cust_data = [
                'id'         => $customer->get_id(),
                'email'      => $customer->get_email(),
                'first_name' => $customer->get_first_name(),
                'last_name'  => $customer->get_last_name(),
                'billing'    => [
                    'first_name' => $customer->get_billing_first_name(),
                    'last_name'  => $customer->get_billing_last_name(),
                    'company'    => $customer->get_billing_company(),
                    'address_1'  => $customer->get_billing_address_1(),
                    'address_2'  => $customer->get_billing_address_2(),
                    'city'       => $customer->get_billing_city(),
                    'state'      => $customer->get_billing_state(),
                    'postcode'   => $customer->get_billing_postcode(),
                    'country'    => $customer->get_billing_country(),
                    'phone'      => $customer->get_billing_phone(),
                    'email'      => $customer->get_billing_email(),
                ],
                'shipping'   => [
                    'first_name' => $customer->get_shipping_first_name(),
                    'last_name'  => $customer->get_shipping_last_name(),
                    'company'    => $customer->get_shipping_company(),
                    'address_1'  => $customer->get_shipping_address_1(),
                    'address_2'  => $customer->get_shipping_address_2(),
                    'city'       => $customer->get_shipping_city(),
                    'state'      => $customer->get_shipping_state(),
                    'postcode'   => $customer->get_shipping_postcode(),
                    'country'    => $customer->get_shipping_country(),
                ],
            ];
        }
    }

    // Merge with user meta (always include both sources for completeness)
    if ( $user ) {
        $cust_data = array_merge( [
            'id'           => $user_id,
            'username'     => $user->user_login,
            'display_name' => $user->display_name,
            'email'        => $user->user_email,
            'first_name'   => $cust_data['first_name'] ?? get_user_meta( $user_id, 'first_name', true ) ?: '',
            'last_name'    => $cust_data['last_name'] ?? get_user_meta( $user_id, 'last_name', true ) ?: '',
        ], $cust_data );

        // Ensure billing/shipping are always present (from user meta as ultimate fallback)
        if ( empty( $cust_data['billing'] ) ) {
            $cust_data['billing'] = [];
        }
        $cust_data['billing'] = array_merge( [
            'first_name' => get_user_meta( $user_id, 'billing_first_name', true ),
            'last_name'  => get_user_meta( $user_id, 'billing_last_name', true ),
            'address_1'  => get_user_meta( $user_id, 'billing_address_1', true ),
            'address_2'  => get_user_meta( $user_id, 'billing_address_2', true ),
            'city'       => get_user_meta( $user_id, 'billing_city', true ),
            'state'      => get_user_meta( $user_id, 'billing_state', true ),
            'postcode'   => get_user_meta( $user_id, 'billing_postcode', true ),
            'country'    => get_user_meta( $user_id, 'billing_country', true ),
            'phone'      => get_user_meta( $user_id, 'billing_phone', true ),
        ], $cust_data['billing'] );

        if ( empty( $cust_data['shipping'] ) ) {
            $cust_data['shipping'] = [];
        }
        $cust_data['shipping'] = array_merge( [
            'first_name' => get_user_meta( $user_id, 'shipping_first_name', true ),
            'last_name'  => get_user_meta( $user_id, 'shipping_last_name', true ),
            'address_1'  => get_user_meta( $user_id, 'shipping_address_1', true ),
            'address_2'  => get_user_meta( $user_id, 'shipping_address_2', true ),
            'city'       => get_user_meta( $user_id, 'shipping_city', true ),
            'state'      => get_user_meta( $user_id, 'shipping_state', true ),
            'postcode'   => get_user_meta( $user_id, 'shipping_postcode', true ),
            'country'    => get_user_meta( $user_id, 'shipping_country', true ),
        ], $cust_data['shipping'] );
    }

    vendor_api_respond( $cust_data );
}

// ── update_customer ────────────────────────────────────────────────────
// POST /?action=update_customer
// Body: { "billing": {...}, "shipping": {...} }
// Uses WC_Customer class for proper validation.
if ( $action === 'update_customer' ) {
    if ( $_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'PUT' ) {
        vendor_api_respond( [ 'error' => 'Use POST or PUT.', 'code' => 'bad_method' ], 405 );
    }

    $body  = file_get_contents( 'php://input' );
    $input = json_decode( $body, true );

    if ( ! $input ) {
        vendor_api_respond( [ 'error' => 'Invalid JSON body.', 'code' => 'bad_json' ], 400 );
    }

    $customer    = null;
    $customer_id = vendor_api_find_customer_id( $user_id );
    if ( $customer_id && class_exists( 'WC_Customer' ) ) {
        $customer = new WC_Customer( $customer_id );
    }

    // Update billing address
    if ( isset( $input['billing'] ) && is_array( $input['billing'] ) ) {
        $b = $input['billing'];
        if ( $customer && $customer->get_id() ) {
            if ( isset( $b['address_1'] ) ) $customer->set_billing_address_1( sanitize_text_field( $b['address_1'] ) );
            if ( isset( $b['address_2'] ) ) $customer->set_billing_address_2( sanitize_text_field( $b['address_2'] ) );
            if ( isset( $b['city'] ) )      $customer->set_billing_city( sanitize_text_field( $b['city'] ) );
            if ( isset( $b['state'] ) )     $customer->set_billing_state( sanitize_text_field( $b['state'] ) );
            if ( isset( $b['postcode'] ) )  $customer->set_billing_postcode( sanitize_text_field( $b['postcode'] ) );
            if ( isset( $b['country'] ) )   $customer->set_billing_country( sanitize_text_field( $b['country'] ) );
            if ( isset( $b['phone'] ) )     $customer->set_billing_phone( sanitize_text_field( $b['phone'] ) );
        } else {
            foreach ( [ 'address_1', 'address_2', 'city', 'state', 'postcode', 'country', 'phone' ] as $field ) {
                if ( isset( $b[ $field ] ) ) {
                    update_user_meta( $user_id, "billing_$field", sanitize_text_field( $b[ $field ] ) );
                }
            }
        }
    }

    // Update shipping address
    if ( isset( $input['shipping'] ) && is_array( $input['shipping'] ) ) {
        $s = $input['shipping'];
        if ( $customer && $customer->get_id() ) {
            if ( isset( $s['address_1'] ) ) $customer->set_shipping_address_1( sanitize_text_field( $s['address_1'] ) );
            if ( isset( $s['address_2'] ) ) $customer->set_shipping_address_2( sanitize_text_field( $s['address_2'] ) );
            if ( isset( $s['city'] ) )      $customer->set_shipping_city( sanitize_text_field( $s['city'] ) );
            if ( isset( $s['state'] ) )     $customer->set_shipping_state( sanitize_text_field( $s['state'] ) );
            if ( isset( $s['postcode'] ) )  $customer->set_shipping_postcode( sanitize_text_field( $s['postcode'] ) );
            if ( isset( $s['country'] ) )   $customer->set_shipping_country( sanitize_text_field( $s['country'] ) );
        } else {
            foreach ( [ 'address_1', 'address_2', 'city', 'state', 'postcode', 'country' ] as $field ) {
                if ( isset( $s[ $field ] ) ) {
                    update_user_meta( $user_id, "shipping_$field", sanitize_text_field( $s[ $field ] ) );
                }
            }
        }
    }

    if ( $customer && $customer->get_id() ) {
        $customer->save();
    }

    vendor_api_respond( [ 'success' => true, 'user_id' => $user_id ] );
}

// ── update_user ─────────────────────────────────────────────────────────
// POST /?action=update_user
// Body: { "first_name": "...", "last_name": "...", "email": "...", "password": "...", "old_password": "..." }
// Password change requires old_password verification.
if ( $action === 'update_user' ) {
    if ( $_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'PUT' ) {
        vendor_api_respond( [ 'error' => 'Use POST or PUT.', 'code' => 'bad_method' ], 405 );
    }

    $body  = file_get_contents( 'php://input' );
    $input = json_decode( $body, true );

    if ( ! $input ) {
        vendor_api_respond( [ 'error' => 'Invalid JSON body.', 'code' => 'bad_json' ], 400 );
    }

    // If changing password, verify the old one first
    if ( ! empty( $input['password'] ) ) {
        if ( empty( $input['old_password'] ) ) {
            vendor_api_respond( [ 'error' => 'Current password is required to set a new password.', 'code' => 'old_password_required' ], 400 );
        }
        $current_user = get_userdata( $user_id );
        if ( ! $current_user || ! wp_check_password( $input['old_password'], $current_user->user_pass, $user_id ) ) {
            vendor_api_respond( [ 'error' => 'Current password is incorrect.', 'code' => 'old_password_wrong' ], 400 );
        }
    }

    $user_data = [ 'ID' => $user_id ];

    if ( isset( $input['first_name'] ) ) {
        $user_data['first_name'] = sanitize_text_field( $input['first_name'] );
    }
    if ( isset( $input['last_name'] ) ) {
        $user_data['last_name'] = sanitize_text_field( $input['last_name'] );
    }
    if ( isset( $input['email'] ) && is_email( $input['email'] ) ) {
        $user_data['user_email'] = sanitize_email( $input['email'] );
    }

    $result = wp_update_user( $user_data );

    if ( is_wp_error( $result ) ) {
        vendor_api_respond( [ 'error' => $result->get_error_message(), 'code' => 'update_failed' ], 400 );
    }

    // Password change (old password already verified above)
    if ( ! empty( $input['password'] ) && strlen( $input['password'] ) >= 6 ) {
        wp_set_password( $input['password'], $user_id );
    }

    vendor_api_respond( [ 'success' => true, 'user_id' => $user_id ] );
}

// ── get_orders_user ────────────────────────────────────────────────────
// GET /?action=get_orders_user&per_page=20&page=1
// Returns WC orders for the authenticated customer (not vendor orders).
if ( $action === 'get_orders_user' ) {
    $per_page  = max( 1, min( 50, (int) ( $_GET['per_page'] ?? 20 ) ) );
    $page      = max( 1, (int) ( $_GET['page'] ?? 1 ) );

    $args = [
        'limit'       => $per_page,
        'page'        => $page,
        'customer_id' => $user_id,
        'type'        => 'shop_order',
        'orderby'     => 'date',
        'order'       => 'DESC',
    ];

    $orders = [];
    if ( class_exists( 'WooCommerce' ) ) {
        $order_ids = wc_get_orders( array_merge( $args, [ 'return' => 'ids' ] ) );
        foreach ( $order_ids as $oid ) {
            $order = wc_get_order( $oid );
            if ( ! $order ) continue;

            $items = [];
            foreach ( $order->get_items() as $item ) {
                $product = $item->get_product();
                $items[] = [
                    'id'                  => $item->get_id(),
                    'name'                => $item->get_name(),
                    'product_id'          => $item->get_product_id(),
                    'quantity'            => $item->get_quantity(),
                    'total'               => $item->get_total(),
                    'downloadable'        => $product ? $product->is_downloadable() : false,
                    'meta_data'           => $item->get_meta_data(),
                ];
            }

            $orders[] = [
                'id'              => $order->get_id(),
                'order_number'    => $order->get_order_number(),
                'status'          => $order->get_status(),
                'date_created'    => $order->get_date_created() ? $order->get_date_created()->format( 'Y-m-d H:i:s' ) : '',
                'total'           => $order->get_total(),
                'currency'        => $order->get_currency(),
                'line_items'      => $items,
                'items_count'     => count( $items ),
            ];
        }
    }

    vendor_api_respond( [ 'orders' => $orders ] );
}

// ── update_order_status ────────────────────────────────────────────────
// POST /vendor-api.php?action=update_order_status
// Body: { "order_id": N, "status": "completed" }
if ( $action === 'update_order_status' ) {
    vendor_api_require_vendor( $user_id );

    if ( $_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'PUT' ) {
        vendor_api_respond( [ 'error' => 'Use POST or PUT.', 'code' => 'bad_method' ], 405 );
    }

    $body  = file_get_contents( 'php://input' );
    $input = json_decode( $body, true );
    if ( ! $input ) {
        vendor_api_respond( [ 'error' => 'Invalid JSON body.', 'code' => 'bad_json' ], 400 );
    }

    $order_id = absint( $input['order_id'] ?? ( $_GET['order_id'] ?? 0 ) );
    $status   = sanitize_key( $input['status'] ?? '' );
    if ( ! $order_id || ! $status ) {
        vendor_api_respond( [ 'error' => 'order_id and status are required.', 'code' => 'bad_request' ], 400 );
    }

    $allowed = [ 'pending', 'processing', 'on-hold', 'completed', 'cancelled', 'refunded', 'failed' ];
    if ( ! in_array( $status, $allowed, true ) ) {
        vendor_api_respond( [ 'error' => 'Invalid order status.', 'code' => 'bad_request' ], 400 );
    }

    $order = function_exists( 'wc_get_order' ) ? wc_get_order( $order_id ) : null;
    if ( ! $order ) {
        vendor_api_respond( [ 'error' => 'Order not found.', 'code' => 'not_found' ], 404 );
    }

    // Verify ownership — Dokan links orders to vendors via meta or line items.
    $vendor   = dokan()->vendor->get( $user_id );
    $store_id = $vendor ? (int) $vendor->get_id() : 0;
    $owns     = $store_id > 0 && (int) $order->get_meta( '_dokan_vendor_id' ) === $store_id;

    if ( ! $owns && $store_id > 0 ) {
        foreach ( $order->get_items() as $item ) {
            $pid = (int) $item->get_product_id();
            if ( ! $pid ) continue;
            if ( (int) get_post_field( 'post_author', $pid ) === $user_id
                || (int) get_post_meta( $pid, '_dokan_vendor_id', true ) === $store_id ) {
                $owns = true;
                break;
            }
        }
    }

    if ( ! $owns ) {
        vendor_api_respond( [ 'error' => 'You do not own this order.', 'code' => 'forbidden' ], 403 );
    }

    $order->update_status( $status );
    vendor_api_respond( [ 'success' => true, 'order_id' => $order_id, 'status' => $status ] );
}

// ── request_withdrawal ─────────────────────────────────────────────────
// POST /vendor-api.php?action=request_withdrawal
// Body: { "amount": 10.00, "method": "bank" }
//
// DB SCHEMA (confirmed from u910292103_0z5JM.sql lines 133530-133540):
//   CREATE TABLE wp_dokan_withdraw (
//     id bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT,
//     user_id bigint(20) UNSIGNED NOT NULL,
//     amount decimal(19,4) NOT NULL,
//     date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
//     status int(1) NOT NULL DEFAULT 0,    -- 0 = pending, 1 = approved/paid
//     method varchar(30) NOT NULL,
//     note text NOT NULL DEFAULT '',
//     details longtext DEFAULT NULL,       -- serialized assoc array of method settings
//     ip varchar(50) NOT NULL DEFAULT '',
//     PRIMARY KEY (id)
//   );
if ( $action === 'request_withdrawal' ) {
    vendor_api_require_vendor( $user_id );

    if ( $_SERVER['REQUEST_METHOD'] !== 'POST' ) {
        vendor_api_respond( [ 'error' => 'Use POST.', 'code' => 'bad_method' ], 405 );
    }

    // ── 1. Read & validate JSON body ───────────────────────────────────
    $body  = file_get_contents( 'php://input' );
    $input = json_decode( $body, true );
    if ( ! is_array( $input ) ) {
        // Also accept application/x-www-form-urlencoded as a fallback for
        // older Dokan REST clients.
        if ( ! empty( $_POST ) ) {
            $input = $_POST;
        } else {
            vendor_api_respond( [
                'error' => 'Invalid JSON body. Expected {"amount":N,"method":"bank"}',
                'code'  => 'bad_json',
                'raw_body_preview' => substr( $body, 0, 200 ),
            ], 400 );
        }
    }

    $amount_raw = $input['amount'] ?? 0;
    $amount     = is_numeric( $amount_raw ) ? (float) $amount_raw : (float) preg_replace( '/[^0-9.]/', '', (string) $amount_raw );
    $method     = substr( trim( (string) ( $input['method'] ?? 'bank' ) ), 0, 30 );
    $note       = substr( trim( (string) ( $input['note'] ?? '' ) ), 0, 65535 );
    $details    = is_array( $input['details'] ?? null ) ? $input['details'] : [];
    $ip         = substr( (string) ( $_SERVER['REMOTE_ADDR'] ??
                       $_SERVER['HTTP_X_FORWARDED_FOR'] ??
                       $_SERVER['HTTP_CLIENT_IP'] ?? '' ), 0, 50 );

    // ── 2. Business validation ─────────────────────────────────────────
    if ( $amount <= 0 ) {
        vendor_api_respond( [
            'error'   => 'Amount must be greater than zero.',
            'code'    => 'bad_amount',
            'amount'  => $amount,
        ], 400 );
    }

    // Method whitelist — matches Dokan Lite built-in methods + common Pro
    $allowed_methods = [ 'bank', 'paypal', 'skrill', 'stripe', 'by_cash', 'dokan_custom_gateway',
                         'paystack', 'razorpay', 'mollie', 'bacs', 'cheque', 'cod' ];
    $method_lower    = strtolower( $method );
    if ( ! in_array( $method_lower, $allowed_methods, true ) ) {
        // Allow unknown but still-length-safe methods (plugins may add new ones)
        if ( strlen( $method ) > 30 || $method === '' ) {
            vendor_api_respond( [
                'error' => 'Invalid payment method.',
                'code'  => 'bad_method_value',
                'allowed' => $allowed_methods,
                'received' => $method,
            ], 400 );
        }
    }

    // ── 3. Available balance check (multi-source fallback) ─────────────
    $balance = null;

    // Source A: dokan_get_seller_balance (if available)
    if ( $balance === null && function_exists( 'dokan_get_seller_balance' ) ) {
        try {
            $bal_fn = (float) dokan_get_seller_balance( $user_id, false );
            if ( $bal_fn >= 0 ) $balance = $bal_fn;
        } catch ( \Throwable $e ) { $balance = null; }
    }

    // Source B: direct wp_dokan_vendor_balance ledger calculation
    // (identical to get_reports — most reliable on Dokan Lite)
    if ( $balance === null ) {
        global $wpdb;
        $credit  = (float) $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(debit), 0) FROM {$wpdb->dokan_vendor_balance}
             WHERE vendor_id = %d AND trn_type = 'dokan_orders' AND status = 1",
            $user_id
        ) );
        $debit   = (float) $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(credit), 0) FROM {$wpdb->dokan_vendor_balance}
             WHERE vendor_id = %d AND trn_type = 'dokan_orders' AND status = 1",
            $user_id
        ) );
        $withdrawn = (float) $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(credit), 0) FROM {$wpdb->dokan_vendor_balance}
             WHERE vendor_id = %d AND trn_type = 'dokan_withdraw' AND status = 1",
            $user_id
        ) );
        $pending   = (float) $wpdb->get_var( $wpdb->prepare(
            "SELECT COALESCE(SUM(credit), 0) FROM {$wpdb->dokan_vendor_balance}
             WHERE vendor_id = %d AND trn_type = 'dokan_withdraw' AND status = 0",
            $user_id
        ) );
        $calc = max( 0.0, $credit - $debit - $withdrawn - $pending );
        if ( $calc >= 0 ) $balance = $calc;
    }

    if ( $balance !== null && $amount > $balance ) {
        vendor_api_respond( [
            'error'   => 'Withdrawal amount exceeds your available balance.',
            'code'    => 'insufficient_balance',
            'requested' => $amount,
            'available' => $balance,
        ], 400 );
    }

    // ── 4. Build normalized details array (serialized by maybe_serialize)
    $currency = function_exists( 'get_woocommerce_currency' ) ? get_woocommerce_currency() : 'GBP';
    $vendor_billing = get_user_meta( $user_id, 'dokan_profile_settings', true );
    $vendor_billing = is_array( $vendor_billing ) ? $vendor_billing : [];
    $payment_settings = $vendor_billing['payment'] ?? [];
    $payment_settings = is_array( $payment_settings ) ? $payment_settings : [];
    $method_settings  = $payment_settings[ $method ] ?? $payment_settings[ $method_lower ] ?? [];
    $method_settings  = is_array( $method_settings ) ? $method_settings : [];

    // DB INSERT shape matches existing sample row (sql line 133548):
    // a:12:{s:7:"ac_name";s:14:"ZZMORE LIMITED";s:9:"ac_number";...}
    $details_normalized = array_merge( [
        'withdraw_amount'   => number_format( $amount, 2, '.', '' ),
        'currency'          => $currency,
        'email'             => (string) ( get_userdata( $user_id )->user_email ?? '' ),
        'order_ids'         => '',
        'commission_ids'    => '',
        'withdraw_charges'  => '',
        'withdraw_mode'     => 'by_request',
        'is_auto_withdrawal'=> '',
        'withdraw_paid_date'=> '',
    ], $method_settings, $details );

    // ── 5. PRIMARY PATH: DIRECT SQL INSERT INTO wp_dokan_withdraw ──────
    // (This is the most reliable method because it follows the exact DB
    //  schema we confirmed.  Dokan's PHP wrapper often fails silently on
    //  Dokan Lite when the Withdraw class isn't fully bootstrapped.)
    global $wpdb;
    $table = $wpdb->prefix . 'dokan_withdraw';
    $result = false;
    $sql_errors = [];

    $insert_payload = [
        'user_id' => $user_id,
        'amount'  => number_format( $amount, 4, '.', '' ),  // decimal(19,4)
        'date'    => current_time( 'mysql' ),               // timestamp
        'status'  => 0,                                      // int(1) 0 = pending
        'method'  => $method_lower,                          // varchar(30)
        'note'    => $note,                                  // text
        'details' => maybe_serialize( (object) $details_normalized ), // longtext serialized
        'ip'      => $ip,                                    // varchar(50)
    ];

    $insert_formats = [ '%d', '%s', '%s', '%d', '%s', '%s', '%s', '%s' ];

    try {
        // Ensure WPDB error mode is visible
        $wpdb->hide_errors();
        $did_insert = $wpdb->insert( $table, $insert_payload, $insert_formats );
        if ( $did_insert !== false && is_numeric( $wpdb->insert_id ) && (int) $wpdb->insert_id > 0 ) {
            $result = (int) $wpdb->insert_id;
        } else {
            $sql_errors[] = $wpdb->last_error ?: 'wpdb->insert returned false';
            $sql_errors[] = 'last_query: ' . substr( $wpdb->last_query, 0, 500 );
        }
    } catch ( \Throwable $e ) {
        $sql_errors[] = 'Exception: ' . $e->getMessage();
    }

    // ── 6. FALLBACK 1: dokan()->withdraw->insert_withdraw_request ─────
    if ( ! $result ) {
        $manager = null;
        if ( function_exists( 'dokan' ) && isset( dokan()->withdraw ) ) {
            try { $manager = dokan()->withdraw; } catch ( \Throwable $e ) { $manager = null; }
        }
        $args = [
            'user_id' => $user_id,
            'amount'  => $amount,
            'method'  => $method_lower,
            'note'    => $note,
            'ip'      => $ip,
            'details' => $details_normalized,
            'status'  => 0,
            'date'    => current_time( 'mysql' ),
        ];
        if ( is_object( $manager ) && method_exists( $manager, 'insert_withdraw_request' ) ) {
            try {
                $res = $manager->insert_withdraw_request( $args );
                if ( is_wp_error( $res ) ) {
                    $sql_errors[] = 'dokan()->withdraw: ' . $res->get_error_message();
                } elseif ( $res && is_numeric( $res ) ) {
                    $result = (int) $res;
                } elseif ( $res && is_object( $res ) && isset( $res->id ) ) {
                    $result = (int) $res->id;
                }
            } catch ( \Throwable $e ) {
                $sql_errors[] = 'dokan()->withdraw Exception: ' . $e->getMessage();
            }
        }
    }

    // ── 7. FALLBACK 2: dokan_withdraw() helper ─────────────────────────
    if ( ! $result && function_exists( 'dokan_withdraw' ) ) {
        try {
            $res = dokan_withdraw()->insert_withdraw_request( $args );
            if ( is_wp_error( $res ) ) {
                $sql_errors[] = 'dokan_withdraw(): ' . $res->get_error_message();
            } elseif ( $res && is_numeric( $res ) ) {
                $result = (int) $res;
            } elseif ( $res && is_object( $res ) && isset( $res->id ) ) {
                $result = (int) $res->id;
            }
        } catch ( \Throwable $e ) {
            $sql_errors[] = 'dokan_withdraw() Exception: ' . $e->getMessage();
        }
    }

    // ── 8. Final result check ──────────────────────────────────────────
    if ( is_wp_error( $result ) ) {
        vendor_api_respond( [
            'error' => $result->get_error_message(),
            'code'  => 'withdraw_failed',
            'tried' => [ 'sql_insert', 'dokan()->withdraw', 'dokan_withdraw()' ],
            'sql_errors' => $sql_errors,
        ], 400 );
    }

    if ( ! $result ) {
        vendor_api_respond( [
            'error' => 'Unable to create withdrawal request.',
            'code'  => 'withdraw_failed',
            'requested' => [
                'user_id' => $user_id,
                'amount'  => $amount,
                'method'  => $method_lower,
                'balance' => $balance,
                'ip'      => $ip,
            ],
            'tried' => [ 'sql_insert', 'dokan()->withdraw', 'dokan_withdraw()' ],
            'sql_errors' => $sql_errors,
        ], 400 );
    }

    vendor_api_respond( [
        'success'       => true,
        'withdrawal_id' => (int) $result,
        'amount'        => $amount,
        'method'        => $method_lower,
        'status'        => 0,  // pending (admin must approve)
        'balance_after' => $balance !== null ? max( 0.0, $balance - $amount ) : null,
    ] );
}

// ── Unknown action ────────────────────────────────────────────────────
vendor_api_respond( [
    'error' => 'Unknown action.',
    'code'  => 'bad_action',
    'supported' => [
        'ping', 'get_store', 'get_reports', 'get_products',
        'get_orders', 'get_balance', 'get_coupons', 'get_reviews',
        'get_announcements', 'update_store', 'get_store_products',
        'get_user', 'get_customer', 'update_customer', 'update_user', 'get_orders_user',
        'get_store_public', 'get_store_reviews', 'update_order_status', 'request_withdrawal',
    ],
], 400 );
