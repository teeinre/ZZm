<?php
/**
 * Plugin Name: Dokan Vendor Bridge for zzmore.store
 * Description: Reliable vendor store settings endpoint that reads directly from
 *              Dokan's internal PHP objects (bypassing inconsistent REST API).
 *
 * Endpoint: GET /wp-json/vendor-bridge/v1/store/me
 *           PUT /wp-json/vendor-bridge/v1/store/me
 *
 * Requires: JWT Auth plugin + Dokan Pro active
 * Install:  Drop in wp-content/mu-plugins/dokan-vendor-bridge.php
 */

if ( ! defined( 'ABSPATH' ) ) exit;

// =========================================================================
// JWT Auth Compatibility — ensures is_user_logged_in() works for this
// plugin's REST routes even if no other plugin hooks determine_current_user.
// =========================================================================
add_filter( 'determine_current_user', function ( $user_id ) {
    // If already determined by a cookie or JWT plugin, keep it.
    if ( $user_id > 0 ) {
        return $user_id;
    }

    $jwt_token = '';

    // 1. Try Authorization header first
    $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ( empty( $auth_header ) && function_exists( 'getallheaders' ) ) {
        $headers = getallheaders();
        $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    if ( $auth_header && preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $matches ) ) {
        $jwt_token = $matches[1];
    }

    // 2. Fallback: ?token= query parameter (LiteSpeed strips Authorization header)
    if ( empty( $jwt_token ) && ! empty( $_GET['token'] ) ) {
        $jwt_token = $_GET['token'];
    }

    // 3. Fallback: X-JWT-Token custom header (alternative to Authorization)
    if ( empty( $jwt_token ) ) {
        $custom_header = $_SERVER['HTTP_X_JWT_TOKEN'] ?? '';
        if ( ! empty( $custom_header ) ) {
            $jwt_token = $custom_header;
        } elseif ( function_exists( 'getallheaders' ) ) {
            $headers = getallheaders();
            $jwt_token = $headers['X-JWT-Token'] ?? $headers['x-jwt-token'] ?? '';
        }
    }

    if ( empty( $jwt_token ) ) {
        return $user_id;
    }

    // Try the JWT Auth plugin's validation function
    if ( function_exists( 'jwt_auth_get_user_from_token' ) ) {
        try {
            $user = jwt_auth_get_user_from_token( $jwt_token );
            if ( $user && ! is_wp_error( $user ) && isset( $user->ID ) ) {
                wp_set_current_user( $user->ID );
                return $user->ID;
            }
        } catch ( \Exception $e ) {}
    }

    // Fallback: manual JWT decode (if JWT_AUTH_SECRET_KEY is defined)
    if ( defined( 'JWT_AUTH_SECRET_KEY' ) ) {
        try {
            // Check multiple JWT class locations
            $decoded = null;
            if ( class_exists( '\Firebase\JWT\JWT' ) ) {
                $decoded = \Firebase\JWT\JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
            } elseif ( class_exists( 'JWT' ) ) {
                $decoded = \JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
            }
            if ( $decoded && isset( $decoded->data->user->id ) ) {
                $user_id = (int) $decoded->data->user->id;
                wp_set_current_user( $user_id );
                return $user_id;
            }
        } catch ( \Exception $e ) {}
    }

    return $user_id;
}, 20 );

// =========================================================================
// WooCommerce Subscriptions — expose meta on /wc/v3/products REST response
// WooCommerce Subscriptions does NOT include subscription meta fields in
// the standard product REST response, so the Flutter app sees isSubscription
// as false for every product.  This filter injects all required fields at
// both the top level and into the meta_data list so either extraction path
// in Product.fromJson() succeeds.
// =========================================================================
add_filter( 'woocommerce_rest_prepare_product_object', function ( WP_REST_Response $response, $product, $request ) {
    $data = $response->get_data();

    $is_subscription = false;
    if ( class_exists( 'WC_Subscriptions_Product' ) ) {
        try {
            $price      = (string) WC_Subscriptions_Product::get_price( $product );
            $period     = (string) WC_Subscriptions_Product::get_period( $product );
            $interval   = (string) WC_Subscriptions_Product::get_interval( $product );
            $length     = (string) WC_Subscriptions_Product::get_length( $product );
            $trial_len  = (string) WC_Subscriptions_Product::get_trial_length( $product );
            $trial_per  = (string) WC_Subscriptions_Product::get_trial_period( $product );
            $signup_fee = (string) WC_Subscriptions_Product::get_sign_up_fee( $product );

            $is_subscription = ! empty( $period );

            $data['is_subscription']              = $is_subscription;
            $data['subscription_price']           = $price;
            $data['subscription_period']          = $period;
            $data['subscription_period_interval'] = $interval;
            $data['subscription_length']          = $length;
            $data['subscription_trial_length']    = $trial_len;
            $data['subscription_trial_period']    = $trial_per;
            $data['subscription_sign_up_fee']     = $signup_fee;

            // Also inject into the meta_data list so the Flutter loop finds them
            $subscription_meta = [
                '_subscription_price'           => $price,
                '_subscription_period'          => $period,
                '_subscription_period_interval' => $interval,
                '_subscription_length'          => $length,
                '_subscription_trial_length'    => $trial_len,
                '_subscription_trial_period'    => $trial_per,
                '_subscription_sign_up_fee'     => $signup_fee,
            ];
            if ( empty( $data['meta_data'] ) ) {
                $data['meta_data'] = [];
            }
            foreach ( $subscription_meta as $key => $value ) {
                $found = false;
                foreach ( $data['meta_data'] as &$md ) {
                    if ( is_object( $md ) ) {
                        if ( $md->key === $key ) { $md->value = $value; $found = true; break; }
                    } elseif ( is_array( $md ) ) {
                        if ( ( $md['key'] ?? '' ) === $key ) { $md['value'] = $value; $found = true; break; }
                    }
                }
                unset( $md );
                if ( ! $found ) {
                    $data['meta_data'][] = (object) [ 'id' => 0, 'key' => $key, 'value' => $value ];
                }
            }
        } catch ( \Exception $e ) {
            $data['is_subscription'] = false;
        }
    } else {
        // Fallback: read directly from post meta if the helper class isn't loaded
        $period = get_post_meta( $product->get_id(), '_subscription_period', true );
        if ( ! empty( $period ) ) {
            $is_subscription = true;
            $data['is_subscription']              = true;
            $data['subscription_price']           = get_post_meta( $product->get_id(), '_subscription_price', true );
            $data['subscription_period']          = $period;
            $data['subscription_period_interval'] = get_post_meta( $product->get_id(), '_subscription_period_interval', true );
            $data['subscription_length']          = get_post_meta( $product->get_id(), '_subscription_length', true );
            $data['subscription_trial_length']    = get_post_meta( $product->get_id(), '_subscription_trial_length', true );
            $data['subscription_trial_period']    = get_post_meta( $product->get_id(), '_subscription_trial_period', true );
            $data['subscription_sign_up_fee']     = get_post_meta( $product->get_id(), '_subscription_sign_up_fee', true );
        }
    }

    // The Flutter model checks both (1) explicit flag AND (2) product type slug
    // so make sure subscription type survives (Woo may strip custom types).
    if ( $is_subscription && ! in_array( $data['type'], [ 'subscription', 'variable-subscription' ], true ) ) {
        // Don't override existing type; only mark via the is_subscription flag
        // which takes precedence in the Dart getter isSubscriptionProduct.
    }

    // ── WooCommerce Bookings meta injection ──
    // WooCommerce Bookings / Dokan Bookings don't reliably expose all booking
    // meta fields in /wc/v3/products REST responses.  Same pattern as subs:
    // read directly from post meta and inject both at top-level AND into
    // meta_data array so either extraction path works.
    $booking_meta_keys = [
        '_wc_booking_duration',
        '_wc_booking_duration_unit',
        '_wc_booking_duration_type',
        '_wc_booking_cost',
        '_wc_booking_block_cost',
        '_wc_display_cost',
        '_wc_booking_has_resources',
        '_wc_booking_resources_assignment',
        '_wc_booking_location',
        '_wc_booking_location_type',
        '_wc_booking_has_persons',
        '_wc_booking_min_persons_group',
        '_wc_booking_max_persons_group',
        '_wc_booking_min_date',
        '_wc_booking_min_date_unit',
        '_wc_booking_max_date',
        '_wc_booking_max_date_unit',
        '_wc_booking_default_date_availability',
        '_wc_booking_first_block_time',
        '_wc_booking_restricted_days',
        '_wc_booking_has_restricted_days',
        '_wc_booking_requires_confirmation',
        '_wc_booking_user_can_cancel',
        '_wc_booking_qty',
        '_bookable',
    ];
    $pid = $product->get_id();
    $has_booking = false;
    foreach ( $booking_meta_keys as $bk ) {
        $val = get_post_meta( $pid, $bk, true );
        if ( $val !== '' && $val !== null ) {
            $has_booking = true;
            // Strip leading _wc_booking_ for cleaner top-level keys
            // (keep both so either parser path works).
            $short = $bk;
            if ( strpos( $short, '_wc_booking_' ) === 0 ) {
                $short = substr( $short, 12 );
            } elseif ( strpos( $short, '_' ) === 0 ) {
                $short = substr( $short, 1 );
            }
            $data[ $short ] = $val;
            $data[ 'booking_' . $short ] = $val;
            // Also push into meta_data list
            if ( empty( $data['meta_data'] ) ) {
                $data['meta_data'] = [];
            }
            $found_in_meta = false;
            foreach ( $data['meta_data'] as &$md ) {
                $md_key = is_object( $md ) ? ( $md->key ?? '' ) : ( is_array( $md ) ? ( $md['key'] ?? '' ) : '' );
                if ( $md_key === $bk ) {
                    if ( is_object( $md ) ) $md->value = $val;
                    elseif ( is_array( $md ) ) $md['value'] = $val;
                    $found_in_meta = true;
                    break;
                }
            }
            unset( $md );
            if ( ! $found_in_meta ) {
                $data['meta_data'][] = (object) [ 'id' => 0, 'key' => $bk, 'value' => $val ];
            }
        }
    }
    // If ANY booking meta exists, also set the top-level type hint to 'booking'
    // (unless already set to booking or a subscription type — don't clobber those).
    if ( $has_booking && empty( $data['type'] ) ) {
        $data['type'] = 'booking';
    }
    // Mark product-level bookable flag so the Flutter isBookable getter's
    // 4-way fallback (type || metaIsBookable || bookingDuration || firstBlockTime)
    // catches products with legacy meta combinations.
    if ( $has_booking ) {
        $data['bookable'] = true;
    }

    $response->set_data( $data );
    return $response;
}, 20, 3 );

// Same treatment for product variations (variable-subscription children)
add_filter( 'woocommerce_rest_prepare_product_variation_object', function ( WP_REST_Response $response, $variation, $request ) {
    $data = $response->get_data();
    if ( class_exists( 'WC_Subscriptions_Product' ) ) {
        try {
            $period = WC_Subscriptions_Product::get_period( $variation );
            if ( ! empty( $period ) ) {
                $data['is_subscription']              = true;
                $data['subscription_price']           = (string) WC_Subscriptions_Product::get_price( $variation );
                $data['subscription_period']          = $period;
                $data['subscription_period_interval'] = (string) WC_Subscriptions_Product::get_interval( $variation );
                $data['subscription_length']          = (string) WC_Subscriptions_Product::get_length( $variation );
                $data['subscription_trial_length']    = (string) WC_Subscriptions_Product::get_trial_length( $variation );
                $data['subscription_trial_period']    = (string) WC_Subscriptions_Product::get_trial_period( $variation );
                $data['subscription_sign_up_fee']     = (string) WC_Subscriptions_Product::get_sign_up_fee( $variation );
            }
        } catch ( \Exception $e ) {}
    }
    $response->set_data( $data );
    return $response;
}, 20, 3 );

// =========================================================================
// Dokan REST — enforce strict vendor-isolation on every dokan/v1/* endpoint
// Dokan's MenuManager only hides menu items in the dashboard UI.  If a REST
// call arrives with elevated credentials (e.g. WC Basic Auth consumer key)
// Dokan's native REST may accept ?vendor_id= or ?author= query parameters
// that leak cross-vendor data.  These hooks clamp every sensitive endpoint
// to the authenticated user's own store — BEFORE the endpoint runs.
// =========================================================================
add_action( 'rest_api_init', function () {
    if ( ! function_exists( 'dokan_is_user_seller' ) ) return;

    // Helper: resolve the caller's own store/user IDs
    $resolve_identity = function () {
        $user_id   = get_current_user_id();
        $store_id  = 0;
        if ( $user_id > 0 && dokan_is_user_seller( $user_id ) ) {
            $vendor   = dokan()->vendor->get( $user_id );
            $store_id = $vendor ? (int) $vendor->get_id() : 0;
        }
        return [ $user_id, $store_id ];
    };

    // Hook 1 — Dokan orders list: override any user-supplied vendor_id filter
    add_filter( 'dokan_rest_orders_query_args', function ( $args ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $user_id <= 0 ) return $args;

        // Clamp seller_id — Dokan Lite v5 uses seller_id / vendor_id keys
        $force_keys = [ 'seller_id', 'vendor_id', 'dokan_vendor_id' ];
        foreach ( $force_keys as $k ) {
            if ( $store_id > 0 ) $args[ $k ] = $store_id;
        }
        // If the query uses meta_query instead, inject/override our meta clause
        if ( $store_id > 0 ) {
            $args['meta_query'] = $args['meta_query'] ?? [];
            $args['meta_query'][] = [
                'key'     => '_dokan_vendor_id',
                'value'   => $store_id,
                'compare' => '=',
            ];
        }
        return $args;
    }, 999 );

    // Hook 2 — Dokan products query: force author to current user
    add_filter( 'dokan_rest_products_query', function ( $args ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $user_id > 0 ) {
            $args['author'] = $user_id;
        }
        return $args;
    }, 999 );

    // Hook 3 — Dokan reports/summary: override any supplied seller parameter
    add_filter( 'dokan_rest_reports_get_orders_query_args', function ( $args ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $store_id > 0 ) {
            $args['seller_id']  = $store_id;
            $args['meta_query'] = $args['meta_query'] ?? [];
            $args['meta_query'][] = [
                'key'     => '_dokan_vendor_id',
                'value'   => $store_id,
                'compare' => '=',
            ];
        }
        return $args;
    }, 999 );

    // Hook 4 — Dokan product creation: force post_author to the caller
    add_action( 'dokan_rest_insert_product_object', function ( $product, $request, $creating ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $creating && $user_id > 0 ) {
            wp_update_post( [ 'ID' => $product->get_id(), 'post_author' => $user_id ] );
            update_post_meta( $product->get_id(), '_dokan_vendor_id', $store_id );
        }
    }, 999, 3 );

    // Hook 5 — Dokan order item retrieval: strip cross-vendor line items before response
    add_filter( 'dokan_rest_prepare_order_object', function ( $response, $order, $request ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $store_id <= 0 || ! is_a( $response, 'WP_REST_Response' ) ) return $response;

        $data = $response->get_data();
        // Only keep line_items whose products belong to this store
        if ( isset( $data['line_items'] ) && is_array( $data['line_items'] ) ) {
            $filtered = [];
            foreach ( $data['line_items'] as $item ) {
                $pid = $item['product_id'] ?? 0;
                if ( ! $pid ) continue;
                $author_id = (int) get_post_field( 'post_author', $pid );
                $vendor_id = (int) get_post_meta( $pid, '_dokan_vendor_id', true );
                if ( $author_id === $user_id || $vendor_id === $store_id ) {
                    $filtered[] = $item;
                }
            }
            $data['line_items'] = $filtered;
            $response->set_data( $data );
        }
        return $response;
    }, 999, 3 );

    // Hook 6 — Reviews: clamp comments query to vendor's own products.
    // Dokan Pro ReviewsController calls comment_query($store_id, ...) but if
    // JWT auth fails silently the store_id may be wrong.  This comments_clauses
    // filter joins on the posts table and restricts to the vendor's author ID.
    add_filter( 'comments_clauses', function ( $clauses ) use ( $resolve_identity ) {
        // Only intervene on Dokan REST review requests
        $uri = $_SERVER['REQUEST_URI'] ?? '';
        if ( strpos( $uri, '/dokan/v1/reviews' ) === false ) return $clauses;

        list( $user_id, $store_id ) = $resolve_identity();
        if ( $user_id <= 0 ) return $clauses;

        global $wpdb;
        $clauses['join']   = ( $clauses['join'] ?? '' ) . " INNER JOIN {$wpdb->posts} ON {$wpdb->posts}.ID = {$wpdb->comments}.comment_post_ID";
        $clauses['where']  = ( $clauses['where'] ?? '' ) . $wpdb->prepare( " AND {$wpdb->posts}.post_author = %d", $user_id );
        return $clauses;
    }, 999 );

    // Hook 7 — Coupons: force post_author on shop_coupon queries during
    // Dokan REST requests so vendors only see their own coupons.
    add_action( 'pre_get_posts', function ( $query ) use ( $resolve_identity ) {
        $uri = $_SERVER['REQUEST_URI'] ?? '';
        if ( strpos( $uri, '/dokan/v1/coupons' ) === false ) return;
        if ( ! $query->is_main_query() ) return;
        if ( $query->get( 'post_type' ) !== 'shop_coupon' ) return;

        list( $user_id, $store_id ) = $resolve_identity();
        if ( $user_id > 0 ) {
            $query->set( 'author', $user_id );
        }
    }, 999 );

    // Hook 8 — Withdrawals: Dokan's WithdrawController uses get_current_user_id()
    // but add a prepare-response filter that strips withdrawal records not owned
    // by the authenticated user (defence in depth).
    add_filter( 'dokan_rest_prepare_withdraw_object', function ( $response, $withdraw, $request ) use ( $resolve_identity ) {
        list( $user_id, $store_id ) = $resolve_identity();
        if ( $user_id <= 0 ) return $response;

        // The withdraw object's user_id must match the authenticated user
        $withdraw_user_id = isset( $withdraw->user_id ) ? (int) $withdraw->user_id : 0;
        if ( $withdraw_user_id > 0 && $withdraw_user_id !== $user_id ) {
            return new WP_Error(
                'dokan_rest_cannot_view_other_vendor_withdraw',
                __( 'You cannot view other vendors\' withdrawal records.', 'dokan-lite' ),
                [ 'status' => 403 ]
            );
        }
        return $response;
    }, 999, 3 );

}, 100 );

// =========================================================================
// Register REST endpoints
// =========================================================================
add_action( 'rest_api_init', function () {

    // Diagnostic route — no auth, no Dokan dependency. Hit this to confirm
    // the plugin file is being loaded: GET /wp-json/vendor-bridge/v1/ping
    register_rest_route( 'vendor-bridge/v1', '/ping', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true',
        'callback'            => function () {
            return [
                'status'     => 'ok',
                'dokan'      => function_exists( 'dokan' ),
                'is_seller'  => function_exists( 'dokan_is_user_seller' ),
                'jwt'        => function_exists( 'jwt_auth_get_user_from_token' ),
                'jwt_secret' => defined( 'JWT_AUTH_SECRET_KEY' ),
                'time'       => current_time( 'mysql' ),
            ];
        },
    ] );

    // Debug route — tests JWT auth resolution. Sends same headers as /store/me
    // to determine if the determine_current_user filter is working.
    register_rest_route( 'vendor-bridge/v1', '/auth-debug', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true',
        'callback'            => function () {
            $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
            if ( empty( $auth_header ) && function_exists( 'getallheaders' ) ) {
                $headers = getallheaders();
                $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
            }

            $has_bearer = preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $matches );

            return [
                'auth_header_found'  => ! empty( $auth_header ),
                'bearer_matched'     => (bool) $has_bearer,
                'token_preview'      => $has_bearer ? ( substr( $matches[1], 0, 20 ) . '…' ) : null,
                'current_user_id'    => get_current_user_id(),
                'is_logged_in'       => is_user_logged_in(),
                'jwt_class_exists'   => class_exists( 'JWT' ) || class_exists( '\Firebase\JWT\JWT' ),
                'jwt_secret_defined' => defined( 'JWT_AUTH_SECRET_KEY' ),
                'all_headers'        => array_keys( $_SERVER ),
            ];
        },
    ] );

    // Skip registering store routes if Dokan isn't available
    if ( ! function_exists( 'dokan' ) || ! function_exists( 'dokan_is_user_seller' ) ) {
        return;
    }

    register_rest_route( 'vendor-bridge/v1', '/store/me', [
        'methods'             => 'GET',
        'permission_callback' => function () {
            // Must be logged in via JWT
            return is_user_logged_in() && dokan_is_user_seller( get_current_user_id() );
        },
        'callback' => 'dvb_get_store',
    ] );

    register_rest_route( 'vendor-bridge/v1', '/store/me', [
        'methods'             => 'PUT',
        'permission_callback' => function () {
            return is_user_logged_in() && dokan_is_user_seller( get_current_user_id() );
        },
        'callback' => 'dvb_update_store',
    ] );
} );

// =========================================================================
// GET — Returns ALL store settings using Dokan's native methods
// =========================================================================
function dvb_get_store( WP_REST_Request $request ) {
    $user_id = get_current_user_id();

    if ( ! dokan_is_user_seller( $user_id ) ) {
        return new WP_Error( 'not_vendor', 'You are not a vendor.', [ 'status' => 403 ] );
    }

    $vendor = dokan()->vendor->get( $user_id );

    if ( ! $vendor || ! $vendor->get_id() ) {
        return new WP_Error( 'no_store', 'No store found for this user.', [ 'status' => 404 ] );
    }

    // Read from the same source Dokan's own dashboard UI uses:
    // dokan_profile_settings is user meta key that stores all vendor settings.
    $profile_settings = get_user_meta( $user_id, 'dokan_profile_settings', true );
    if ( ! is_array( $profile_settings ) ) {
        $profile_settings = [];
    }

    // Build a comprehensive response using both the vendor object and profile meta
    $store_id = $vendor->get_id();

    return [
        'id'                => $store_id,
        'user_id'           => $user_id,
        'store_name'        => $vendor->get_shop_name(),
        'slug'              => $vendor->get_slug(),
        'email'             => get_userdata( $user_id )->user_email ?? '',
        'phone'             => $vendor->get_phone(),
        'banner'            => $vendor->get_banner(),
        'gravatar'          => $vendor->get_avatar(),

        // Address — Dokan_Vendor has get_address() which returns array
        'address'           => dvb_get_address( $vendor, $profile_settings ),

        // Store open/close
        'store_open_close'  => [
            'is_open'       => $vendor->is_store_open(),
            'open_notice'   => $profile_settings['store_open_close']['open_notice'] ?? '',
            'close_notice'  => $profile_settings['store_open_close']['close_notice'] ?? '',
        ],

        // Payment / bank details
        'payment'           => [
            'bank' => [
                'bank_name' => $profile_settings['payment']['bank']['bank_name'] ?? '',
                'iban'      => $profile_settings['payment']['bank']['iban'] ?? '',
                'ac_name'   => $profile_settings['payment']['bank']['ac_name'] ?? '',
                'ac_number' => $profile_settings['payment']['bank']['ac_number'] ?? '',
            ],
            'paypal' => [
                'email'     => $profile_settings['payment']['paypal']['email'] ?? '',
            ],
        ],

        // Social
        'social'            => [
            'fb'        => $profile_settings['social']['fb'] ?? '',
            'twitter'   => $profile_settings['social']['twitter'] ?? '',
            'instagram' => $profile_settings['social']['instagram'] ?? '',
            'youtube'   => $profile_settings['social']['youtube'] ?? '',
            'linkedin'  => $profile_settings['social']['linkedin'] ?? '',
        ],

        // Store SEO
        'store_seo'         => $profile_settings['store_seo'] ?? [],

        // Bio / description
        'description'       => $vendor->get_shop_description(),
    ];
}

/**
 * Builds a consistent address array from both vendor object and profile meta.
 */
function dvb_get_address( $vendor, array $profile_settings ): array {
    $addr = [];
    if ( method_exists( $vendor, 'get_address' ) ) {
        $addr = (array) $vendor->get_address();
    }
    // Fall back to profile settings
    if ( empty( array_filter( $addr ) ) ) {
        $addr = [
            'street_1' => $profile_settings['address']['street_1'] ?? '',
            'street_2' => $profile_settings['address']['street_2'] ?? '',
            'city'     => $profile_settings['address']['city'] ?? '',
            'state'    => $profile_settings['address']['state'] ?? '',
            'zip'      => $profile_settings['address']['zip'] ?? '',
            'country'  => $profile_settings['address']['country'] ?? '',
        ];
    }
    return $addr;
}

// =========================================================================
// PUT — Update store settings
// =========================================================================
function dvb_update_store( WP_REST_Request $request ) {
    $user_id = get_current_user_id();

    if ( ! dokan_is_user_seller( $user_id ) ) {
        return new WP_Error( 'not_vendor', 'You are not a vendor.', [ 'status' => 403 ] );
    }

    $params = $request->get_json_params();

    // Use Dokan's own update function which writes to dokan_profile_settings user meta
    $data_to_update = [];

    if ( isset( $params['store_name'] ) ) {
        $data_to_update['store_name'] = sanitize_text_field( $params['store_name'] );
    }
    if ( isset( $params['phone'] ) ) {
        $data_to_update['phone'] = sanitize_text_field( $params['phone'] );
    }

    // Address
    if ( isset( $params['address'] ) && is_array( $params['address'] ) ) {
        $data_to_update['address'] = [
            'street_1' => sanitize_text_field( $params['address']['street_1'] ?? '' ),
            'street_2' => sanitize_text_field( $params['address']['street_2'] ?? '' ),
            'city'     => sanitize_text_field( $params['address']['city'] ?? '' ),
            'state'    => sanitize_text_field( $params['address']['state'] ?? '' ),
            'zip'      => sanitize_text_field( $params['address']['zip'] ?? '' ),
            'country'  => sanitize_text_field( $params['address']['country'] ?? '' ),
        ];
    }

    // Payment / bank
    if ( isset( $params['payment'] ) && is_array( $params['payment'] ) ) {
        $data_to_update['payment'] = [
            'bank' => [
                'bank_name' => sanitize_text_field( $params['payment']['bank']['bank_name'] ?? '' ),
                'iban'      => sanitize_text_field( $params['payment']['bank']['iban'] ?? '' ),
                'ac_name'   => sanitize_text_field( $params['payment']['bank']['ac_name'] ?? '' ),
                'ac_number' => sanitize_text_field( $params['payment']['bank']['ac_number'] ?? '' ),
            ],
            'paypal' => [
                'email' => sanitize_email( $params['payment']['paypal']['email'] ?? '' ),
            ],
        ];
    }

    // Social
    if ( isset( $params['social'] ) && is_array( $params['social'] ) ) {
        $data_to_update['social'] = [
            'fb'        => sanitize_text_field( $params['social']['fb'] ?? '' ),
            'twitter'   => sanitize_text_field( $params['social']['twitter'] ?? '' ),
            'instagram' => sanitize_text_field( $params['social']['instagram'] ?? '' ),
            'youtube'   => sanitize_text_field( $params['social']['youtube'] ?? '' ),
            'linkedin'  => sanitize_text_field( $params['social']['linkedin'] ?? '' ),
        ];
    }

    // Store open/close
    if ( isset( $params['store_open_close'] ) && is_array( $params['store_open_close'] ) ) {
        $data_to_update['store_open_close'] = [
            'open_notice'  => sanitize_text_field( $params['store_open_close']['open_notice'] ?? '' ),
            'close_notice' => sanitize_text_field( $params['store_open_close']['close_notice'] ?? '' ),
        ];
        // Persist the is_open toggle separately — Dokan uses it to control store visibility
        if ( isset( $params['store_open_close']['is_open'] ) ) {
            update_user_meta( $user_id, 'dokan_enable_selling', $params['store_open_close']['is_open'] ? 'yes' : 'no' );
        }
    }

    if ( ! empty( $data_to_update ) ) {
        if ( function_exists( 'dokan_update_store_settings' ) ) {
            dokan_update_store_settings( $user_id, $data_to_update );
        } else {
            // Fallback: write directly to user meta
            update_user_meta( $user_id, 'dokan_profile_settings', array_merge(
                get_user_meta( $user_id, 'dokan_profile_settings', true ) ?: [],
                $data_to_update,
            ) );
        }
    }

    // Return the updated store
    return dvb_get_store( $request );
}
