<?php
/**
 * Plugin Name: ZZmore Payment Links Bridge
 * Description: REST bridge for the Dokan Payment Links plugin so the ZZmore
 *              Flutter app can list / create / cancel vendor payment links
 *              using JWT authentication (same pattern as dokan-vendor-bridge.php).
 *
 * Endpoints:
 *   GET  /wp-json/vendor-bridge/v1/payment-links?page=N
 *   POST /wp-json/vendor-bridge/v1/payment-links
 *   POST /wp-json/vendor-bridge/v1/payment-links/{id}/cancel
 *
 * Requires: Dokan Payment Links plugin active + Dokan + JWT Auth plugin.
 * Install:  Drop into wp-content/mu-plugins/zzmore-payment-links.php
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_action( 'rest_api_init', function () {
	if ( ! function_exists( 'dokan_is_user_seller' ) ) {
		return;
	}

	$permission = function () {
		return is_user_logged_in() && dokan_is_user_seller( get_current_user_id() );
	};

	register_rest_route( 'vendor-bridge/v1', '/payment-links', [
		'methods'             => 'GET',
		'permission_callback' => $permission,
		'callback'            => 'zzmore_dpl_list_links',
	] );

	register_rest_route( 'vendor-bridge/v1', '/payment-links', [
		'methods'             => 'POST',
		'permission_callback' => $permission,
		'callback'            => 'zzmore_dpl_create_link',
	] );

	register_rest_route( 'vendor-bridge/v1', '/payment-links/(?P<id>\d+)/cancel', [
		'methods'             => 'POST',
		'permission_callback' => $permission,
		'callback'            => 'zzmore_dpl_cancel_link',
	] );
} );

/**
 * Whether the Dokan Payment Links plugin is fully bootstrapped.
 */
function zzmore_dpl_ready() {
	return function_exists( 'dpl' ) && class_exists( 'Dokan_Payment_Links' );
}

/**
 * GET — list the current vendor's payment links (paginated).
 */
function zzmore_dpl_list_links( WP_REST_Request $request ) {
	if ( ! zzmore_dpl_ready() ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is not active.', [ 'status' => 503 ] );
	}

	$vendor_id = get_current_user_id();
	$page      = max( 1, absint( $request->get_param( 'page' ) ) );

	return dpl()->payment_link->get_vendor_links( $vendor_id, 20, $page );
}

/**
 * POST — create a new payment link for the current vendor.
 */
function zzmore_dpl_create_link( WP_REST_Request $request ) {
	if ( ! zzmore_dpl_ready() ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is not active.', [ 'status' => 503 ] );
	}

	$vendor_id = get_current_user_id();

	// --- Enforce the plugin's per-vendor rate limit (mirrors DPL_Ajax) ---
	$limit     = absint( dpl_get_setting( 'rate_limit', 20 ) );
	$rate_key  = 'dpl_rate_limit_' . $vendor_id;
	$count     = absint( get_transient( $rate_key ) );
	if ( $count >= $limit ) {
		return new WP_Error(
			'rate_limited',
			sprintf( 'You have reached the limit of %d payment links per hour. Please try again later.', $limit ),
			[ 'status' => 429 ]
		);
	}

	$body = $request->get_json_params();
	if ( empty( $body ) ) {
		$body = $request->get_body_params();
	}

	$amount         = isset( $body['amount'] ) ? floatval( $body['amount'] ) : 0;
	$label          = isset( $body['label'] ) ? sanitize_text_field( wp_unslash( $body['label'] ) ) : '';
	$needs_shipping = ! empty( $body['needs_shipping'] );
	$delivery_note  = isset( $body['delivery_note'] ) ? sanitize_textarea_field( wp_unslash( $body['delivery_note'] ) ) : '';
	$expiry         = isset( $body['expiry'] ) ? sanitize_text_field( wp_unslash( $body['expiry'] ) ) : 'none';

	$valid_expiry = [ '24h', '3d', '7d', 'none' ];
	if ( ! in_array( $expiry, $valid_expiry, true ) ) {
		$expiry = 'none';
	}

	try {
		$result = dpl()->payment_link->create( [
			'vendor_id'      => $vendor_id,
			'amount'         => $amount,
			'label'          => $label,
			'needs_shipping' => $needs_shipping,
			'delivery_note'  => $delivery_note,
			'expiry'         => $expiry,
		] );

		// Increment rate limiter.
		set_transient( $rate_key, $count + 1, HOUR_IN_SECONDS );

		return [
			'link_id' => $result['link_id'],
			'pay_url' => $result['pay_url'],
			'status'  => $result['status'],
		];
	} catch ( Exception $e ) {
		return new WP_Error( 'dpl_create_failed', $e->getMessage(), [ 'status' => 400 ] );
	}
}

/**
 * POST — cancel an unpaid payment link (ownership-verified).
 */
function zzmore_dpl_cancel_link( WP_REST_Request $request ) {
	if ( ! zzmore_dpl_ready() ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is not active.', [ 'status' => 503 ] );
	}

	$vendor_id = get_current_user_id();
	$link_id   = absint( $request->get_param( 'id' ) );

	$result = dpl()->payment_link->cancel( $link_id, $vendor_id );
	if ( is_wp_error( $result ) ) {
		return $result;
	}

	return [ 'success' => true, 'message' => 'Payment link cancelled.' ];
}
