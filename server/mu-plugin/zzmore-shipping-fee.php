<?php
/**
 * Plugin Name: ZZmore Shipping Fee
 * Description: Exposes the vendor shipping fee for a product to the Flutter app.
 *              Reuses the checkout shipping logic from
 *              `tee_resolve_vendor_shipping_cost()` (installed as a Code
 *              Snippets snippet — see "shipping fee logic") so the cart shows
 *              the same fee that will be charged at checkout.
 *
 * Endpoint:
 *   GET /wp-json/app/v1/product-shipping-fee?product_id={id}&quantity={n}
 *
 * Install: Drop in wp-content/mu-plugins/zzmore-shipping-fee.php
 */

if ( ! defined( 'ABSPATH' ) ) exit;

add_action( 'rest_api_init', 'zzmore_register_shipping_fee_route' );

function zzmore_register_shipping_fee_route(): void {
    register_rest_route( 'app/v1', '/product-shipping-fee', [
        'methods'             => 'GET',
        'permission_callback' => '__return_true',
        'callback'            => 'zzmore_product_shipping_fee',
        'args'                => [
            'product_id' => [ 'required' => true, 'type' => 'integer' ],
            'quantity'   => [ 'required' => false, 'type' => 'integer', 'default' => 1 ],
            'country'    => [ 'required' => false, 'type' => 'string', 'default' => '' ],
            'state'      => [ 'required' => false, 'type' => 'string', 'default' => '' ],
            'postcode'   => [ 'required' => false, 'type' => 'string', 'default' => '' ],
        ],
    ] );
}

/**
 * GET /app/v1/product-shipping-fee
 *
 * Resolves the lowest vendor shipping cost for a product and returns it,
 * multiplied by the requested quantity. Returns `available: false` when no
 * shipping cost can be resolved (e.g. product has no vendor or the shipping
 * logic is not active), so the app can fall back gracefully.
 */
function zzmore_product_shipping_fee( WP_REST_Request $request ) {
    $product_id = (int) $request->get_param( 'product_id' );
    $quantity   = max( 1, (int) $request->get_param( 'quantity' ) );
    $product    = function_exists( 'wc_get_product' ) ? wc_get_product( $product_id ) : null;

    if ( ! $product || ! $product instanceof WC_Product ) {
        return new WP_Error(
            'not_found',
            __( 'Product not found.', 'zzmore' ),
            [ 'status' => 404 ]
        );
    }

    $destination = [
        'country'  => (string) $request->get_param( 'country' ),
        'state'    => (string) $request->get_param( 'state' ),
        'postcode' => (string) $request->get_param( 'postcode' ),
    ];

    $cost = null;
    if ( function_exists( 'tee_resolve_vendor_shipping_cost' ) ) {
        $cost = tee_resolve_vendor_shipping_cost( $product, $destination );
    }

    if ( $cost === null ) {
        return [
            'product_id' => $product_id,
            'cost'       => null,
            'available'  => false,
        ];
    }

    return [
        'product_id' => $product_id,
        'cost'       => (float) $cost,
        'total'      => (float) $cost * $quantity,
        'quantity'   => $quantity,
        'currency'   => function_exists( 'get_woocommerce_currency' ) ? get_woocommerce_currency() : '',
        'available'  => true,
    ];
}
