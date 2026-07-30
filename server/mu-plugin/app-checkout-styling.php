<?php
/**
 * Plugin Name: App Checkout Styling for zzmore.store
 * Description: Strips WordPress theme on checkout pages when accessed from the
 *              Flutter app WebView (detected via app_checkout cookie).
 *              Serves a bare, Flutter-styled template matching the app's design.
 *
 * Install: Drop in wp-content/mu-plugins/app-checkout-styling.php
 */

if ( ! defined( 'ABSPATH' ) ) exit;

// =========================================================================
// 1. Detect app checkout request
// =========================================================================
function is_app_checkout(): bool {
    return isset( $_COOKIE['app_checkout'] ) && $_COOKIE['app_checkout'] === '1';
}

// =========================================================================
// 2. Strip the theme on app checkout pages
// =========================================================================
add_action( 'init', function () {
    if ( ! is_app_checkout() ) return;

    // Remove theme assets
    add_action( 'wp_enqueue_scripts', 'app_checkout_strip_styles', 999 );
    add_action( 'wp_enqueue_scripts', 'app_checkout_enqueue_styles' );

    // Strip admin bar
    add_filter( 'show_admin_bar', '__return_false' );
} );

function app_checkout_strip_styles() {
    global $wp_styles;
    // Dequeue ALL enqueued styles, then we re-add only our own
    foreach ( $wp_styles->queue as $handle ) {
        wp_dequeue_style( $handle );
    }
}

function app_checkout_enqueue_styles() {
    $css_url = plugin_dir_url( __FILE__ ) . 'templates/app-checkout.css';
    $css_ver = filemtime( __DIR__ . '/templates/app-checkout.css' ) ?: '1.0';
    wp_enqueue_style( 'app-checkout', $css_url, [], $css_ver );
}

// =========================================================================
// 3. Swap to bare template
// =========================================================================
add_filter( 'template_include', function ( $template ) {
    if ( ! is_app_checkout() ) return $template;
    if ( ! function_exists( 'is_checkout' ) || ! is_checkout() ) return $template;

    $bare_template = __DIR__ . '/templates/app-checkout-bare.php';
    if ( file_exists( $bare_template ) ) {
        return $bare_template;
    }
    return $template;
}, 999 );

// =========================================================================
// 4. Provide Flutter with the order-received redirect URL
// (already handled by the bridge's native NavigationDelegate)
// =========================================================================
