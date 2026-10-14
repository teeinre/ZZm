<?php
/**
 * ZZmore App — Push Notifications via Firebase Cloud Messaging
 * ============================================================
 * Must-use plugin for WordPress.
 * Place this file in: wp-content/mu-plugins/zzmore-push-notifications.php
 *
 * Listens to WooCommerce and Dokan hooks and sends push notifications
 * to registered mobile devices via Firebase Cloud Messaging (FCM v1).
 *
 * Required: WooCommerce, Dokan (optional), and a valid FCM Server Key
 *           set in the constant FCM_SERVER_KEY or via a filter.
 *
 * Register user device tokens via REST endpoint:
 *   POST /wp-json/app/v1/register-device
 *
 * Events that trigger push notifications:
 *   - WooCommerce order status changes (processing, completed, shipped, cancelled, etc.)
 *   - New order placed
 *   - Dokan vendor starts a livestream (requires Dokan livestream module)
 *   - Dokan vendor order status changes
 *
 * Deploy: Copy this file to wp-content/mu-plugins/ on zzmore.store,
 *         then define FCM_SERVER_KEY in wp-config.php or set it below.
 */

defined('ABSPATH') || exit;

// ─── Configuration ───────────────────────────────────────────────────────────
//
// CRITICAL: this plugin used to send via the FCM *legacy* HTTP API
// (fcm.googleapis.com/fcm/send with an `Authorization: key=<server key>`
// header). Google fully retired that API in mid-2024 — it now rejects every
// request, so every push this plugin tried to send (order updates,
// livestream-start alerts, promotions) was silently failing regardless of
// whether device tokens were registered. Sending has been rewritten below to
// use the current FCM HTTP v1 API, which is a completely different auth
// model: a short-lived OAuth2 access token minted from a Firebase *service
// account*, not a static server key.
//
// To configure, get a service account key from Firebase Console → Project
// Settings → Service Accounts → "Generate new private key" (downloads a
// JSON file), then set ONE of:
//   define('ZZMORE_FCM_SERVICE_ACCOUNT_JSON', file_get_contents('/path/outside/webroot/service-account.json'));
//   define('ZZMORE_FCM_SERVICE_ACCOUNT_PATH', '/path/outside/webroot/service-account.json');
//   update_option('zzmore_fcm_service_account_json', file_get_contents('...'));
// in wp-config.php (preferred — keeps the key out of the database) or via a
// one-off wp-cli snippet. The project id, signing key, and OAuth client
// email are all read from that JSON; there is no separate "server key"
// setting any more.

// ─── Register device token endpoint ──────────────────────────────────────────

add_action('rest_api_init', 'zzmore_register_push_endpoints');

function zzmore_register_push_endpoints(): void
{
    // Register/unregister device token (JWT-authenticated)
    register_rest_route('app/v1', '/register-device', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_register_device',
        'permission_callback' => 'is_user_logged_in',
    ]);

    // Unregister device token (on logout)
    register_rest_route('app/v1', '/unregister-device', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_unregister_device',
        'permission_callback' => 'is_user_logged_in',
    ]);
}

function zzmore_register_device(WP_REST_Request $request)
{
    $user_id = get_current_user_id();
    $token   = sanitize_text_field($request->get_param('token'));
    $platform = sanitize_text_field($request->get_param('platform')) ?: 'android';

    if (empty($token)) {
        return new WP_Error('missing_token', 'FCM token is required', ['status' => 400]);
    }

    // Store token (unique per user/device)
    $existing = get_user_meta($user_id, '_fcm_tokens', true) ?: [];
    if (!is_array($existing)) {
        $existing = [];
    }

    // Remove duplicate tokens, keep last 5 per user
    $existing = array_filter($existing, fn($t) => isset($t['token']) && $t['token'] !== $token);
    $existing[] = [
        'token'      => $token,
        'platform'   => $platform,
        'updated_at' => current_time('mysql'),
    ];
    $existing = array_slice($existing, -5);

    update_user_meta($user_id, '_fcm_tokens', $existing);

    return ['success' => true, 'message' => 'Device registered for push notifications'];
}

function zzmore_unregister_device(WP_REST_Request $request)
{
    $user_id = get_current_user_id();
    $token   = sanitize_text_field($request->get_param('token'));

    if (empty($token)) {
        return new WP_Error('missing_token', 'FCM token is required', ['status' => 400]);
    }

    $existing = get_user_meta($user_id, '_fcm_tokens', true) ?: [];
    if (!is_array($existing)) {
        $existing = [];
    }

    $existing = array_filter($existing, fn($t) => isset($t['token']) && $t['token'] !== $token);
    update_user_meta($user_id, '_fcm_tokens', array_values($existing));

    return ['success' => true, 'message' => 'Device unregistered from push notifications'];
}

// ─── WooCommerce Order Status Notifications ──────────────────────────────────

add_action('woocommerce_order_status_changed', 'zzmore_notify_order_status_change', 10, 4);

function zzmore_notify_order_status_change($order_id, $old_status, $new_status, $order): void
{
    $customer_id = $order->get_customer_id();
    if (!$customer_id) return;

    $status_labels = wc_get_order_statuses();
    $new_label = $status_labels['wc-' . $new_status] ?? ucfirst($new_status);

    $title = 'Order #' . $order->get_order_number() . ' Update';
    $body  = sprintf(
        'Your order has been %s.',
        strtolower($new_label)
    );

    $data = [
        'type'       => 'order_update',
        'order_id'   => (int) $order_id,
        'order_no'   => $order->get_order_number(),
        'status'     => $new_status,
        'total'      => $order->get_total(),
        'currency'   => $order->get_currency(),
    ];

    zzmore_send_push_to_user($customer_id, $title, $body, $data);
}

// ─── New Order Notification ──────────────────────────────────────────────────

add_action('woocommerce_new_order', 'zzmore_notify_new_order', 10, 2);

function zzmore_notify_new_order($order_id, $order): void
{
    $customer_id = $order->get_customer_id();
    if (!$customer_id) return;

    $title = 'Order Confirmed!';
    $body  = sprintf(
        'Your order #%s has been placed successfully. Total: %s%s.',
        $order->get_order_number(),
        get_woocommerce_currency_symbol($order->get_currency()),
        $order->get_total()
    );

    $data = [
        'type'       => 'new_order',
        'order_id'   => (int) $order_id,
        'order_no'   => $order->get_order_number(),
        'status'     => $order->get_status(),
        'total'      => $order->get_total(),
        'currency'   => $order->get_currency(),
    ];

    zzmore_send_push_to_user($customer_id, $title, $body, $data);
}

// ─── Vendor-Specific: Order for vendor status change ─────────────────────────

add_action('woocommerce_order_status_changed', 'zzmore_notify_vendor_order_status', 20, 4);

function zzmore_notify_vendor_order_status($order_id, $old_status, $new_status, $order): void
{
    if (!function_exists('dokan_get_seller_id_by_order')) return;

    $seller_id = dokan_get_seller_id_by_order($order_id);
    if (!$seller_id) return;

    $status_labels = wc_get_order_statuses();
    $new_label = $status_labels['wc-' . $new_status] ?? ucfirst($new_status);

    $title = 'Order #' . $order->get_order_number();
    $body  = sprintf(
        'Order status changed to %s.',
        strtolower($new_label)
    );

    $data = [
        'type'       => 'vendor_order_update',
        'order_id'   => (int) $order_id,
        'order_no'   => $order->get_order_number(),
        'status'     => $new_status,
    ];

    zzmore_send_push_to_user($seller_id, $title, $body, $data);
}

// ─── Livestream Start Notification ───────────────────────────────────────────

/**
 * Hook into the Dokan livestream start event.
 * The exact action name depends on the Dokan version and livestream plugin used.
 * Common hooks:
 *   - dokan_livestream_started
 *   - dokan_after_livestream_start
 *   - dokan_vendor_livestream_start
 *   - wp_after_insert_post (for 'livestream' CPT with status 'publish')
 */
add_action('dokan_livestream_started', 'zzmore_notify_livestream_start', 10, 2);
add_action('dokan_after_livestream_start', 'zzmore_notify_livestream_start', 10, 2);
add_action('dokan_vendor_livestream_start', 'zzmore_notify_livestream_start', 10, 2);
add_action('dokan_live_stream_started', 'zzmore_notify_livestream_start', 10, 2);

// Also catch CPT publish for livestream post types
add_action('wp_after_insert_post', 'zzmore_notify_livestream_cpt_publish', 10, 4);

function zzmore_notify_livestream_start($vendor_id, $stream_data = []): void
{
    if (empty($vendor_id)) return;

    $vendor_name = '';
    if (function_exists('dokan')) {
        $vendor = dokan()->vendor->get($vendor_id);
        if ($vendor) {
            $vendor_name = $vendor->get_shop_name();
        }
    }
    if (empty($vendor_name)) {
        $user = get_userdata($vendor_id);
        $vendor_name = $user ? $user->display_name : 'A vendor';
    }

    $title = $vendor_name . ' is Live!';
    $body  = $vendor_name . ' just started a livestream. Watch now!';

    $data = [
        'type'        => 'livestream_start',
        'vendor_id'   => (int) $vendor_id,
        'vendor_name' => $vendor_name,
        'url'         => $stream_data['url'] ?? $stream_data['stream_url'] ?? '',
        'platform'    => $stream_data['platform'] ?? '',
    ];

    // Send to all users who follow this vendor or have opted into notifications
    zzmore_send_push_to_vendor_followers($vendor_id, $title, $body, $data);
}

function zzmore_notify_livestream_cpt_publish($post_id, $post, $update, $post_before): void
{
    if ($update) return; // Only for new posts

    $livestream_cpts = ['livestream', 'live_stream', 'dokan_livestream', 'vendor_livestream'];
    if (!in_array($post->post_type, $livestream_cpts, true)) return;

    $vendor_id = get_post_meta($post_id, 'vendor_id', true);
    if (empty($vendor_id)) return;

    $stream_url = get_post_meta($post_id, 'stream_url', true)
        ?: get_post_meta($post_id, 'livestream_url', true)
        ?: '';

    zzmore_notify_livestream_start($vendor_id, [
        'url'   => $stream_url,
        'title' => $post->post_title,
    ]);
}

// ─── FCM HTTP v1 Send Logic ──────────────────────────────────────────────────

/**
 * Send a push notification to a specific user across all their registered devices.
 */
function zzmore_send_push_to_user(int $user_id, string $title, string $body, array $data = []): void
{
    $tokens = get_user_meta($user_id, '_fcm_tokens', true);
    if (empty($tokens) || !is_array($tokens)) return;

    foreach ($tokens as $entry) {
        if (!empty($entry['token'])) {
            zzmore_send_fcm_message($entry['token'], $title, $body, $data);
        }
    }
}

/**
 * Send a push notification to all followers of a vendor.
 */
function zzmore_send_push_to_vendor_followers(int $vendor_id, string $title, string $body, array $data = []): void
{
    // Get all users who have interacted with this vendor (ordered products, etc.)
    // For performance, we target all users with registered FCM tokens.
    // A production system should use a dedicated followers table or user meta.
    $users = get_users([
        'meta_key'     => '_fcm_tokens',
        'meta_compare' => 'EXISTS',
        'number'       => 500,
        'fields'       => 'ID',
    ]);

    foreach ($users as $user_id) {
        zzmore_send_push_to_user($user_id, $title, $body, $data);
    }
}

/**
 * Read + validate the configured Firebase service account (see the
 * Configuration block at the top of this file). Result is cached for the
 * lifetime of the request.
 */
function zzmore_fcm_service_account(): ?array
{
    static $checked = false;
    static $account = null;
    if ($checked) return $account;
    $checked = true;

    $json = '';
    if (defined('ZZMORE_FCM_SERVICE_ACCOUNT_JSON') && ZZMORE_FCM_SERVICE_ACCOUNT_JSON) {
        $json = ZZMORE_FCM_SERVICE_ACCOUNT_JSON;
    } elseif (defined('ZZMORE_FCM_SERVICE_ACCOUNT_PATH') && ZZMORE_FCM_SERVICE_ACCOUNT_PATH && is_readable(ZZMORE_FCM_SERVICE_ACCOUNT_PATH)) {
        $json = (string) file_get_contents(ZZMORE_FCM_SERVICE_ACCOUNT_PATH);
    } else {
        $json = (string) get_option('zzmore_fcm_service_account_json', '');
    }

    if (empty($json)) {
        return null;
    }

    $data = json_decode($json, true);
    if (!is_array($data) || empty($data['client_email']) || empty($data['private_key']) || empty($data['project_id'])) {
        error_log('[ZZmore Push] FCM service account JSON is missing client_email/private_key/project_id.');
        return null;
    }

    $account = $data;
    return $account;
}

/**
 * Mint (and cache) a short-lived OAuth2 access token for the FCM v1 API via
 * the service-account JWT-bearer flow (RFC 7523) — implemented with core
 * PHP openssl functions only, no Google client library / Composer needed.
 */
function zzmore_fcm_access_token(): ?string
{
    $account = zzmore_fcm_service_account();
    if (!$account) return null;

    $cache_key = 'zzmore_fcm_access_token_' . md5($account['client_email']);
    $cached = get_transient($cache_key);
    if (is_string($cached) && $cached !== '') return $cached;

    $now = time();
    $b64url = function (string $s): string {
        return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    };

    $jwt_unsigned = $b64url(wp_json_encode(['alg' => 'RS256', 'typ' => 'JWT'])) . '.' . $b64url(wp_json_encode([
        'iss'   => $account['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'iat'   => $now,
        'exp'   => $now + 3600,
    ]));

    $signature = '';
    if (!openssl_sign($jwt_unsigned, $signature, $account['private_key'], 'SHA256')) {
        error_log('[ZZmore Push] Failed to sign FCM OAuth2 JWT — check the private_key field in the service account JSON.');
        return null;
    }
    $jwt = $jwt_unsigned . '.' . $b64url($signature);

    $response = wp_remote_post('https://oauth2.googleapis.com/token', [
        'headers' => ['Content-Type' => 'application/x-www-form-urlencoded'],
        'body'    => [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ],
        'timeout' => 10,
    ]);

    if (is_wp_error($response)) {
        error_log('[ZZmore Push] FCM OAuth2 token request error: ' . $response->get_error_message());
        return null;
    }
    if (wp_remote_retrieve_response_code($response) !== 200) {
        error_log('[ZZmore Push] FCM OAuth2 token HTTP ' . wp_remote_retrieve_response_code($response) . ': ' . wp_remote_retrieve_body($response));
        return null;
    }

    $body = json_decode(wp_remote_retrieve_body($response), true);
    $token = $body['access_token'] ?? null;
    if (!$token) return null;

    $expires_in = (int) ($body['expires_in'] ?? 3600);
    // Cache for a bit less than the real lifetime so we never hand out a
    // token that expires mid-flight.
    set_transient($cache_key, $token, max(60, $expires_in - 120));

    return $token;
}

/**
 * Core FCM v1 (HTTP) send function — one message to one device token.
 */
function zzmore_send_fcm_message(string $token, string $title, string $body, array $data = []): bool
{
    $account = zzmore_fcm_service_account();
    if (!$account) {
        error_log('[ZZmore Push] FCM service account not configured. Skipping push.');
        return false;
    }

    $access_token = zzmore_fcm_access_token();
    if (!$access_token) {
        error_log('[ZZmore Push] Could not obtain FCM OAuth2 access token. Skipping push.');
        return false;
    }

    // FCM v1 requires every `data` value to be a string.
    $string_data = array_merge($data, ['click_action' => 'FLUTTER_NOTIFICATION_CLICK']);
    foreach ($string_data as $k => $v) {
        $string_data[$k] = is_string($v) ? $v : (string) wp_json_encode($v);
    }

    $payload = [
        'message' => [
            'token'        => $token,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data'    => $string_data,
            'android' => [
                'notification' => [
                    'sound'      => 'default',
                    'channel_id' => 'zzmore_notifications',
                ],
            ],
            'apns' => [
                'payload' => [
                    'aps' => ['sound' => 'default'],
                ],
            ],
        ],
    ];

    $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($account['project_id']) . '/messages:send';

    $response = wp_remote_post($url, [
        'headers' => [
            'Authorization' => 'Bearer ' . $access_token,
            'Content-Type'  => 'application/json',
        ],
        'body'    => wp_json_encode($payload),
        'timeout' => 10,
    ]);

    if (is_wp_error($response)) {
        error_log('[ZZmore Push] FCM send error: ' . $response->get_error_message());
        return false;
    }

    $code = wp_remote_retrieve_response_code($response);
    if ($code !== 200) {
        $resp_body = wp_remote_retrieve_body($response);
        error_log('[ZZmore Push] FCM HTTP ' . $code . ': ' . $resp_body);
        // Unregistered/invalid tokens come back as 404 NOT_FOUND or 400
        // INVALID_ARGUMENT under v1 — clean those up so we stop retrying them.
        $decoded = json_decode($resp_body, true);
        $error_status = $decoded['error']['status'] ?? '';
        if (in_array($error_status, ['UNREGISTERED', 'NOT_FOUND', 'INVALID_ARGUMENT'], true)) {
            zzmore_cleanup_invalid_token($token);
        }
        return false;
    }

    return true;
}

/**
 * Remove an invalid/expired FCM token from all users.
 */
function zzmore_cleanup_invalid_token(string $token): void
{
    $users = get_users([
        'meta_key'     => '_fcm_tokens',
        'meta_compare' => 'EXISTS',
        'number'       => 200,
        'fields'       => 'ID',
    ]);

    foreach ($users as $user_id) {
        $tokens = get_user_meta($user_id, '_fcm_tokens', true);
        if (!is_array($tokens)) continue;

        $filtered = array_filter($tokens, fn($t) => isset($t['token']) && $t['token'] !== $token);
        if (count($filtered) !== count($tokens)) {
            update_user_meta($user_id, '_fcm_tokens', array_values($filtered));
        }
    }
}
