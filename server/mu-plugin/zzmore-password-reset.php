<?php
/**
 * Plugin Name: ZZmore Password Reset
 * Description: Secure password-reset REST endpoints for the ZZmore Flutter app.
 *              Uses WordPress core reset-key generation (with built-in 24h
 *              expiration) so the reset flow matches core security semantics.
 *
 * Endpoints:
 *   POST /wp-json/app/v1/forgot-password   -> validate email + send reset link
 *   POST /wp-json/app/v1/reset-password    -> validate key + set new password
 *
 * Install: Drop in wp-content/mu-plugins/zzmore-password-reset.php
 */

if ( ! defined( 'ABSPATH' ) ) exit;

add_action( 'rest_api_init', 'zzmore_register_password_reset_routes' );

// Inject the in-app deep link into the reset email so tapping the link opens
// the ZZmore app (instead of the web reset form). Priority 99 runs after other
// plugins so the app link is always present.
add_filter( 'retrieve_password_notification_email', 'zzmore_app_reset_email', 99, 4 );

function zzmore_register_password_reset_routes(): void {
    register_rest_route( 'app/v1', '/forgot-password', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'zzmore_forgot_password',
        'args'                => [
            'email' => [ 'required' => true, 'type' => 'string' ],
        ],
    ] );

    register_rest_route( 'app/v1', '/reset-password', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'zzmore_reset_password',
        'args'                => [
            'key'      => [ 'required' => true, 'type' => 'string' ],
            'login'    => [ 'required' => true, 'type' => 'string' ],
            'password' => [ 'required' => true, 'type' => 'string' ],
        ],
    ] );
}

/**
 * POST /app/v1/forgot-password
 *
 * Body: { "email": "user@example.com" }
 *
 * Validates the email format, rate-limits by email address, then uses the
 * canonical WordPress reset flow to generate a secure key (24h expiry) and
 * email a reset link. Returns a deliberately generic message whether or not
 * the account exists, to avoid leaking which emails are registered.
 */
function zzmore_forgot_password( WP_REST_Request $request ) {
    $email = sanitize_email( (string) $request->get_param( 'email' ) );

    // Server-side validation: reject malformed emails early.
    if ( ! is_email( $email ) ) {
        return new WP_Error(
            'invalid_email',
            __( 'Please enter a valid email address.', 'zzmore' ),
            [ 'status' => 400 ]
        );
    }

    // Simple per-email rate limit to mitigate abuse (60s between attempts).
    $limit_key = 'zzmore_pr_' . md5( strtolower( $email ) );
    if ( get_transient( $limit_key ) ) {
        return new WP_Error(
            'too_many_requests',
            __( 'Please wait a moment before requesting another reset link.', 'zzmore' ),
            [ 'status' => 429 ]
        );
    }
    set_transient( $limit_key, 1, 60 );

    // Canonical secure flow: generates a reset key, stores its hash with
    // expiration, and emails the reset link. Returns true or WP_Error.
    $result = function_exists( 'retrieve_password' )
        ? retrieve_password( $email )
        : new WP_Error( 'not_available', 'Password reset is unavailable.' );

    // Always return a generic success to prevent user enumeration.
    // (The email format was already validated above.)
    return [
        'success' => true,
        'message' => __(
            'If an account exists for this email, a password reset link has been sent.',
            'zzmore'
        ),
    ];
}

/**
 * POST /app/v1/reset-password
 *
 * Body: { "key": "...", "login": "username-or-email", "password": "newPass" }
 *
 * Validates the reset key (including its expiration) and, on success, sets the
 * new password using WordPress core. This supports an in-app "set new password"
 * screen when the reset link is opened inside the app.
 */
function zzmore_reset_password( WP_REST_Request $request ) {
    $key       = sanitize_text_field( (string) $request->get_param( 'key' ) );
    $login     = sanitize_text_field( (string) $request->get_param( 'login' ) );
    $password  = (string) $request->get_param( 'password' );

    if ( '' === $key || '' === $login ) {
        return new WP_Error( 'missing_fields', __( 'Reset key and login are required.', 'zzmore' ), [ 'status' => 400 ] );
    }

    if ( strlen( $password ) < 8 ) {
        return new WP_Error( 'weak_password', __( 'Password must be at least 8 characters.', 'zzmore' ), [ 'status' => 400 ] );
    }

    // Resolve the login (username or email) to a user, then validate the key.
    $user = check_password_reset_key( $key, $login );
    if ( is_wp_error( $user ) ) {
        // Invalid or expired key.
        return new WP_Error(
            'invalid_reset_key',
            __( 'This reset link is invalid or has expired. Please request a new one.', 'zzmore' ),
            [ 'status' => 400 ]
        );
    }

    // Set the new password (fires core hooks + clears the reset key).
    reset_password( $user, $password );

    return [
        'success' => true,
        'message' => __( 'Your password has been updated. You can now sign in.', 'zzmore' ),
    ];
}

/**
 * Rebuild the WordPress reset email as HTML so it contains a tappable deep
 * link (zzmore://reset-password?key=...&login=...) that opens the app, with the
 * standard web reset form kept as a fallback.
 */
function zzmore_app_reset_email( $retrieve_email, $key, $user_login, $user_data ) {
    $app_link = 'zzmore://reset-password?key=' . rawurlencode( $key ) . '&login=' . rawurlencode( $user_login );
    $web_link = network_site_url(
        "wp-login.php?action=rp&key=$key&login=" . rawurlencode( $user_login ),
        'login'
    );

    $site_name = wp_specialchars_decode( get_option( 'blogname' ), ENT_QUOTES );

    $message  = '<p>' . sprintf(
        __( 'Someone requested a password reset for your account on %s.', 'zzmore' ),
        esc_html( $site_name )
    ) . '</p>';
    $message .= '<p>' . sprintf(
        __( 'Username: %s', 'zzmore' ),
        esc_html( $user_login )
    ) . '</p>';
    $message .= '<p style="margin:24px 0">'
        . '<a href="' . esc_url( $app_link, array( 'zzmore' ) ) . '" '
        . 'style="background:#E67E14;color:#ffffff;padding:12px 24px;text-decoration:none;border-radius:6px;display:inline-block">'
        . esc_html__( 'Reset your password', 'zzmore' )
        . '</a></p>';
    $message .= '<p>' . esc_html__( "If the button does not open the app, tap or copy this link:", 'zzmore' ) . '<br>'
        . esc_html( $app_link ) . '</p>';
    $message .= '<p>' . esc_html__( 'Or reset via the website:', 'zzmore' ) . '<br>'
        . '<a href="' . esc_url( $web_link ) . '">' . esc_html( $web_link ) . '</a></p>';

    $retrieve_email['message'] = $message;
    $retrieve_email['headers'] = 'Content-Type: text/html; charset=UTF-8';

    return $retrieve_email;
}
