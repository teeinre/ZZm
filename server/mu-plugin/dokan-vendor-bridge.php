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

    // Try JWT token from Authorization header
    $auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ( empty( $auth_header ) && function_exists( 'getallheaders' ) ) {
        $headers = getallheaders();
        $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }

    if ( $auth_header && preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $matches ) ) {
        $jwt_token = $matches[1];

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
        if ( defined( 'JWT_AUTH_SECRET_KEY' ) && class_exists( 'JWT' ) ) {
            try {
                $decoded = \JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
                if ( isset( $decoded->data->user->id ) ) {
                    $user_id = (int) $decoded->data->user->id;
                    wp_set_current_user( $user_id );
                    return $user_id;
                }
            } catch ( \Exception $e ) {}
        }
    }

    return $user_id;
}, 20 );

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
