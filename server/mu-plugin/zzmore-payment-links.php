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
 *   GET  /wp-json/vendor-bridge/v1/payment-links/{id}/orders
 *
 * Requires: Dokan Payment Links plugin active + Dokan + JWT Auth plugin.
 * Install:  Drop into wp-content/mu-plugins/zzmore-payment-links.php
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

add_action( 'rest_api_init', function () {
	// Diagnostic route — no auth, no Dokan dependency. Confirms the bridge is
	// loaded and reports whether the Dokan Payment Links plugin exposes the
	// exact methods this bridge depends on.
	register_rest_route( 'vendor-bridge/v1', '/payment-links/ping', [
		'methods'             => 'GET',
		'permission_callback' => '__return_true',
		'callback'            => 'zzmore_dpl_ping',
	] );

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

	register_rest_route( 'vendor-bridge/v1', '/payment-links/(?P<id>\d+)/orders', [
		'methods'             => 'GET',
		'permission_callback' => $permission,
		'callback'            => 'zzmore_dpl_link_orders',
	] );
} );

/**
 * Whether the Dokan Payment Links plugin is fully bootstrapped.
 */
function zzmore_dpl_ready() {
	if ( ! function_exists( 'dpl' ) || ! class_exists( 'Dokan_Payment_Links' ) ) {
		return false;
	}

	$link = dpl()->payment_link ?? null;

	return is_object( $link )
		&& method_exists( $link, 'get_vendor_links' )
		&& method_exists( $link, 'create' )
		&& method_exists( $link, 'cancel' );
}

/**
 * Diagnostic — reports whether the Dokan Payment Links plugin is loaded and
 * exposes the exact methods this bridge calls. Hit this to confirm the deployed
 * plugin version matches the bridge.
 */
function zzmore_dpl_ping() {
	$instance = function_exists( 'dpl' ) ? dpl() : null;
	$link     = $instance ? ( $instance->payment_link ?? null ) : null;
	$order    = $instance ? ( $instance->order ?? null ) : null;

	return [
		'dpl_function'     => function_exists( 'dpl' ),
		'dpl_class'        => class_exists( 'Dokan_Payment_Links' ),
		'plugin_version'   => defined( 'DPL_VERSION' ) ? DPL_VERSION : null,
		'has_payment_link' => is_object( $link ),
		'get_vendor_links' => is_object( $link ) && method_exists( $link, 'get_vendor_links' ),
		'create'           => is_object( $link ) && method_exists( $link, 'create' ),
		'cancel'           => is_object( $link ) && method_exists( $link, 'cancel' ),
		'get_link'         => is_object( $link ) && method_exists( $link, 'get_link' ),
		'has_order'        => is_object( $order ),
		'get_link_orders'  => is_object( $order ) && method_exists( $order, 'get_link_orders' ),
	];
}

/**
 * GET — list the current vendor's payment links (paginated).
 */
function zzmore_dpl_list_links( WP_REST_Request $request ) {
	if ( ! zzmore_dpl_ready() ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is missing or its API does not match this bridge.', [ 'status' => 503 ] );
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
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is missing or its API does not match this bridge.', [ 'status' => 503 ] );
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

		// Normalise the plugin's return value (array, object, or WP_Error)
		// so the app always receives a consistent { link_id, pay_url, status }.
		if ( is_wp_error( $result ) ) {
			return $result;
		}

		$link_id = 0;
		$pay_url = '';
		$status  = 'active';

		if ( is_array( $result ) ) {
			$link_id = isset( $result['link_id'] ) ? absint( $result['link_id'] ) : ( isset( $result['id'] ) ? absint( $result['id'] ) : 0 );
			$pay_url = isset( $result['pay_url'] ) ? (string) $result['pay_url'] : ( isset( $result['url'] ) ? (string) $result['url'] : '' );
			$status  = isset( $result['status'] ) ? (string) $result['status'] : 'active';
		} elseif ( is_object( $result ) ) {
			$link_id = absint( $result->link_id ?? $result->id ?? 0 );
			$pay_url = (string) ( $result->pay_url ?? $result->url ?? '' );
			$status  = (string) ( $result->status ?? 'active' );
		}

		if ( ! $link_id ) {
			return new WP_Error( 'dpl_create_failed', 'Payment link was not created.', [ 'status' => 400 ] );
		}

		return [
			'link_id' => $link_id,
			'pay_url' => $pay_url,
			'status'  => $status,
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
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is missing or its API does not match this bridge.', [ 'status' => 503 ] );
	}

	$vendor_id = get_current_user_id();
	$link_id   = absint( $request->get_param( 'id' ) );

	$result = dpl()->payment_link->cancel( $link_id, $vendor_id );
	if ( is_wp_error( $result ) ) {
		return $result;
	}

	return [ 'success' => true, 'message' => 'Payment link cancelled.' ];
}

/**
 * GET — list all orders minted for a specific payment link (ownership-verified).
 */
function zzmore_dpl_link_orders( WP_REST_Request $request ) {
	if ( ! zzmore_dpl_ready() ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links plugin is missing or its API does not match this bridge.', [ 'status' => 503 ] );
	}

	$vendor_id = get_current_user_id();
	$link_id   = absint( $request->get_param( 'id' ) );

	$link_repo = dpl()->payment_link;
	if ( ! is_object( $link_repo ) || ! method_exists( $link_repo, 'get_link' ) ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links order API is missing or does not match this bridge.', [ 'status' => 503 ] );
	}

	$link = $link_repo->get_link( $link_id );
	if ( ! $link || absint( $link['vendor_id'] ) !== $vendor_id ) {
		return new WP_Error( 'unauthorized', 'You do not own this payment link.', [ 'status' => 403 ] );
	}

	$order = dpl()->order ?? null;
	if ( ! is_object( $order ) || ! method_exists( $order, 'get_link_orders' ) ) {
		return new WP_Error( 'dpl_inactive', 'Dokan Payment Links order API is missing or does not match this bridge.', [ 'status' => 503 ] );
	}

	$per_page = absint( $request->get_param( 'per_page' ) );
	if ( ! $per_page ) {
		$per_page = 20;
	}
	$per_page = min( 50, max( 1, $per_page ) );
	$page     = max( 1, absint( $request->get_param( 'page' ) ) );

	return $order->get_link_orders( $link_id, $per_page, $page );
}
