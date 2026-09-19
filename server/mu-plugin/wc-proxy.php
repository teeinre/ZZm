<?php
/**
 * Plugin Name: ZZmore WooCommerce API Proxy
 * Description: Server-side proxy for the WooCommerce REST API so the store's
 *              consumer key/secret never ships inside the Flutter app binary.
 *              The client calls /wp-json/wc-proxy/v1/<path> and this plugin
 *              forwards the request to the real WooCommerce endpoint using
 *              credentials that live ONLY on the server.
 *
 * Endpoints (all relative to /wp-json/wc-proxy/v1/):
 *   GET  wc/v3/products[...]                      (public catalog)
 *   GET  wc/v3/products/categories|tags|attributes (public catalog)
 *   GET  wc/v3/payment_gateways[...]               (public)
 *   GET  wc/v3/shipping_methods / shipping/zones   (public)
 *   GET  wc/v3/coupons?code=...                    (public coupon lookup)
 *   GET  wc/v3/settings/general                    (public)
 *   GET  wc-bookings/v1/products/slots             (public booking slots)
 *   POST wc/v3/customers                           (public self-registration)
 *   ...everything else (orders, customer records, vendor writes, media)
 *       requires a valid JWT (see determine_current_user below).
 *
 * SECRET CONFIGURATION (set ONE of these on the server — never commit them):
 *   1. Environment variables (recommended for Codemagic/VPS/container hosts):
 *        WOOCOMMERCE_CONSUMER_KEY=ck_...
 *        WOOCOMMERCE_CONSUMER_SECRET=cs_...
 *   2. wp-config.php constants:
 *        define( 'ZZMORE_WC_CONSUMER_KEY', 'ck_...' );
 *        define( 'ZZMORE_WC_CONSUMER_SECRET', 'cs_...' );
 *   3. WordPress options (via wp-cli or a one-off snippet):
 *        update_option( 'zzmore_wc_consumer_key', 'ck_...' );
 *        update_option( 'zzmore_wc_consumer_secret', 'cs_...' );
 *
 * Install: copy to wp-content/mu-plugins/wc-proxy.php
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// =========================================================================
// JWT Auth compatibility — make JWT-authenticated requests resolve to the
// correct WordPress user for THIS plugin's routes, even when LiteSpeed
// strips the Authorization header. Mirrors dokan-vendor-bridge.php.
// =========================================================================
add_filter( 'determine_current_user', function ( $user_id ) {
	if ( $user_id > 0 ) {
		return $user_id;
	}

	$jwt_token = '';

	$auth_header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
	if ( empty( $auth_header ) && function_exists( 'getallheaders' ) ) {
		$headers     = getallheaders();
		$auth_header = $headers['Authorization'] ?? $headers['authorization'] ?? '';
	}
	if ( $auth_header && preg_match( '/^Bearer\s+(.+)$/i', $auth_header, $m ) ) {
		$jwt_token = $m[1];
	}

	if ( empty( $jwt_token ) && ! empty( $_GET['token'] ) ) {
		$jwt_token = $_GET['token'];
	}

	if ( empty( $jwt_token ) ) {
		$custom_header = $_SERVER['HTTP_X_JWT_TOKEN'] ?? '';
		if ( ! empty( $custom_header ) ) {
			$jwt_token = $custom_header;
		} elseif ( function_exists( 'getallheaders' ) ) {
			$headers     = getallheaders();
			$jwt_token   = $headers['X-JWT-Token'] ?? $headers['x-jwt-token'] ?? '';
		}
	}

	if ( empty( $jwt_token ) ) {
		return $user_id;
	}

	if ( function_exists( 'jwt_auth_get_user_from_token' ) ) {
		try {
			$user = jwt_auth_get_user_from_token( $jwt_token );
			if ( $user && ! is_wp_error( $user ) && isset( $user->ID ) ) {
				wp_set_current_user( $user->ID );
				return $user->ID;
			}
		} catch ( \Exception $e ) {
			// invalid token — fall through
		}
	}

	if ( defined( 'JWT_AUTH_SECRET_KEY' ) ) {
		try {
			$decoded = null;
			if ( class_exists( '\Firebase\JWT\JWT' ) ) {
				$decoded = \Firebase\JWT\JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
			} elseif ( class_exists( 'JWT' ) ) {
				$decoded = \JWT::decode( $jwt_token, JWT_AUTH_SECRET_KEY, [ 'HS256' ] );
			}
			if ( $decoded && isset( $decoded->data->user->id ) ) {
				$user_id = (int) $decoded->data->user->id;
				wp_set_current_user( $user_id );
				return $user_id;
			}
		} catch ( \Exception $e ) {
			// invalid token — fall through
		}
	}

	return $user_id;
}, 20 );

// =========================================================================
// Credential resolution (server-side only).
// =========================================================================
function zzmore_wc_proxy_key() {
	$env = getenv( 'WOOCOMMERCE_CONSUMER_KEY' );
	if ( false !== $env && '' !== $env ) {
		return $env;
	}
	if ( defined( 'ZZMORE_WC_CONSUMER_KEY' ) ) {
		return ZZMORE_WC_CONSUMER_KEY;
	}
	$opt = get_option( 'zzmore_wc_consumer_key' );
	return $opt ? (string) $opt : '';
}

function zzmore_wc_proxy_secret() {
	$env = getenv( 'WOOCOMMERCE_CONSUMER_SECRET' );
	if ( false !== $env && '' !== $env ) {
		return $env;
	}
	if ( defined( 'ZZMORE_WC_CONSUMER_SECRET' ) ) {
		return ZZMORE_WC_CONSUMER_SECRET;
	}
	$opt = get_option( 'zzmore_wc_consumer_secret' );
	return $opt ? (string) $opt : '';
}

// =========================================================================
// Whitelist: public GET catalog endpoints (no auth required).
// =========================================================================
function zzmore_wc_proxy_is_public( $method, $path ) {
	// Guest self-registration (creates a WordPress user + WC customer).
	if ( 'POST' === $method && preg_match( '#^wc/v3/customers/?$#', $path ) ) {
		return true;
	}

	if ( 'GET' !== $method ) {
		return false;
	}

	$public_get = array(
		'#^wc/v3/products/?$#',
		'#^wc/v3/products/\d+/?$#',
		'#^wc/v3/products/\d+/variations/?$#',
		'#^wc/v3/products/categories/?$#',
		'#^wc/v3/products/tags/?$#',
		'#^wc/v3/products/shipping_classes/?$#',
		'#^wc/v3/products/attributes/?$#',
		'#^wc/v3/products/attributes/\d+/terms/?$#',
		'#^wc/v3/products/reviews/?$#',
		'#^wc/v3/payment_gateways/?$#',
		'#^wc/v3/payment_gateways/[a-z_]+/?$#',
		'#^wc/v3/shipping_methods/?$#',
		'#^wc/v3/shipping/zones/?$#',
		'#^wc/v3/shipping/zones/\d+/methods/?$#',
		'#^wc/v3/coupons/?$#',
		'#^wc/v3/settings/general/?$#',
		'#^wc-bookings/v1/products/slots/?$#',
	);

	foreach ( $public_get as $pattern ) {
		if ( preg_match( $pattern, $path ) ) {
			return true;
		}
	}

	return false;
}

// =========================================================================
// Object-level authorization for the sensitive (JWT-gated) endpoints.
// =========================================================================
function zzmore_wc_proxy_authorize( $method, $path, $query ) {
	$user_id  = get_current_user_id();
	$is_admin = current_user_can( 'manage_woocommerce' );
	$is_seller = function_exists( 'dokan_is_user_seller' ) && dokan_is_user_seller( $user_id );

	if ( $is_admin ) {
		return true;
	}

	// --- Customers: regular users may only touch their own record. ---
	if ( 0 === strpos( $path, 'wc/v3/customers' ) ) {
		if ( $is_seller ) {
			return true;
		}
		if ( preg_match( '#^wc/v3/customers/(\d+)$#', $path, $m ) ) {
			return (int) $m[1] === $user_id;
		}
		if ( 'GET' === $method && ! empty( $query['email'] ) ) {
			$u = get_userdata( $user_id );
			return $u && strtolower( $u->user_email ) === strtolower( (string) $query['email'] );
		}
		return false;
	}

	// --- Orders: customers only their own; sellers may list vendor orders. ---
	if ( 0 === strpos( $path, 'wc/v3/orders' ) ) {
		if ( $is_seller ) {
			return true;
		}
		if ( preg_match( '#^wc/v3/orders/(\d+)(/notes)?$#', $path, $m ) ) {
			$order = wc_get_order( (int) $m[1] );
			return $order && (int) $order->get_customer_id() === $user_id;
		}
		if ( 'GET' === $method ) {
			return ! empty( $query['customer'] ) && (int) $query['customer'] === $user_id;
		}
		// POST /orders (legacy direct order placement) — authenticated users only.
		return true;
	}

	// --- Everything else sensitive (product variations, coupons, shipping
	//     zone methods, review replies, media upload) is a vendor action. ---
	return $is_seller;
}

// =========================================================================
// Native media upload handler (avoids forwarding a raw multipart body).
// =========================================================================
function zzmore_wc_proxy_handle_media( WP_REST_Request $request ) {
	if ( ! current_user_can( 'upload_files' ) ) {
		return new WP_Error( 'zzmore_wc_proxy_forbidden', 'You do not have permission to upload files.', array( 'status' => 403 ) );
	}

	$files = $request->get_file_params();
	$file  = isset( $files['file'] ) ? $files['file'] : null;

	if ( ! $file || empty( $file['tmp_name'] ) ) {
		return new WP_Error( 'zzmore_wc_proxy_no_file', 'No file uploaded.', array( 'status' => 400 ) );
	}
	if ( ! empty( $file['error'] ) ) {
		return new WP_Error( 'zzmore_wc_proxy_upload_error', 'File upload failed.', array( 'status' => 400 ) );
	}

	require_once ABSPATH . 'wp-admin/includes/file.php';
	require_once ABSPATH . 'wp-admin/includes/media.php';
	require_once ABSPATH . 'wp-admin/includes/image.php';

	$upload = wp_handle_upload( $file, array( 'test_form' => false ) );
	if ( isset( $upload['error'] ) ) {
		return new WP_Error( 'zzmore_wc_proxy_upload_error', $upload['error'], array( 'status' => 400 ) );
	}

	$attachment_id = wp_insert_attachment(
		array(
			'post_mime_type' => $upload['type'],
			'post_title'     => preg_replace( '/\.[^.]+$/', '', sanitize_file_name( $file['name'] ) ),
			'post_status'    => 'inherit',
		),
		$upload['file']
	);

	if ( is_wp_error( $attachment_id ) ) {
		return new WP_Error( 'zzmore_wc_proxy_attachment_error', $attachment_id->get_error_message(), array( 'status' => 500 ) );
	}

	wp_update_attachment_metadata( $attachment_id, wp_generate_attachment_metadata( $attachment_id, $upload['file'] ) );

	$url = wp_get_attachment_url( $attachment_id );

	return array(
		'id'         => $attachment_id,
		'url'        => $url,
		'source_url' => $url,
	);
}

// =========================================================================
// Route registration + forwarding.
// =========================================================================
add_action( 'rest_api_init', function () {
	register_rest_route(
		'wc-proxy/v1',
		'/(?P<path>.*)',
		array(
			'methods'             => WP_REST_Server::ALLMETHODS,
			'callback'            => 'zzmore_wc_proxy_dispatch',
			'permission_callback' => '__return_true',
		)
	);
} );

function zzmore_wc_proxy_dispatch( WP_REST_Request $request ) {
	$path   = (string) $request['path'];
	$method = $request->get_method();
	$query  = $request->get_query_params();

	$key    = zzmore_wc_proxy_key();
	$secret = zzmore_wc_proxy_secret();

	if ( '' === $key || '' === $secret ) {
		return new WP_Error( 'zzmore_wc_proxy_unconfigured', 'WooCommerce API proxy is not configured on the server.', array( 'status' => 500 ) );
	}

	// Media upload is handled natively (never forwarded as raw multipart).
	if ( 'POST' === $method && 'wp/v2/media' === $path ) {
		if ( ! get_current_user_id() ) {
			return new WP_Error( 'zzmore_wc_proxy_unauthorized', 'Authentication required.', array( 'status' => 401 ) );
		}
		if ( ! current_user_can( 'manage_woocommerce' )
			&& ! ( function_exists( 'dokan_is_user_seller' ) && dokan_is_user_seller( get_current_user_id() ) ) ) {
			return new WP_Error( 'zzmore_wc_proxy_forbidden', 'You do not have permission to upload files.', array( 'status' => 403 ) );
		}
		return zzmore_wc_proxy_handle_media( $request );
	}

	if ( ! zzmore_wc_proxy_is_public( $method, $path ) ) {
		if ( ! get_current_user_id() ) {
			return new WP_Error( 'zzmore_wc_proxy_unauthorized', 'Authentication required for this endpoint.', array( 'status' => 401 ) );
		}
		if ( ! zzmore_wc_proxy_authorize( $method, $path, $query ) ) {
			return new WP_Error( 'zzmore_wc_proxy_forbidden', 'You do not have permission to access this resource.', array( 'status' => 403 ) );
		}
	}

	$upstream = rest_url( $path );
	if ( ! empty( $query ) ) {
		$upstream = add_query_arg( $query, $upstream );
	}

	$args = array(
		'method'  => $method,
		'timeout' => 30,
		'headers' => array(
			'Authorization' => 'Basic ' . base64_encode( $key . ':' . $secret ),
			'Accept'        => 'application/json',
		),
	);

	$content_type = $request->get_content_type();
	if ( ! empty( $content_type['value'] ) ) {
		$args['headers']['Content-Type'] = $content_type['value'];
	}

	if ( ! in_array( $method, array( 'GET', 'HEAD' ), true ) ) {
		$args['body'] = $request->get_body();
	}

	$response = wp_remote_request( $upstream, $args );

	if ( is_wp_error( $response ) ) {
		return new WP_Error( 'zzmore_wc_proxy_upstream_error', $response->get_error_message(), array( 'status' => 502 ) );
	}

	$status = (int) wp_remote_retrieve_response_code( $response );
	$body   = wp_remote_retrieve_body( $response );

	$result = new WP_REST_Response( json_decode( $body, true ), $status );

	foreach ( array( 'x-wp-total', 'x-wp-totalpages', 'link', 'x-robots-tag' ) as $header ) {
		$value = wp_remote_retrieve_header( $response, $header );
		if ( $value ) {
			$result->header( $header, $value );
		}
	}

	return $result;
}
