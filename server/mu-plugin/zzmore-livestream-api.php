<?php
/**
 * ZZmore App — Livestream REST API
 * =================================
 * Must-use plugin for WordPress.
 * Place this file in: wp-content/mu-plugins/zzmore-livestream-api.php
 *
 * Provides a clean REST endpoint to fetch all active livestreams
 * from Dokan vendors (or any registered livestream source).
 *
 * Endpoint: GET /wp-json/app/v1/livestreams
 *
 * Shortcode support: If a shortcode like [vendor_livestream] or
 * [dokan_livestream] exists, its output is parsed for stream URLs.
 * Falls back to querying Dokan vendor meta and custom post types.
 */

defined('ABSPATH') || exit;

// ─── Register REST endpoint ─────────────────────────────────────────────────

add_action('rest_api_init', 'zzmore_register_livestream_endpoints');

function zzmore_register_livestream_endpoints(): void
{
    // Public: Get all active livestreams
    register_rest_route('app/v1', '/livestreams', [
        'methods'             => 'GET',
        'callback'            => 'zzmore_get_livestreams',
        'permission_callback' => '__return_true',
    ]);

    // Vendor: Get own stream settings (JWT auth)
    register_rest_route('app/v1', '/livestreams/vendor', [
        'methods'             => 'GET',
        'callback'            => 'zzmore_get_vendor_livestream',
        'permission_callback' => function () {
            return current_user_can('dokandar') || current_user_can('seller') || is_user_logged_in();
        },
    ]);

    // Vendor: Save stream URL (JWT auth)
    register_rest_route('app/v1', '/livestreams/vendor', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_save_vendor_livestream',
        'permission_callback' => function () {
            return current_user_can('dokandar') || current_user_can('seller') || is_user_logged_in();
        },
    ]);

    // Vendor: Set active product for livestream
    register_rest_route('app/v1', '/livestreams/vendor/product', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_set_vendor_livestream_product',
        'permission_callback' => function () {
            return current_user_can('dokandar') || current_user_can('seller') || is_user_logged_in();
        },
    ]);

    // Back compat: /dokan/v1/livestreams → delegate to vendor endpoint
    register_rest_route('dokan/v1', '/livestreams', [
        'methods'             => 'GET',
        'callback'            => 'zzmore_get_vendor_livestream_dokan',
        'permission_callback' => function () {
            return current_user_can('dokandar') || current_user_can('seller') || is_user_logged_in();
        },
    ]);

    register_rest_route('dokan/v1', '/livestreams', [
        'methods'             => 'POST',
        'callback'            => 'zzmore_save_vendor_livestream_dokan',
        'permission_callback' => function () {
            return current_user_can('dokandar') || current_user_can('seller') || is_user_logged_in();
        },
    ]);
}

// ─── GET /app/v1/livestreams ────────────────────────────────────────────────

function zzmore_get_livestreams(): array
{
    $streams = [];

    // Priority 1: Try well-known shortcodes and extract structured data
    $streams = zzmore_fetch_from_shortcodes();
    if (!empty($streams)) {
        return zzmore_enrich_with_products($streams);
    }

    // Priority 2: Try Dokan vendor livestream meta
    $streams = zzmore_fetch_from_vendor_meta();
    if (!empty($streams)) {
        return zzmore_enrich_with_products($streams);
    }

    // Priority 3: Try custom post type 'livestream' or 'live_stream'
    $streams = zzmore_fetch_from_cpt();
    if (!empty($streams)) {
        return zzmore_enrich_with_products($streams);
    }

    // Priority 4: Query Dokan store settings for livestream URLs
    $streams = zzmore_fetch_from_dokan_settings();
    return zzmore_enrich_with_products($streams);
}

/**
 * Enrich stream data with active product info from the DLS REST API.
 * Calls /wp-json/dls/v1/stream/{vendor_id}/active-product for each stream
 * and merges product_name, product_price, product_id, and product_image.
 */
function zzmore_enrich_with_products(array $streams): array
{
    foreach ($streams as &$stream) {
        // Determine vendor ID from stream data
        $vendor_id = $stream['vendor_id'] ?? $stream['id'] ?? 0;
        if (empty($vendor_id)) continue;

        $product = zzmore_fetch_active_product($vendor_id);
        if (!empty($product)) {
            $stream['product_id']    = $product['product_id'] ?? null;
            $stream['product_name']  = $product['title'] ?? null;
            $stream['product_price'] = $product['price_raw'] ?? zzmore_strip_currency($product['price_html'] ?? '');
            $stream['product_image'] = $product['image_url'] ?? '';
        }
    }
    unset($stream);

    return $streams;
}

/**
 * Fetch the active product for a vendor via the DLS REST API.
 * Makes an internal HTTP request to /dls/v1/stream/{vendor_id}/active-product.
 */
function zzmore_fetch_active_product(int $vendor_id): ?array
{
    $transient_key = 'zzmore_live_prod_' . $vendor_id;
    $cached = get_transient($transient_key);
    if ($cached !== false) {
        return $cached;
    }

    $url = rest_url('dls/v1/stream/' . $vendor_id . '/active-product');
    $response = wp_remote_get($url, ['timeout' => 5]);

    if (is_wp_error($response) || wp_remote_retrieve_response_code($response) !== 200) {
        return null;
    }

    $body = json_decode(wp_remote_retrieve_body($response), true);
    if (empty($body['live']) || empty($body['product_id'])) {
        return null;
    }

    // Strip HTML tags from price_html and extract numeric value
    $price_html = $body['price_html'] ?? '';
    $price_raw = zzmore_strip_currency($price_html);

    $product = [
        'product_id'   => (int) $body['product_id'],
        'title'        => $body['title'] ?? '',
        'price_html'   => $price_html,
        'price_raw'    => $price_raw,
        'image_url'    => $body['image_url'] ?? '',
    ];

    // Cache for 30 seconds (product changes are infrequent but should be timely)
    set_transient($transient_key, $product, 30);

    return $product;
}

/**
 * Strip HTML and extract numeric price from a WooCommerce price HTML string.
 * e.g. '<span class="woocommerce-Price-amount"><bdi><span class="woocommerce-Price-currencySymbol">&pound;</span>24.99</bdi></span>' => '24.99'
 */
function zzmore_strip_currency(string $html): string
{
    $clean = wp_strip_all_tags($html);
    // Extract numeric value (supports . and , as decimal separators)
    if (preg_match('/[\d,.]+/', $clean, $matches)) {
        return $matches[0];
    }
    return '';
}

// ─── Priority 1: Parse shortcode output ─────────────────────────────────────

function zzmore_fetch_from_shortcodes(): array
{
    $streams = [];

    // List of known livestream shortcodes (try each)
    $shortcodes = [
        'vendor_livestream',
        'dokan_livestream',
        'dokan_live_stream',
        'dokan-livestream',
        'livestream',
        'live_stream',
        'vendor_live',
        'zzmore_livestream',
    ];

    foreach ($shortcodes as $tag) {
        if (shortcode_exists($tag)) {
            // Render with empty atts to get active streams grid
            $output = do_shortcode('[' . $tag . ']');
            $streams = zzmore_parse_livestream_html($output);
            if (!empty($streams)) {
                return $streams;
            }
        }
    }

    return $streams;
}

/**
 * Parse rendered shortcode HTML to extract stream data.
 * Handles common patterns: data-stream-url, data-vendor-name,
 * data-thumbnail, iframe src, or YouTube/Twitch links.
 */
function zzmore_parse_livestream_html(string $html): array
{
    $streams = [];

    // Try extracting from data-* attributes first (most reliable)
    if (preg_match_all(
        '/<[^>]+data-stream-id=["\']?(\d+)["\']?[^>]*>/i',
        $html, $id_matches, PREG_SET_ORDER
    )) {
        foreach ($id_matches as $match) {
            $full_tag = $match[0];
            $stream = [
                'id'         => (int) $match[1],
                'platform'   => 'youtube',
                'status'     => 'live',
                'viewers'    => '0',
            ];

            // Extract other data attributes
            if (preg_match('/data-stream-url=["\']([^"\']+)["\']/i', $full_tag, $u)) {
                $stream['url'] = $u[1];
            }
            if (preg_match('/data-vendor-name=["\']([^"\']+)["\']/i', $full_tag, $v)) {
                $stream['vendor_name'] = html_entity_decode($v[1]);
            }
            if (preg_match('/data-title=["\']([^"\']+)["\']/i', $full_tag, $t)) {
                $stream['title'] = html_entity_decode($t[1]);
            }
            if (preg_match('/data-thumbnail=["\']([^"\']+)["\']/i', $full_tag, $th)) {
                $stream['thumbnail'] = $th[1];
            }
            if (preg_match('/data-viewers=["\']([^"\']+)["\']/i', $full_tag, $vw)) {
                $stream['viewers'] = $vw[1];
            }
            if (preg_match('/data-platform=["\']([^"\']+)["\']/i', $full_tag, $p)) {
                $stream['platform'] = $p[1];
            }
            if (preg_match('/data-store-name=["\']([^"\']+)["\']/i', $full_tag, $sn)) {
                $stream['store_name'] = html_entity_decode($sn[1]);
            }
            if (preg_match('/data-vendor-avatar=["\']([^"\']+)["\']/i', $full_tag, $av)) {
                $stream['vendor_avatar'] = $av[1];
            }

            // Detect platform from URL if not explicitly set
            if (empty($stream['platform']) && !empty($stream['url'])) {
                $stream['platform'] = zzmore_detect_platform($stream['url']);
            }

            $streams[] = $stream;
        }
    }

    // Fallback: extract YouTube/Twitch embeds from iframes
    if (empty($streams) && preg_match_all(
        '/<iframe[^>]+src=["\'](https?:\/\/(?:www\.)?(?:youtube\.com\/embed\/|player\.twitch\.tv\/)[^"\']+)["\'][^>]*>/i',
        $html, $iframe_matches, PREG_SET_ORDER
    )) {
        foreach ($iframe_matches as $i => $match) {
            $url = $match[1];
            $stream = [
                'id'       => $i + 10000, // Synthetic ID
                'url'      => $url,
                'platform' => zzmore_detect_platform($url),
                'status'   => 'live',
                'viewers'  => '0',
            ];

            // Try to extract title from surrounding HTML
            if (preg_match('/<h[34][^>]*>(.+?)<\/h[34]>/i', $html, $title_m)) {
                $stream['title'] = html_entity_decode(strip_tags($title_m[1]));
            }

            $streams[] = $stream;
        }
    }

    // Fallback: extract direct YouTube/Twitch links
    if (empty($streams) && preg_match_all(
        '/https?:\/\/(?:www\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/|twitch\.tv\/)([a-zA-Z0-9_\-]+)/i',
        $html, $link_matches, PREG_SET_ORDER
    )) {
        foreach ($link_matches as $i => $match) {
            $streams[] = [
                'id'       => $i + 20000,
                'url'      => $match[0],
                'platform' => zzmore_detect_platform($match[0]),
                'status'   => 'live',
                'viewers'  => '0',
            ];
        }
    }

    return $streams;
}

// ─── Priority 2: Query Dokan vendor livestream meta ─────────────────────────

function zzmore_fetch_from_vendor_meta(): array
{
    $streams = [];

    if (!function_exists('dokan_get_sellers')) {
        return $streams;
    }

    $sellers = dokan_get_sellers(['number' => 50]);
    if (empty($sellers['users'])) {
        return $streams;
    }

    foreach ($sellers['users'] as $seller) {
        $user_id = is_object($seller) ? $seller->ID : ($seller['ID'] ?? 0);
        if (!$user_id) continue;

        // Check for various possible livestream meta keys
        // Priority: the DLS (Dokan Live Stream) plugin uses 'dls_stream_url'
        $meta_keys = [
            'dls_stream_url',          // DLS plugin primary key
            'dls_stream_status',       // DLS plugin status
            'dokan_livestream_url',
            'dokan_live_stream_url',
            'vendor_livestream_url',
            'dokan_live_status',
            'vendor_live_status',
            'dokan_live_url',
            'livestream_url',
            'dokan_livestream_data',
        ];

        $live_url = '';
        $live_status = '';
        foreach ($meta_keys as $key) {
            $value = get_user_meta($user_id, $key, true);
            if (!empty($value)) {
                if (in_array($key, ['dokan_live_status', 'vendor_live_status'])) {
                    $live_status = $value;
                } else {
                    $live_url = $value;
                }
            }
        }

        // Also check store settings
        if (empty($live_url)) {
            $store_settings = get_user_meta($user_id, 'dokan_profile_settings', true);
            if (is_array($store_settings)) {
                $live_url = $store_settings['livestream_url'] ?? $store_settings['live_url'] ?? '';
                $live_status = $live_status ?: ($store_settings['livestream_status'] ?? $store_settings['is_live'] ?? '');
            }
        }

        // Only include if live or no status set (assume live if URL present)
        $status = strtolower($live_status);
        if (!empty($live_url) && ($status === 'live' || $status === '1' || $status === 'yes' || $status === '')) {
            $vendor_info = get_userdata($user_id);
            $store_info = dokan()->vendor->get($user_id)->get_shop_info() ?: [];
            $store_name = $store_info['store_name'] ?? ($vendor_info ? $vendor_info->display_name : '');
            $store_avatar = $store_info['gravatar'] ?? '';

            $streams[] = [
                'id'              => (int) $user_id,
                'vendor_id'       => (int) $user_id,
                'url'             => $live_url,
                'platform'        => zzmore_detect_platform($live_url),
                'vendor_name'     => $store_name,
                'vendor_avatar'   => $store_avatar,
                'store_name'      => $store_name,
                'store_avatar'    => $store_avatar,
                'title'           => $store_name . ' Live Stream',
                'status'          => 'live',
                'viewers'         => '0',
            ];
        }
    }

    return $streams;
}

// ─── Priority 3: Custom post type query ──────────────────────────────────────

function zzmore_fetch_from_cpt(): array
{
    $streams = [];

    // Try common CPT slugs for livestreams
    $cpt_slugs = ['livestream', 'live_stream', 'dokan_livestream', 'vendor_livestream'];
    $active_cpt = '';

    foreach ($cpt_slugs as $slug) {
        if (post_type_exists($slug)) {
            $active_cpt = $slug;
            break;
        }
    }

    if (empty($active_cpt)) {
        return $streams;
    }

    $query = new WP_Query([
        'post_type'      => $active_cpt,
        'post_status'    => 'publish',
        'posts_per_page' => 20,
        'meta_query'     => [
            [
                'key'     => 'stream_status',
                'value'   => 'live',
                'compare' => '=',
            ],
        ],
    ]);

    while ($query->have_posts()) {
        $query->the_post();
        $post_id = get_the_ID();

        $url = get_post_meta($post_id, 'stream_url', true)
            ?: get_post_meta($post_id, 'livestream_url', true)
            ?: '';

        if (empty($url)) continue;

        $vendor_id = get_post_meta($post_id, 'vendor_id', true);
        $vendor_name = '';
        $vendor_avatar = '';
        if ($vendor_id) {
            $vendor_info = get_userdata($vendor_id);
            $vendor_name = $vendor_info ? $vendor_info->display_name : '';
        }

        $streams[] = [
            'id'            => $post_id,
            'url'           => $url,
            'platform'      => zzmore_detect_platform($url),
            'title'         => get_the_title(),
            'thumbnail'     => get_the_post_thumbnail_url($post_id, 'medium') ?: '',
            'vendor_name'   => $vendor_name,
            'vendor_avatar' => $vendor_avatar,
            'store_name'    => $vendor_name,
            'status'        => 'live',
            'viewers'       => get_post_meta($post_id, 'viewer_count', true) ?: '0',
        ];
    }
    wp_reset_postdata();

    return $streams;
}

// ─── Priority 4: Dokan store settings ───────────────────────────────────────

function zzmore_fetch_from_dokan_settings(): array
{
    $streams = [];

    if (!function_exists('dokan_get_sellers')) {
        return $streams;
    }

    // Try the Dokan REST API internally if available
    $stores = dokan()->vendor->all(['number' => 50]);
    foreach ($stores as $store) {
        $store_id = $store->get_id();
        $settings = get_user_meta($store_id, 'dokan_profile_settings', true);
        if (!is_array($settings)) continue;

        $is_live = $settings['is_livestream_active']
            ?? $settings['live_status']
            ?? $settings['going_live']
            ?? '';

        if (in_array(strtolower((string)$is_live), ['yes', '1', 'true', 'active', 'live'], true)) {
            $streams[] = [
                'id'            => (int) $store_id,
                'url'           => $settings['livestream_url'] ?? $settings['live_stream_url'] ?? '',
                'platform'      => zzmore_detect_platform($settings['livestream_url'] ?? ''),
                'vendor_name'   => $store->get_shop_name(),
                'store_name'    => $store->get_shop_name(),
                'title'         => $store->get_shop_name() . ' — Live Now',
                'status'        => 'live',
                'viewers'       => '0',
            ];
        }
    }

    return $streams;
}

// ─── Vendor Livestream Endpoints ─────────────────────────────────────────────

/**
 * GET /app/v1/livestreams/vendor — Get the current vendor's stream settings.
 * Returns the vendor's stream URL, status, active product, etc.
 */
function zzmore_get_vendor_livestream(WP_REST_Request $request): array
{
    $vendor_id = get_current_user_id();
    $streams = [];

    $stream_url = get_user_meta($vendor_id, 'dls_stream_url', true);
    $status = get_user_meta($vendor_id, 'dls_stream_status', true);

    if (!empty($stream_url)) {
        $store_info = function_exists('dokan_get_store_info')
            ? dokan_get_store_info($vendor_id)
            : [];
        $store_name = $store_info['store_name'] ?? '';

        $stream = [
            'id'          => $vendor_id,
            'vendor_id'   => $vendor_id,
            'title'       => $store_name ? $store_name . ' — Live Stream' : 'My Live Stream',
            'url'         => $stream_url,
            'stream_url'  => $stream_url,
            'platform'    => zzmore_detect_platform($stream_url),
            'status'      => ($status === 'suspended') ? 'ended' : 'live',
            'vendor_name' => $store_name,
            'store_name'  => $store_name,
            'viewers'     => '0',
            'description' => '',
            'scheduled_at' => '',
            'product_ids'  => [],
        ];

        // Get active product
        $product = zzmore_fetch_active_product($vendor_id);
        if (!empty($product)) {
            $stream['product_id']    = $product['product_id'];
            $stream['product_name']  = $product['title'];
            $stream['product_price'] = $product['price_raw'];
            $stream['product_image'] = $product['image_url'];
            $stream['product_ids']   = [$product['product_id']];
        }

        $streams[] = $stream;
    }

    return $streams;
}

/**
 * POST /app/v1/livestreams/vendor — Save/update the vendor's stream URL.
 */
function zzmore_save_vendor_livestream(WP_REST_Request $request): array
{
    $vendor_id = get_current_user_id();
    $params = $request->get_json_params();

    $stream_url = sanitize_text_field($params['stream_url'] ?? $params['url'] ?? '');
    $title = sanitize_text_field($params['title'] ?? '');
    $description = sanitize_textarea_field($params['description'] ?? '');

    if (empty($stream_url)) {
        return new WP_Error('missing_url', 'Stream URL is required.', ['status' => 400]);
    }

    update_user_meta($vendor_id, 'dls_stream_url', $stream_url);

    // Clear any suspension
    $current_status = get_user_meta($vendor_id, 'dls_stream_status', true);
    if ($current_status === 'suspended') {
        delete_user_meta($vendor_id, 'dls_stream_status');
    }

    // If a product ID is provided, set it as active
    $product_id = intval($params['product_id'] ?? 0);
    if ($product_id > 0) {
        set_transient('dls_live_prod_vendor_' . $vendor_id, $product_id, HOUR_IN_SECONDS);
    }

    // Purge cache
    if (class_exists('LiteSpeed_Cache_API')) {
        LiteSpeed_Cache_API::purge('dls_stream_' . $vendor_id);
    }

    return [
        'id'          => $vendor_id,
        'vendor_id'   => $vendor_id,
        'stream_url'  => $stream_url,
        'url'         => $stream_url,
        'title'       => $title,
        'platform'    => zzmore_detect_platform($stream_url),
        'status'      => 'live',
        'product_ids' => $product_id > 0 ? [$product_id] : [],
    ];
}

/**
 * POST /app/v1/livestreams/vendor/product — Set the active product for the vendor's livestream.
 */
function zzmore_set_vendor_livestream_product(WP_REST_Request $request): array
{
    $vendor_id = get_current_user_id();
    $params = $request->get_json_params();
    $product_id = intval($params['product_id'] ?? 0);

    if ($product_id <= 0) {
        return new WP_Error('invalid_product', 'Valid product_id is required.', ['status' => 400]);
    }

    // Verify the product belongs to this vendor
    $product = wc_get_product($product_id);
    if (!$product || (int) $product->get_post_data()->post_author !== $vendor_id) {
        return new WP_Error('unauthorized', 'You do not own this product.', ['status' => 403]);
    }

    set_transient('dls_live_prod_vendor_' . $vendor_id, $product_id, HOUR_IN_SECONDS);

    return [
        'success'    => true,
        'product_id' => $product_id,
        'title'      => $product->get_name(),
    ];
}

/**
 * GET /dokan/v1/livestreams — Back-compat wrapper for Flutter Dokan API client.
 * Delegates to the vendor endpoint and returns data in Dokan's expected format.
 */
function zzmore_get_vendor_livestream_dokan(WP_REST_Request $request): array
{
    return zzmore_get_vendor_livestream($request);
}

/**
 * POST /dokan/v1/livestreams — Back-compat wrapper for Flutter Dokan API client.
 */
function zzmore_save_vendor_livestream_dokan(WP_REST_Request $request): array
{
    $result = zzmore_save_vendor_livestream($request);

    if (is_wp_error($result)) {
        return $result;
    }

    // Dokan API client expects a response with the created stream data
    return $result;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function zzmore_detect_platform(string $url): string
{
    $url = strtolower($url);
    if (strpos($url, 'youtube.com') !== false || strpos($url, 'youtu.be') !== false) {
        return 'youtube';
    }
    if (strpos($url, 'twitch.tv') !== false) {
        return 'twitch';
    }
    if (strpos($url, 'facebook.com') !== false || strpos($url, 'fb.watch') !== false) {
        return 'facebook';
    }
    if (strpos($url, 'instagram.com') !== false) {
        return 'instagram';
    }
    if (strpos($url, 'tiktok.com') !== false) {
        return 'tiktok';
    }
    return 'custom';
}
