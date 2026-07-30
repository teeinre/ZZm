<?php
/**
 * ZZmore App — Checkout Bridge
 * =============================
 * Must-use plugin for WordPress.
 * Place this file in: wp-content/mu-plugins/zzmore-app-checkout.php
 *
 * Flow:
 *  1. App (JWT-authenticated) → POST /wp-json/app/v1/prepare-checkout
 *     → Server stores cart + user_id in a transient, returns opaque single-use code.
 *  2. WebView → GET /wp-json/app/v1/enter-checkout?code=XXX
 *     → Server logs user in, builds WC cart, redirects to /checkout/.
 *     → WebView's native cookie store receives Set-Cookie from this response.
 *  3. App watches WebView navigation for /checkout/order-received/{id}?key=xxx
 *     → Extracts order ID + key, fetches order via WC REST API for verification.
 *
 * Requires: WooCommerce, JWT Authentication for WP REST API.
 */

defined('ABSPATH') || exit;

// ─── Register REST endpoints ────────────────────────────────────────────────

add_action('rest_api_init', 'zzmore_register_checkout_endpoints');

function zzmore_register_checkout_endpoints(): void
{
    // Step 1: App prepares checkout via POST (JWT-authenticated)
    register_rest_route('app/v1', '/prepare-checkout', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_prepare_checkout',
        'permission_callback' => 'zzmore_is_logged_in',
    ]);

    // Step 2: WebView enters checkout via GET (public, uses single-use code)
    register_rest_route('app/v1', '/enter-checkout', [
        'methods'             => 'GET',
        'callback'            => 'zzmore_enter_checkout',
        'permission_callback' => '__return_true',
    ]);

    // Step 3: App fetches verified order data (JWT-authenticated)
    register_rest_route('app/v1', '/order/(?P<id>\d+)', [
        'methods'             => 'GET',
        'callback'            => 'zzmore_get_order',
        'permission_callback' => 'zzmore_is_logged_in',
        'args'                => [
            'id'  => ['required' => true, 'type' => 'integer'],
            'key' => ['required' => true, 'type' => 'string'],
        ],
    ]);
}

function zzmore_is_logged_in(): bool
{
    return is_user_logged_in();
}

// ─── POST /app/v1/prepare-checkout ──────────────────────────────────────────

function zzmore_prepare_checkout(WP_REST_Request $request)
{
    $user_id = get_current_user_id();
    $items   = $request->get_param('items');

    if (empty($items) || !is_array($items)) {
        return new WP_Error('bad_request', 'No cart items provided', ['status' => 400]);
    }

    // Validate each item has at least product_id
    foreach ($items as $item) {
        if (empty($item['product_id'])) {
            return new WP_Error('bad_request', 'Each item must have a product_id', ['status' => 400]);
        }
    }

    // Generate opaque single-use code (40 random chars, 90-second expiry)
    $code = wp_generate_password(40, false);
    set_transient('zzmore_checkout_' . $code, [
        'user_id' => $user_id,
        'items'   => $items,
        'email'   => $request->get_param('email') ?: '',
    ], 90);

    return [
        'code'       => $code,
        'checkout_url' => home_url('/checkout/'),
    ];
}

// ─── GET /app/v1/enter-checkout?code=XXX ────────────────────────────────────

function zzmore_enter_checkout(WP_REST_Request $request)
{
    $code = sanitize_text_field($request->get_param('code'));
    if (!$code) {
        wp_die('Missing checkout code.', 'Bad Request', ['response' => 400]);
    }

    $data = get_transient('zzmore_checkout_' . $code);
    if (!$data || !is_array($data)) {
        wp_die(
            'This checkout link has expired or was already used. Please go back to the app and try again.',
            'Link Expired',
            ['response' => 410]
        );
    }

    // Consume immediately — single use
    delete_transient('zzmore_checkout_' . $code);

    // Log in as the user
    wp_clear_auth_cookie();
    wp_set_current_user((int) $data['user_id']);
    wp_set_auth_cookie((int) $data['user_id'], true);

    // Build cart
    if (function_exists('WC') && isset(WC()->cart)) {
        WC()->cart->empty_cart();
        foreach ($data['items'] as $item) {
            $product_id   = (int) ($item['product_id'] ?? 0);
            $qty          = (int) ($item['quantity'] ?? 1);
            $variation_id = (int) ($item['variation_id'] ?? 0);
            $variation    = !empty($item['variation']) ? (array) $item['variation'] : [];

            if ($product_id > 0) {
                WC()->cart->add_to_cart($product_id, $qty, $variation_id, $variation);
            }
        }
    }

    // Redirect to native WooCommerce checkout page
    wp_safe_redirect(home_url('/checkout/'));
    exit;
}

// ─── GET /app/v1/order/{id}?key=xxx ──────────────────────────────────────

function zzmore_get_order(WP_REST_Request $request)
{
    $order_id  = (int) $request->get_param('id');
    $order_key = sanitize_text_field($request->get_param('key'));
    $user_id   = get_current_user_id();

    // Fetch order via WooCommerce
    $order = function_exists('wc_get_order') ? wc_get_order($order_id) : null;
    if (!$order) {
        return new WP_Error('not_found', 'Order not found', ['status' => 404]);
    }

    // Verify order key matches (prevents ID guessing)
    if ($order->get_order_key() !== $order_key) {
        return new WP_Error('forbidden', 'Invalid order key', ['status' => 403]);
    }

    // Verify this order belongs to the authenticated user
    if ((int) $order->get_customer_id() !== $user_id) {
        return new WP_Error('forbidden', 'Order does not belong to you', ['status' => 403]);
    }

    // Return sanitized order data
    return [
        'id'              => $order->get_id(),
        'status'          => $order->get_status(),
        'total'           => $order->get_total(),
        'currency'        => $order->get_currency(),
        'date_created'    => $order->get_date_created() ? $order->get_date_created()->__toString() : '',
        'payment_method'  => $order->get_payment_method_title(),
        'billing'         => $order->get_address('billing'),
        'shipping'        => $order->get_address('shipping'),
        'line_items'      => array_map(function ($item) {
            return [
                'name'     => $item->get_name(),
                'quantity' => $item->get_quantity(),
                'total'    => $item->get_total(),
            ];
        }, $order->get_items()),
        'order_key'       => $order->get_order_key(),
    ];
}
