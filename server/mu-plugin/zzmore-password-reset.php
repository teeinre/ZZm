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
