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

    // OTP-based in-app reset flow.
    register_rest_route( 'app/v1', '/request-otp', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'zzmore_request_otp',
        'args'                => [
            'email' => [ 'required' => true, 'type' => 'string' ],
        ],
    ] );

    register_rest_route( 'app/v1', '/verify-otp', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'zzmore_verify_otp',
        'args'                => [
            'email'    => [ 'required' => true, 'type' => 'string' ],
            'otp'      => [ 'required' => true, 'type' => 'string' ],
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
 * POST /app/v1/request-otp
 *
 * Body: { "email": "user@example.com" }
 *
 * Generates a 6-digit one-time password, stores it server-side for 10 minutes,
 * and emails it to the user. Returns a generic success message regardless of
 * whether the account exists, to avoid user enumeration.
 */
function zzmore_request_otp( WP_REST_Request $request ) {
    $email = sanitize_email( (string) $request->get_param( 'email' ) );

    if ( ! is_email( $email ) ) {
        return new WP_Error(
            'invalid_email',
            __( 'Please enter a valid email address.', 'zzmore' ),
            [ 'status' => 400 ]
        );
    }

    // Rate-limit per email (60s) to reduce abuse.
    $limit_key = 'zzmore_otp_rl_' . md5( strtolower( $email ) );
    if ( get_transient( $limit_key ) ) {
        return new WP_Error(
            'too_many_requests',
            __( 'Please wait a moment before requesting another code.', 'zzmore' ),
            [ 'status' => 429 ]
        );
    }
    set_transient( $limit_key, 1, 60 );

    $user = get_user_by( 'email', $email );
    if ( ! $user ) {
        // Generic response to prevent enumeration.
        return [
            'success' => true,
            'message' => __( 'If an account exists for this email, a verification code has been sent.', 'zzmore' ),
        ];
    }

    $otp = zzmore_generate_otp();
    // Store a salted hash of the code so the plain value never persists.
    set_transient( 'zzmore_otp_' . md5( strtolower( $email ) ), wp_hash( $otp ), 10 * MINUTE_IN_SECONDS );

    zzmore_send_otp_email( $email, $user, $otp );

    return [
        'success' => true,
        'message' => __( 'If an account exists for this email, a verification code has been sent.', 'zzmore' ),
    ];
}

/**
 * POST /app/v1/verify-otp
 *
 * Body: { "email": "...", "otp": "123456", "password": "newPass123" }
 *
 * Validates the OTP (value, expiration, and match to the email), enforces the
 * new-password strength requirements, then updates the user's password.
 */
function zzmore_verify_otp( WP_REST_Request $request ) {
    $email    = sanitize_email( (string) $request->get_param( 'email' ) );
    $otp      = sanitize_text_field( (string) $request->get_param( 'otp' ) );
    $password = (string) $request->get_param( 'password' );

    if ( ! is_email( $email ) ) {
        return new WP_Error( 'invalid_email', __( 'Please enter a valid email address.', 'zzmore' ), [ 'status' => 400 ] );
    }

    if ( '' === $otp ) {
        return new WP_Error( 'missing_otp', __( 'Please enter the verification code.', 'zzmore' ), [ 'status' => 400 ] );
    }

    // Password strength: minimum 8 chars containing at least a letter and a number.
    if ( strlen( $password ) < 8 ) {
        return new WP_Error( 'weak_password', __( 'Password must be at least 8 characters.', 'zzmore' ), [ 'status' => 400 ] );
    }
    if ( ! preg_match( '/[A-Za-z]/', $password ) || ! preg_match( '/[0-9]/', $password ) ) {
        return new WP_Error(
            'weak_password',
            __( 'Password must contain at least one letter and one number.', 'zzmore' ),
            [ 'status' => 400 ]
        );
    }

    $user = get_user_by( 'email', $email );
    if ( ! $user ) {
        // Generic failure to avoid enumeration.
        return new WP_Error( 'invalid_otp', __( 'This code is invalid or has expired. Please request a new one.', 'zzmore' ), [ 'status' => 400 ] );
    }

    $stored = get_transient( 'zzmore_otp_' . md5( strtolower( $email ) ) );
    if ( ! $stored || ! hash_equals( (string) $stored, wp_hash( $otp ) ) ) {
        return new WP_Error( 'invalid_otp', __( 'This code is invalid or has expired. Please request a new one.', 'zzmore' ), [ 'status' => 400 ] );
    }

    // Code is valid and consumed — remove it before changing the password.
    delete_transient( 'zzmore_otp_' . md5( strtolower( $email ) ) );

    wp_set_password( $password, $user->ID );

    return [
        'success' => true,
        'message' => __( 'Your password has been changed successfully. You can now sign in.', 'zzmore' ),
    ];
}

/**
 * Generates a cryptographically random 6-digit numeric OTP.
 */
function zzmore_generate_otp(): string {
    try {
        return (string) random_int( 100000, 999999 ); // Always a 6-digit code.
    } catch ( \Throwable $e ) {
        return (string) wp_rand( 100000, 999999 );
    }
}

/**
 * Emails the verification code to the user as a simple HTML message.
 */
function zzmore_send_otp_email( string $email, WP_User $user, string $otp ): void {
    $site_name = wp_specialchars_decode( get_option( 'blogname' ), ENT_QUOTES );
    $code      = str_pad( $otp, 6, '0', STR_PAD_LEFT );

    $subject = sprintf( __( 'Your %s verification code', 'zzmore' ), $site_name );

    $message  = '<p>' . sprintf( __( 'Hello %s,', 'zzmore' ), esc_html( $user->display_name ) ) . '</p>';
    $message .= '<p>' . sprintf(
        __( 'Use the verification code below to reset your %s password:', 'zzmore' ),
        esc_html( $site_name )
    ) . '</p>';
    $message .= '<p style="margin:24px 0;font-size:32px;font-weight:bold;letter-spacing:6px;color:#E67E14">' . esc_html( $code ) . '</p>';
    $message .= '<p>' . __( 'This code expires in 10 minutes. If you did not request it, you can safely ignore this email.', 'zzmore' ) . '</p>';

    wp_mail( $email, $subject, $message, [ 'Content-Type: text/html; charset=UTF-8' ] );
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
