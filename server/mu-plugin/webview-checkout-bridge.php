<?php
/**
 * Plugin Name: Flutter WebView Checkout Bridge for zzmore.store
 * Description: Bridges Flutter app authentication (JWT) to WooCommerce PHP session
 *              checkout. Handles: token generation, auto-login into WebView,
 *              cart rebuild, and order detail retrieval.
 *
 * Install: Copy to wp-content/mu-plugins/webview-checkout-bridge.php
 *
 * Prerequisites:
 *   - JWT Authentication for WP-API plugin must be active
 *   - add_filter('jwt_auth_token_before_dispatch', ...) is configured
 *     to set the current user so is_user_logged_in() returns true
 */

if ( ! defined( 'ABSPATH' ) ) exit;

define( 'WVB_TOKEN_TTL', 120 );          // seconds a bridge token is valid
define( 'WVB_SECRET', 'zzmore_bridge_9x7Kp2WqR4mN8vY1LtA6sC3' ); // random secret

// =========================================================================
// JWT Compatibility: Make JWT-authenticated requests count as "logged in"
// so the bridge endpoints can use is_user_logged_in() as permission checks.
// =========================================================================
add_action( 'rest_api_init', function () {
    // If the JWT plugin's determine_current_user filter has already run,
    // wp_get_current_user() will return the correct user. But many JWT plugins
    // only set it on the jwt-auth endpoints. This bridge hooks into the same
    // filter to make sure the bridge REST routes also see the JWT user.
}, 1 );

// Hook into JWT auth to set current user for our bridge routes
add_filter( 'determine_current_user', function ( $user_id ) {
    // If already determined by a cookie or by JWT plugin, keep it.
    if ( $user_id > 0 ) {
        return $user_id;
    }

    // Try JWT token from Authorization header (if JWT plugin didn't already)
    $auth_header = null;
    if ( isset( $_SERVER['HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['HTTP_AUTHORIZATION'];
    } elseif ( isset( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ) ) {
        $auth_header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    } elseif ( function_exists( 'getallheaders' ) ) {
        $headers = getallheaders();
        $auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? null;
    }

    if ( $auth_header && preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $matches ) ) {
        $jwt_token = $matches[1];

        // Try to validate with the JWT Auth plugin's validation
        if ( defined( 'JWT_AUTH_SECRET_KEY' ) && class_exists( 'JWT' ) ) {
            try {
                $decoded = \JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
                if ( isset( $decoded->data->user->id ) ) {
                    $user_id = (int) $decoded->data->user->id;
                    wp_set_current_user( $user_id );
                    return $user_id;
                }
            } catch ( \Exception $e ) {
                // JWT validation failed — not logged in
            }
        }

        // Fallback: try the jwt-auth plugin's own validation function
        if ( function_exists( 'jwt_auth_get_user_from_token' ) ) {
            try {
                $user = jwt_auth_get_user_from_token( $jwt_token );
                if ( $user && ! is_wp_error( $user ) ) {
                    wp_set_current_user( $user->ID );
                    return $user->ID;
                }
            } catch ( \Exception $e ) {}
        }
    }

    return $user_id;
}, 20 );

// =========================================================================
// REST API Endpoints
// =========================================================================
add_action( 'rest_api_init', function () {

    // POST /wp-json/bridge/v1/generate-token
    // Flutter sends cart items + JWT auth header. Returns a single-use token.
    register_rest_route( 'bridge/v1', '/generate-token', [
        'methods'             => 'POST',
        'permission_callback' => function () {
            // Must have a valid JWT token that resolves to a WP user.
            return is_user_logged_in();
        },
        'callback' => 'wvb_generate_token',
    ] );

    // GET /wp-json/bridge/v1/enter?token=XYZ
    // WebView loads this. Verifies token, logs user in via cookie,
    // rebuilds WooCommerce cart, redirects to /checkout/.
    register_rest_route( 'bridge/v1', '/enter', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true', // token itself is the auth
        'callback'            => 'wvb_enter',
    ] );

    // GET /wp-json/bridge/v1/order/{id}
    // Flutter fetches order details after checkout completes.
    register_rest_route( 'bridge/v1', '/order/(?P<id>\d+)', [
        'methods'             => 'GET',
        'permission_callback' => function () {
            return is_user_logged_in();
        },
        'callback' => 'wvb_get_order',
    ] );
} );

/**
 * Generate a single-use bridge token.
 *
 * POST body: { "items": [ { "product_id": 123, "quantity": 2, "variation_id": 0 }, ... ] }
 * Response:  { "token": "abc...", "expires_in": 120 }
 */
function wvb_generate_token( WP_REST_Request $request ) {
    $user_id = get_current_user_id();
    $items   = $request->get_param( 'items' );

    if ( empty( $user_id ) ) {
        return new WP_Error( 'no_user', 'Not authenticated. Use a valid JWT token.', [ 'status' => 401 ] );
    }
    if ( ! is_array( $items ) ) {
        $items = [];
    }

    $token = wp_generate_password( 32, false, false );

    // Store user id + cart payload server-side, keyed by the random token.
    // Single-use: deleted when /enter is called. TTL prevents stale tokens.
    set_transient( 'wvb_' . $token, [
        'user_id'  => $user_id,
        'items'    => $items,
    ], WVB_TOKEN_TTL );

    return [
        'token'      => $token,
        'expires_in' => WVB_TOKEN_TTL,
    ];
}

/**
 * WebView entry point. Sets auth cookie, rebuilds cart, redirects to checkout.
 */
function wvb_enter( WP_REST_Request $request ) {
    $token = sanitize_text_field( $request->get_param( 'token' ) );
    $data  = get_transient( 'wvb_' . $token );

    if ( empty( $data ) ) {
        wp_die(
            'This checkout link has expired. Please go back to the app and try again.',
            'Link Expired',
            [ 'response' => 410 ]
        );
    }

    // One-time use: burn it immediately.
    delete_transient( 'wvb_' . $token );

    $user_id = (int) $data['user_id'];
    $items   = (array) $data['items'];

    // Log the user in via cookie auth (so WooCommerce checkout sees them)
    wp_set_current_user( $user_id );
    wp_set_auth_cookie( $user_id, true );

    // Rebuild the WooCommerce cart
    if ( function_exists( 'WC' ) ) {
        if ( null === WC()->cart ) {
            wc_load_cart();
        }
        WC()->cart->empty_cart();

        foreach ( $items as $item ) {
            $product_id   = isset( $item['product_id'] ) ? (int) $item['product_id'] : 0;
            $quantity     = isset( $item['quantity'] ) ? (int) $item['quantity'] : 1;
            $variation_id = isset( $item['variation_id'] ) ? (int) $item['variation_id'] : 0;

            if ( $product_id > 0 ) {
                WC()->cart->add_to_cart( $product_id, $quantity, $variation_id );
            }
        }
    }

    // Set app_checkout cookie so the styling plugin knows this is an app WebView
    setcookie( 'app_checkout', '1', time() + 3600, '/', '', is_ssl(), true );

    wp_safe_redirect( wc_get_checkout_url() );
    exit;
}

/**
 * Fetch order details for Flutter app after checkout.
 */
function wvb_get_order( WP_REST_Request $request ) {
    $order_id = (int) $request['id'];
    $order    = wc_get_order( $order_id );

    if ( ! $order ) {
        return new WP_Error( 'not_found', 'Order not found', [ 'status' => 404 ] );
    }

    // Verify order belongs to the authenticated user
    if ( (int) $order->get_customer_id() !== get_current_user_id() ) {
        return new WP_Error( 'forbidden', 'Not your order', [ 'status' => 403 ] );
    }

    $items = [];
    foreach ( $order->get_items() as $item ) {
        $items[] = [
            'name'     => $item->get_name(),
            'quantity' => $item->get_quantity(),
            'total'    => $item->get_total(),
        ];
    }

    return [
        'id'             => $order->get_id(),
        'status'         => $order->get_status(),
        'total'          => $order->get_total(),
        'currency'       => $order->get_currency(),
        'payment_method' => $order->get_payment_method_title(),
        'date_created'   => $order->get_date_created()
            ? $order->get_date_created()->date( 'c' )
            : null,
        'items'          => $items,
    ];
}
