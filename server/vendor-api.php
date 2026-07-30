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
if ( $action === 'get_reports' ) {
    vendor_api_require_vendor( $user_id );

    $vendor     = dokan()->vendor->get( $user_id );
    $store_id   = $vendor->get_id();
    $results    = [];

    // 1. Sales & orders from Dokan's built-in reports
    if ( function_exists( 'dokan_get_sales_report_data' ) ) {
        try {
            $report = dokan_get_sales_report_data( $store_id );
            $results['sales']    = isset($report['sales']) ? (string)$report['sales'] : '0';
            $results['earnings'] = isset($report['earning']) ? (string)$report['earning'] : (isset($report['earnings']) ? (string)$report['earnings'] : '0');
            $results['orders']   = isset($report['orders']) ? (int)$report['orders'] : 0;
        } catch ( \Exception $e ) {}
    }

    // 2. Order counts by status — always run for accurate counts
    if ( class_exists( 'WooCommerce' ) ) {
        $statuses = [ 'wc-pending' => 'pending', 'wc-processing' => 'processing', 'wc-on-hold' => 'on-hold', 'wc-completed' => 'completed', 'wc-cancelled' => 'cancelled', 'wc-refunded' => 'refunded', 'wc-failed' => 'failed' ];
        $total_orders = 0;
        foreach ( $statuses as $wc_status => $short ) {
            $args = [
                'limit'    => -1,
                'return'   => 'ids',
                'meta_key' => '_dokan_vendor_id',
                'meta_value'=> $store_id,
                'type'     => 'shop_order',
                'status'   => $wc_status,
            ];
            try {
                $count = count( wc_get_orders( $args ) );
                $results[ $short ] = $count;
                $total_orders += $count;
            } catch ( \Exception $e ) {
                $results[ $short ] = 0;
            }
        }
        // Use the WC order count if Dokan reports didn't provide it
        if ( empty( $results['orders'] ) ) {
            $results['orders'] = $total_orders;
        }
    }

    // 3. Product count
    try {
        $product_args = [
            'author'      => $user_id,
            'post_type'   => 'product',
            'post_status' => [ 'publish', 'draft', 'pending' ],
            'posts_per_page' => -1,
            'fields'      => 'ids',
        ];
        $product_query = new WP_Query( $product_args );
        $results['products'] = $product_query->found_posts;
    } catch ( \Exception $e ) {
        $results['products'] = 0;
    }

    // 4. Page views (Dokan Pro)
    if ( function_exists( 'dokan_get_store_pageviews' ) ) {
        $results['pageviews'] = dokan_get_store_pageviews( $store_id );
    }

    // 5. Balance
    if ( function_exists( 'dokan_get_seller_balance' ) ) {
        $results['current_balance'] = (string) dokan_get_seller_balance( $user_id, false );
    }

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

        $products[] = [
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

// ── Unknown action ────────────────────────────────────────────────────
vendor_api_respond( [
    'error' => 'Unknown action.',
    'code'  => 'bad_action',
    'supported' => [
        'ping', 'get_store', 'get_reports', 'get_products',
        'get_orders', 'get_balance', 'get_coupons', 'get_reviews',
        'get_announcements', 'update_store', 'get_store_products',
        'get_user', 'get_customer', 'update_customer', 'update_user', 'get_orders_user',
    ],
], 400 );
