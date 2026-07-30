<?php
/**
 * Bare checkout template for Flutter app WebView.
 *
 * This template strips everything except the WooCommerce checkout shortcode
 * (or order-received / pay-for-order) content. Styling is provided by
 * app-checkout.css, which matches the Flutter app's indigo/gold/coral palette.
 *
 * Used by: app-checkout-styling.php mu-plugin
 */

// Prevent direct access
if ( ! defined( 'ABSPATH' ) ) exit;

?><!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo( 'charset' ); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title><?php echo esc_html( get_bloginfo( 'name' ) ); ?> — Checkout</title>

    <?php wp_head(); ?>
</head>
<body <?php body_class( 'app-checkout' ); ?>>

    <!-- Main checkout content — no header, no footer -->
    <main class="app-checkout-main">
        <div class="app-checkout-container">

            <?php
            while ( have_posts() ) :
                the_post();
                the_content();
            endwhile;
            ?>

        </div>
    </main>

    <?php wp_footer(); ?>

</body>
</html>
