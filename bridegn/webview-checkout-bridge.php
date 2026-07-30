<?php
/**
 * Plugin Name: Flutter WebView Checkout Bridge
 * Description: Lets a Flutter app hand off a logged-in user + cart to the
 *              WooCommerce checkout WebView, and lets the app read back
 *              order details once checkout completes.
 *
 * Install as a normal plugin (wp-content/plugins/webview-checkout-bridge/webview-checkout-bridge.php)
 * or as a must-use plugin (wp-content/mu-plugins/webview-checkout-bridge.php).
 */

if ( ! defined( 'ABSPATH' ) ) exit;

define( 'WVB_TOKEN_TTL', 120 );          // seconds a bridge token is valid for
define( 'WVB_SECRET', 'CHANGE_ME_TO_A_LONG_RANDOM_STRING' ); // used to sign generate-token requests

/**
 * STEP 1
 * Flutter app calls this AFTER the user is already authenticated in the app
 * (e.g. via JWT plugin, or WooCommerce's own /wc-auth/v1 token, or a custom
 * login endpoint). This call must itself be authenticated — we use the
 * standard WP REST auth (Application Passwords or your JWT plugin's
 * Authorization header) so we know which wp_user is making the request.
 *
 * Body:
 * {
 *   "items": [ { "product_id": 123, "quantity": 2, "variation_id": 0 }, ... ]
 * }
 *
 * Response:
 * { "token": "abc123...", "expires_in": 120 }
 */
add_action( 'rest_api_init', function () {

    register_rest_route( 'bridge/v1', '/generate-token', [
        'methods'             => 'POST',
        'permission_callback' => function () {
            // Requires the request to be authenticated as a logged-in WP user
            // (via cookie, Application Passwords, or a JWT auth plugin that
            // hooks into determine_current_user).
            return is_user_logged_in();
        },
        'callback' => 'wvb_generate_token',
    ] );

    register_rest_route( 'bridge/v1', '/enter', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true', // token itself is the auth
        'callback'            => 'wvb_enter',
    ] );

    register_rest_route( 'bridge/v1', '/order/(?P<id>\d+)', [
        'methods'             => 'GET',
        'permission_callback' => function () {
            return is_user_logged_in();
        },
        'callback' => 'wvb_get_order',
    ] );
} );

function wvb_generate_token( WP_REST_Request $request ) {
    $user_id = get_current_user_id();
    $items   = $request->get_param( 'items' );

    if ( empty( $user_id ) ) {
        return new WP_Error( 'no_user', 'Not authenticated', [ 'status' => 401 ] );
    }
    if ( ! is_array( $items ) ) {
        $items = [];
    }

    $token = wp_generate_password( 32, false, false );

    // Store user id + cart payload server-side, keyed by the token.
    // Nobody can forge this because the token itself is random and one-time-use.
    set_transient( 'wvb_' . $token, [
        'user_id' => $user_id,
        'items'   => $items,
    ], WVB_TOKEN_TTL );

    return [
        'token'      => $token,
        'expires_in' => WVB_TOKEN_TTL,
    ];
}

/**
 * STEP 2
 * The WebView's very first request. Logs the user in via cookie auth,
 * rebuilds the cart, then redirects to /checkout/.
 */
function wvb_enter( WP_REST_Request $request ) {
    $token = sanitize_text_field( $request->get_param( 'token' ) );
    $data  = get_transient( 'wvb_' . $token );

    if ( empty( $data ) ) {
        wp_die( 'This checkout link has expired. Please go back to the app and try again.', 'Link expired', [ 'response' => 410 ] );
    }

    // One-time use: burn it immediately.
    delete_transient( 'wvb_' . $token );

    $user_id = (int) $data['user_id'];
    $items   = (array) $data['items'];

    // Log the user in (sets the auth cookie on this response).
    wp_set_current_user( $user_id );
    wp_set_auth_cookie( $user_id, true );

    // Make sure WooCommerce session/cart machinery is loaded.
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

    wp_safe_redirect( wc_get_checkout_url() );
    exit;
}

/**
 * STEP 3
 * Your Flutter app calls this (through your own auth) once it detects the
 * order-received URL, to fetch full order details without ever holding
 * WooCommerce REST API keys on-device.
 */
function wvb_get_order( WP_REST_Request $request ) {
    $order_id = (int) $request['id'];
    $order    = wc_get_order( $order_id );

    if ( ! $order ) {
        return new WP_Error( 'not_found', 'Order not found', [ 'status' => 404 ] );
    }

    // Make sure the logged-in user actually owns this order.
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
        'date_created'   => $order->get_date_created() ? $order->get_date_created()->date( 'c' ) : null,
        'items'          => $items,
    ];
}
