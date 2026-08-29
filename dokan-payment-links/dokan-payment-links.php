<?php
/**
 * Plugin Name: Dokan Payment Links
 * Plugin URI:  https://midesigna.com/dokan-payment-links
 * Description: Let Dokan vendors generate shareable payment links where customers choose the amount to pay. Customers pay directly on WooCommerce's native pay-for-order page — no cart, no product page.
 * Version:     1.1.4
 * Author:      Temitayo
 * Author URI:  https://midesigna.com
 * License:     GPL-2.0+
 * Text Domain: dokan-payment-links
 * Domain Path: /languages
 * Requires at least: 6.0
 * Requires PHP: 7.4
 * Requires Plugins: woocommerce, dokan-lite
 */

// Prevent direct access.
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'DPL_VERSION', '1.1.4' );
define( 'DPL_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'DPL_PLUGIN_URL', plugin_dir_url( __FILE__ ) );
define( 'DPL_PLUGIN_BASENAME', plugin_basename( __FILE__ ) );

/**
 * Check plugin dependencies on activation.
 */
function dpl_activation_check() {
	// Ensure deactivate_plugins is available.
	if ( ! function_exists( 'deactivate_plugins' ) ) {
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
	}

	// Check WooCommerce.
	if ( ! class_exists( 'WooCommerce' ) ) {
		deactivate_plugins( DPL_PLUGIN_BASENAME );
		wp_die(
			esc_html__( 'Dokan Payment Links requires WooCommerce to be active. Please activate WooCommerce first.', 'dokan-payment-links' ),
			esc_html__( 'Plugin Activation Error', 'dokan-payment-links' ),
			array( 'back_link' => true )
		);
	}

	// Check Dokan (Lite or Pro) — use function_exists as it survives different load orders.
	if ( ! function_exists( 'dokan' ) && ! class_exists( 'WeDevs_Dokan' ) ) {
		deactivate_plugins( DPL_PLUGIN_BASENAME );
		wp_die(
			esc_html__( 'Dokan Payment Links requires Dokan (Lite or Pro) to be active. Please activate Dokan first.', 'dokan-payment-links' ),
			esc_html__( 'Plugin Activation Error', 'dokan-payment-links' ),
			array( 'back_link' => true )
		);
	}
}
register_activation_hook( __FILE__, 'dpl_activation_check' );

/**
 * Clean up on deactivation: unschedule cron event.
 */
function dpl_deactivation_cleanup() {
	wp_clear_scheduled_hook( 'dpl_expire_payment_links' );
}
register_deactivation_hook( __FILE__, 'dpl_deactivation_cleanup' );

/**
 * Show admin notice if dependencies are missing at runtime.
 */
function dpl_admin_notice_missing_deps() {
	if ( ! class_exists( 'WooCommerce' ) ) {
		echo '<div class="notice notice-error"><p>';
		echo wp_kses_post( __( '<strong>Dokan Payment Links:</strong> This plugin requires WooCommerce to be active. The plugin has been deactivated.', 'dokan-payment-links' ) );
		echo '</p></div>';
		return;
	}
	if ( ! function_exists( 'dokan' ) && ! class_exists( 'WeDevs_Dokan' ) ) {
		echo '<div class="notice notice-error"><p>';
		echo wp_kses_post( __( '<strong>Dokan Payment Links:</strong> This plugin requires Dokan (Lite or Pro) to be active. The plugin has been deactivated.', 'dokan-payment-links' ) );
		echo '</p></div>';
	}
}
add_action( 'admin_notices', 'dpl_admin_notice_missing_deps' );

/**
 * Bootstrap the plugin on plugins_loaded (priority 20).
 *
 * This runs after ALL active plugins have been loaded — which guarantees
 * WooCommerce and Dokan classes/functions are available regardless of
 * alphabetical load order. Previously, class_exists('WooCommerce') was
 * checked at file-include time, which returned false because 'dokan-payment-links'
 * loads before 'woocommerce' alphabetically. That caused an early return
 * before the menu registration code was ever reached.
 */
function dpl_bootstrap() {
	// Verify dependencies at runtime (all plugins now loaded).
	if ( ! class_exists( 'WooCommerce' ) ) {
		error_log( 'Dokan Payment Links: Bootstrap aborted — WooCommerce not available.' );
		return;
	}
	if ( ! function_exists( 'dokan' ) && ! class_exists( 'WeDevs_Dokan' ) ) {
		error_log( 'Dokan Payment Links: Bootstrap aborted — Dokan not available.' );
		return;
	}

	// Load class files.
	require_once DPL_PLUGIN_DIR . 'includes/functions-order-count.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-product.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-link.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-order.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-dashboard.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-ajax.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-cron.php';
	require_once DPL_PLUGIN_DIR . 'includes/class-plink-admin-settings.php';

	// Register admin menu hooks.
	add_action( 'admin_menu', 'dpl_register_admin_menu' );
	add_filter( 'plugin_action_links_' . DPL_PLUGIN_BASENAME, 'dpl_plugin_action_links' );

	error_log( 'Dokan Payment Links: Class files loaded, menu hooks registered.' );

	// Boot the main plugin class.
	Dokan_Payment_Links::instance();

	error_log( 'Dokan Payment Links: Bootstrap complete.' );
}
add_action( 'plugins_loaded', 'dpl_bootstrap', 20 );

/**
 * Main plugin class — boots all components.
 */
class Dokan_Payment_Links {

	/**
	 * @var Dokan_Payment_Links Singleton instance.
	 */
	private static $instance = null;

	/**
	 * @var DPL_Product
	 */
	public $product;

	/**
	 * @var DPL_Payment_Link
	 */
	public $payment_link;

	/**
	 * @var DPL_Order
	 */
	public $order;

	/**
	 * @var DPL_Dashboard
	 */
	public $dashboard;

	/**
	 * @var DPL_Ajax
	 */
	public $ajax;

	/**
	 * @var DPL_Cron
	 */
	public $cron;

	/**
	 * @var DPL_Admin_Settings
	 */
	public $admin_settings;

	/**
	 * Get singleton instance.
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	/**
	 * Constructor — boot all modules.
	 */
	private function __construct() {
		$this->product        = new DPL_Product();
		$this->payment_link   = new DPL_Payment_Link();
		$this->order          = new DPL_Order();
		$this->dashboard      = new DPL_Dashboard();
		$this->ajax           = new DPL_Ajax();
		$this->cron           = new DPL_Cron();
		$this->admin_settings = new DPL_Admin_Settings();

		$this->init_hooks();
	}

	/**
	 * Global hooks.
	 */
	private function init_hooks() {
		add_action( 'init', array( $this, 'load_textdomain' ) );
		add_action( 'template_redirect', array( $this, 'handle_expired_link_page' ) );
		add_action( 'wp_enqueue_scripts', array( $this, 'enqueue_assets' ) );

		// Inject vendor info + amount field before the pay-for-order form.
		add_action( 'before_woocommerce_pay_form', array( $this, 'render_vendor_info_row' ), 5 );

		// Inject guest customer fields / signed-in summary before the form.
		add_action( 'before_woocommerce_pay_form', array( $this, 'render_customer_fields' ), 6 );

		// Inject bank transfer details before the form.
		add_action( 'before_woocommerce_pay_form', array( $this, 'render_bank_details' ), 7 );

		// Inject trust badge after the pay button.
		add_action( 'woocommerce_pay_order_after_submit', array( $this, 'render_trust_row' ) );

		// Render customer info on the thank-you page for payment-link orders.
		add_action( 'woocommerce_thankyou', array( $this, 'render_thankyou_customer' ), 10, 1 );

		// Add body class for payment link orders.
		add_filter( 'body_class', array( $this, 'add_payment_link_body_class' ) );
	}

	/**
	 * Load plugin textdomain.
	 */
	public function load_textdomain() {
		load_plugin_textdomain( 'dokan-payment-links', false, dirname( DPL_PLUGIN_BASENAME ) . '/languages' );
	}

	/**
	 * Enqueue dashboard assets on the Dokan dashboard page, and payment-page
	 * CSS on the order-pay endpoint for payment-link orders.
	 */
	public function enqueue_assets() {
		// Dashboard assets.
		if ( dpl_is_dokan_dashboard() ) {
			wp_enqueue_style(
				'dpl-dashboard',
				DPL_PLUGIN_URL . 'assets/css/dashboard.css',
				array(),
				DPL_VERSION
			);

			wp_enqueue_script(
				'dpl-qrcode',
				DPL_PLUGIN_URL . 'assets/js/vendor/qrcode.min.js',
				array(),
				DPL_VERSION,
				true
			);

			wp_enqueue_script(
				'dpl-dashboard',
				DPL_PLUGIN_URL . 'assets/js/dashboard.js',
				array( 'jquery', 'dpl-qrcode' ),
				DPL_VERSION,
				true
			);

			// Gather vendor info for QR display.
			$vendor_id   = dpl_get_current_vendor_id();
			$vendor_phone = '';
			$vendor_store = '';
			if ( $vendor_id && function_exists( 'dokan_get_store_info' ) ) {
				$store_info   = dokan_get_store_info( $vendor_id );
				$vendor_phone = isset( $store_info['phone'] ) ? $store_info['phone'] : '';
				$vendor_store = isset( $store_info['store_name'] ) ? $store_info['store_name'] : '';
			}
			// Fallback to user display name if store name empty.
			if ( empty( $vendor_store ) && $vendor_id ) {
				$user = get_userdata( $vendor_id );
				$vendor_store = $user ? $user->display_name : '';
			}

			wp_localize_script(
				'dpl-dashboard',
				'DPL_Ajax',
				array(
					'ajax_url'  => admin_url( 'admin-ajax.php' ),
					'nonce'     => wp_create_nonce( 'dpl_dashboard_nonce' ),
					'copy_text' => __( 'Copy link', 'dokan-payment-links' ),
					'copied_text' => __( 'Copied!', 'dokan-payment-links' ),
					'copy_failed_text' => __( 'Copy failed', 'dokan-payment-links' ),
					'cancelled_text' => __( 'Cancelled', 'dokan-payment-links' ),
					'qr_download_text' => __( 'Download QR (PNG)', 'dokan-payment-links' ),
					'qr_print_text' => __( 'Print QR', 'dokan-payment-links' ),
					'cancel_confirm'   => __( 'Cancel this payment link?', 'dokan-payment-links' ),
					'error_generic'    => __( 'Something went wrong. Please try again.', 'dokan-payment-links' ),
					'vendor_phone'     => $vendor_phone,
					'vendor_store'     => $vendor_store,
					'scan_instruction' => __( 'Scan this QR code with your phone camera to pay', 'dokan-payment-links' ),
				)
			);
		}

		// Payment page CSS for payment-link orders.
		if ( $this->is_payment_link_order_pay() ) {
			wp_enqueue_style(
				'dpl-payment-page',
				DPL_PLUGIN_URL . 'assets/css/payment-page.css',
				array(),
				DPL_VERSION
			);

			// Load Google Fonts for the payment page.
			wp_enqueue_style(
				'dpl-payment-fonts',
				'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
				array(),
				null
			);

			// Amount entry JS for open-amount payment links.
			wp_enqueue_script(
				'dpl-payment-page',
				DPL_PLUGIN_URL . 'assets/js/payment-page.js',
				array( 'jquery' ),
				DPL_VERSION,
				true
			);

			wp_localize_script(
				'dpl-payment-page',
				'DPL_Payment',
				array(
					'currency_symbol'    => get_woocommerce_currency_symbol(),
					'currency_position'  => get_option( 'woocommerce_currency_pos', 'left' ),
					'decimal_separator'  => wc_get_price_decimal_separator(),
					'thousand_separator' => wc_get_price_thousand_separator(),
					'decimals'           => wc_get_price_decimals(),
					'min_amount_error'   => __( 'Please enter an amount greater than zero.', 'dokan-payment-links' ),
				)
			);
		}

		// Thank-you page styles for payment-link orders.
		if ( $this->is_payment_link_thankyou() ) {
			wp_enqueue_style(
				'dpl-payment-page',
				DPL_PLUGIN_URL . 'assets/css/payment-page.css',
				array(),
				DPL_VERSION
			);

			wp_enqueue_style(
				'dpl-payment-fonts',
				'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap',
				array(),
				null
			);
		}
	}

	/**
	 * Check if current request is the order-pay endpoint for a payment-link order.
	 *
	 * @return bool
	 */
	private function is_payment_link_order_pay() {
		global $wp;

		if ( ! isset( $wp->query_vars['order-pay'] ) ) {
			return false;
		}

		$order_id = absint( $wp->query_vars['order-pay'] );
		$order    = wc_get_order( $order_id );

		if ( ! $order ) {
			return false;
		}

		return 'dokan_payment_link' === $order->get_meta( '_payment_link_source' );
	}

	/**
	 * Check if the current request is the thank-you page for a payment-link order.
	 *
	 * @return bool
	 */
	private function is_payment_link_thankyou() {
		if ( ! function_exists( 'is_order_received_page' ) || ! is_order_received_page() ) {
			return false;
		}

		global $wp;
		$order_id = isset( $wp->query_vars['order-received'] ) ? absint( $wp->query_vars['order-received'] ) : 0;

		if ( ! $order_id ) {
			return false;
		}

		$order = wc_get_order( $order_id );

		return $order && 'dokan_payment_link' === $order->get_meta( '_payment_link_source' );
	}

	/**
	 * Render vendor info row above the payment form.
	 */
	public function render_vendor_info_row() {
		if ( ! $this->is_payment_link_order_pay() ) {
			return;
		}

		global $wp;
		$order_id  = absint( $wp->query_vars['order-pay'] );
		$order     = wc_get_order( $order_id );
		$vendor_id = $order ? absint( $order->get_meta( '_dokan_vendor_id' ) ) : 0;

		if ( ! $vendor_id ) {
			return;
		}

		$vendor       = get_userdata( $vendor_id );
		$store_name   = $vendor ? $vendor->display_name : __( 'Store', 'dokan-payment-links' );
		$store_url    = function_exists( 'dokan_get_store_url' ) ? dokan_get_store_url( $vendor_id ) : '';
		$initials     = strtoupper( mb_substr( $store_name, 0, 2 ) );
		$needs_shipping  = false;
		$delivery_note   = '';

		foreach ( $order->get_items() as $item ) {
			$product = $item->get_product();
			if ( $product && ! $product->get_virtual() ) {
				$needs_shipping = true;
			}
		}
		$delivery_note = $order->get_meta( '_payment_link_delivery_note' );
		$label         = $order->get_meta( '_payment_link_label' );

		?>
		<div class="dpl-vendor-row">
			<div class="dpl-vendor-avatar"><?php echo esc_html( $initials ); ?></div>
			<div style="min-width:0;">
				<div class="dpl-vendor-label"><?php esc_html_e( 'Payment requested by', 'dokan-payment-links' ); ?></div>
				<div class="dpl-vendor-name">
					<?php echo esc_html( $store_name ); ?>
				</div>
				<?php if ( $needs_shipping ) : ?>
					<span class="dpl-shipping-badge"><?php esc_html_e( 'Shipping required', 'dokan-payment-links' ); ?></span>
				<?php endif; ?>
			</div>
		</div>
		<?php
		if ( $label || $delivery_note ) : ?>
			<div style="padding:8px 26px 14px;font-size:13.5px;color:#7A6151;line-height:1.5;">
				<?php if ( $label ) : ?>
					<strong><?php echo esc_html( $label ); ?></strong>
				<?php endif; ?>
				<?php if ( $delivery_note ) : ?>
					<br><span style="font-size:12px;"><?php echo esc_html( $delivery_note ); ?></span>
				<?php endif; ?>
			</div>
		<?php endif; ?>

		<div class="dpl-amount-hero dpl-amount-entry">
			<label class="dpl-amount-eyebrow" for="dpl-custom-amount"><?php esc_html_e( 'Enter amount to pay', 'dokan-payment-links' ); ?></label>
			<div class="dpl-amount-input-wrap">
				<span class="dpl-amount-currency"><?php echo esc_html( get_woocommerce_currency_symbol( $order->get_currency() ) ); ?></span>
				<input type="number" id="dpl-custom-amount" name="dpl_custom_amount" form="order_review"
					min="0.01" step="0.01" inputmode="decimal" placeholder="0.00" required
					aria-label="<?php esc_attr_e( 'Amount to pay', 'dokan-payment-links' ); ?>">
			</div>
			<span class="dpl-amount-hint"><?php esc_html_e( 'Pay any amount you choose', 'dokan-payment-links' ); ?></span>
		</div>
		<?php
	}

	/**
	 * Render trust/security row after the place-order button.
	 */
	public function render_trust_row() {
		if ( ! $this->is_payment_link_order_pay() ) {
			return;
		}
		?>
		<div class="dpl-trust-row">
			<svg viewBox="0 0 24 24" fill="none" width="13" height="13"><rect x="4" y="10.5" width="16" height="9.5" rx="2" stroke="currentColor" stroke-width="2"/><path d="M8 10.5V7.5a4 4 0 018 0v3" stroke="currentColor" stroke-width="2"/></svg>
			<?php esc_html_e( 'Secured checkout — payment details are encrypted', 'dokan-payment-links' ); ?>
		</div>
		<?php
	}

	/**
	 * Render guest customer fields or a signed-in summary before the pay form.
	 */
	public function render_customer_fields() {
		if ( ! $this->is_payment_link_order_pay() ) {
			return;
		}

		global $wp;
		$order_id = absint( $wp->query_vars['order-pay'] );
		$order    = wc_get_order( $order_id );

		if ( ! $order ) {
			return;
		}

		if ( is_user_logged_in() || $order->get_user_id() ) {
			$this->render_signed_in_summary( $order );
		} else {
			$this->render_guest_fields( $order );
		}
	}

	/**
	 * Render bank transfer details for the payment link's vendor (fallback to
	 * the admin store BACS details when the vendor has none saved).
	 */
	public function render_bank_details() {
		if ( ! $this->is_payment_link_order_pay() ) {
			return;
		}

		global $wp;
		$order_id  = absint( $wp->query_vars['order-pay'] );
		$order     = wc_get_order( $order_id );
		$vendor_id = $order ? absint( $order->get_meta( '_dokan_vendor_id' ) ) : 0;

		$details = dpl_get_bank_details( $vendor_id );

		if ( empty( $details['rows'] ) ) {
			return;
		}
		?>
		<div class="dpl-bank-details">
			<div class="dpl-bank-details__heading"><?php esc_html_e( 'Bank transfer details', 'dokan-payment-links' ); ?></div>
			<div class="dpl-bank-details__card">
				<?php foreach ( $details['rows'] as $row ) : ?>
					<div class="dpl-bank-details__row">
						<span class="dpl-bank-details__label"><?php echo esc_html( $row['label'] ); ?></span>
						<span class="dpl-bank-details__value"><?php echo esc_html( $row['value'] ); ?></span>
					</div>
				<?php endforeach; ?>
			</div>
		</div>
		<?php
	}

	/**
	 * Render the required first-name / last-name / email inputs for guests.
	 *
	 * @param WC_Order $order
	 */
	private function render_guest_fields( $order ) {
		?>
		<div class="dpl-customer-fields">
			<div class="dpl-customer-fields__heading"><?php esc_html_e( 'Your details', 'dokan-payment-links' ); ?></div>
			<div class="dpl-customer-fields__row">
				<p class="form-row dpl-form-field">
					<label for="dpl-customer-first-name"><?php esc_html_e( 'First name', 'dokan-payment-links' ); ?> <span class="required">*</span></label>
					<input type="text" id="dpl-customer-first-name" name="dpl_customer_first_name" form="order_review"
						value="<?php echo esc_attr( $order->get_billing_first_name() ); ?>" required autocomplete="given-name"
						placeholder="<?php esc_attr_e( 'First name', 'dokan-payment-links' ); ?>">
				</p>
				<p class="form-row dpl-form-field">
					<label for="dpl-customer-last-name"><?php esc_html_e( 'Last name', 'dokan-payment-links' ); ?> <span class="required">*</span></label>
					<input type="text" id="dpl-customer-last-name" name="dpl_customer_last_name" form="order_review"
						value="<?php echo esc_attr( $order->get_billing_last_name() ); ?>" required autocomplete="family-name"
						placeholder="<?php esc_attr_e( 'Last name', 'dokan-payment-links' ); ?>">
				</p>
			</div>
			<p class="form-row dpl-form-field dpl-form-field--email">
				<label for="dpl-customer-email"><?php esc_html_e( 'Email address', 'dokan-payment-links' ); ?> <span class="required">*</span></label>
				<input type="email" id="dpl-customer-email" name="dpl_customer_email" form="order_review"
					value="<?php echo esc_attr( $order->get_billing_email() ); ?>" required autocomplete="email"
					placeholder="<?php esc_attr_e( 'you@example.com', 'dokan-payment-links' ); ?>">
			</p>
		</div>
		<?php
	}

	/**
	 * Render a prominent pre-filled summary for signed-in customers.
	 *
	 * @param WC_Order $order
	 */
	private function render_signed_in_summary( $order ) {
		$customer_id = $order->get_user_id();
		$user        = $customer_id ? get_userdata( $customer_id ) : wp_get_current_user();

		if ( ! $user || ! $user->ID ) {
			$this->render_guest_fields( $order );
			return;
		}

		$name     = dpl_get_user_full_name( $user );
		$username = $user->user_login;
		?>
		<div class="dpl-customer-summary">
			<div class="dpl-customer-summary__heading"><?php esc_html_e( 'Purchasing as', 'dokan-payment-links' ); ?></div>
			<div class="dpl-customer-summary__card">
				<div class="dpl-customer-summary__avatar"><?php echo esc_html( strtoupper( mb_substr( $name, 0, 2 ) ) ); ?></div>
				<div class="dpl-customer-summary__meta">
					<div class="dpl-customer-summary__name"><?php echo esc_html( $name ); ?></div>
					<div class="dpl-customer-summary__username">@<?php echo esc_html( $username ); ?></div>
				</div>
			</div>
		</div>
		<?php
	}

	/**
	 * Render customer details on the thank-you page for payment-link orders.
	 *
	 * @param int $order_id
	 */
	public function render_thankyou_customer( $order_id ) {
		$order = wc_get_order( $order_id );

		if ( ! $order || 'dokan_payment_link' !== $order->get_meta( '_payment_link_source' ) ) {
			return;
		}

		$name     = trim( $order->get_billing_first_name() . ' ' . $order->get_billing_last_name() );
		$email    = $order->get_billing_email();
		$username = $order->get_meta( '_payment_link_customer_username' );

		if ( ! $name && ! $email && ! $username ) {
			return;
		}
		?>
		<div class="dpl-thankyou-customer">
			<div class="dpl-thankyou-customer__heading"><?php esc_html_e( 'Order placed by', 'dokan-payment-links' ); ?></div>
			<div class="dpl-thankyou-customer__card">
				<?php if ( $name ) : ?>
					<div class="dpl-thankyou-customer__name"><?php echo esc_html( $name ); ?></div>
				<?php endif; ?>
				<?php if ( $username ) : ?>
					<div class="dpl-thankyou-customer__username">@<?php echo esc_html( $username ); ?></div>
				<?php endif; ?>
				<?php if ( $email ) : ?>
					<div class="dpl-thankyou-customer__email"><?php echo esc_html( $email ); ?></div>
				<?php endif; ?>
			</div>
		</div>
		<?php
	}

	/**
	 * Add body class for payment-link order-pay pages.
	 *
	 * @param array $classes
	 * @return array
	 */
	public function add_payment_link_body_class( $classes ) {
		if ( $this->is_payment_link_order_pay() ) {
			$classes[] = 'dpl-payment-link-page';
		}
		return $classes;
	}

	/**
	 * Intercept the order-pay endpoint to show an expired/cancelled message
	 * for payment-link orders that are no longer payable.
	 */
	public function handle_expired_link_page() {
		global $wp;

		if ( ! isset( $wp->query_vars['order-pay'] ) ) {
			return;
		}

		$order_id = absint( $wp->query_vars['order-pay'] );
		$order    = wc_get_order( $order_id );

		if ( ! $order ) {
			return;
		}

		// Only intercept payment-link orders.
		if ( 'dokan_payment_link' !== $order->get_meta( '_payment_link_source' ) ) {
			return;
		}

		// If order is already paid/completed, let WooCommerce handle the "already paid" message natively.
		if ( $order->is_paid() || 'completed' === $order->get_status() || 'processing' === $order->get_status() ) {
			return;
		}

		// If expired or cancelled, show message instead of payment form.
		if ( 'cancelled' === $order->get_status() ) {
			$message = $this->get_cancelled_message( $order );
			wp_die(
				wp_kses_post( $message ),
				esc_html__( 'Payment Link Unavailable', 'dokan-payment-links' ),
				array( 'response' => 200 )
			);
		}
	}

	/**
	 * Build the cancelled/expired message HTML.
	 */
	private function get_cancelled_message( $order ) {
		$expires_meta = $order->get_meta( '_payment_link_expires' );
		$now          = time();

		if ( $expires_meta && $expires_meta < $now ) {
			$title   = __( 'This payment link has expired.', 'dokan-payment-links' );
			$details = '';
		} else {
			$title   = __( 'This payment link is no longer available.', 'dokan-payment-links' );
			$details = '';
		}

		$label = $order->get_meta( '_payment_link_label' );

		ob_start();
		?>
		<div class="dpl-expired-notice" style="max-width:600px;margin:80px auto;padding:40px;text-align:center;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
			<div style="font-size:64px;margin-bottom:20px;">&#9203;</div>
			<h2 style="margin:0 0 10px;font-size:22px;color:#333;"><?php echo esc_html( $title ); ?></h2>
			<?php if ( $label ) : ?>
				<p style="color:#666;font-size:15px;"><?php echo esc_html( $label ); ?></p>
			<?php endif; ?>
			<?php if ( $details ) : ?>
				<p style="color:#888;font-size:14px;"><?php echo esc_html( $details ); ?></p>
			<?php endif; ?>
		</div>
		<?php
		return ob_get_clean();
	}
}

/**
 * Register the admin menu — called via admin_menu hook from dpl_bootstrap().
 *
 * Creates:
 *   Payment Links              ← top-level menu with dashicon
 *     └── Settings              ← submenu (same page, labelled "Settings")
 *   Plugins → Payment Links    ← redundant submenu for guaranteed visibility
 *   Plugins row → Settings     ← action link (registered separately)
 */
function dpl_register_admin_menu() {
	// Top-level menu.
	add_menu_page(
		__( 'Payment Links Settings', 'dokan-payment-links' ),
		__( 'Payment Links', 'dokan-payment-links' ),
		'manage_options',
		'dpl-settings',
		'dpl_render_settings_page',
		'dashicons-admin-links',
		56
	);

	// "Settings" submenu under the Payment Links top-level menu.
	add_submenu_page(
		'dpl-settings',
		__( 'Payment Links Settings', 'dokan-payment-links' ),
		__( 'Settings', 'dokan-payment-links' ),
		'manage_options',
		'dpl-settings',
		'dpl_render_settings_page'
	);

	// Redundant submenu under the core Plugins menu.
	add_submenu_page(
		'plugins.php',
		__( 'Payment Links Settings', 'dokan-payment-links' ),
		__( 'Payment Links', 'dokan-payment-links' ),
		'manage_options',
		'dpl-settings-plugins',
		'dpl_render_settings_page'
	);
}

/**
 * Add "Settings" link in the plugin's action row on the Plugins page.
 * Hooked via dpl_bootstrap().
 */
function dpl_plugin_action_links( $links ) {
	$settings_url = admin_url( 'admin.php?page=dpl-settings' );
	$settings_link = '<a href="' . esc_url( $settings_url ) . '">' . esc_html__( 'Settings', 'dokan-payment-links' ) . '</a>';
	array_unshift( $links, $settings_link );
	return $links;
}

/**
 * Render the settings page (delegates to the admin settings class).
 */
function dpl_render_settings_page() {
	if ( ! class_exists( 'Dokan_Payment_Links' ) ) {
		wp_die( esc_html__( 'Plugin not fully initialized. Please refresh the page.', 'dokan-payment-links' ) );
	}
	dpl()->admin_settings->render_settings_page();
}

/**
 * Helper: check if the current page is the Dokan dashboard.
 */
function dpl_is_dokan_dashboard() {
	if ( ! function_exists( 'dokan_get_option' ) ) {
		return false;
	}
	$page_id = dokan_get_option( 'dashboard', 'dokan_pages' );
	return is_page( $page_id );
}

/**
 * Helper: get vendor ID for the currently logged-in user.
 */
function dpl_get_current_vendor_id() {
	if ( ! is_user_logged_in() ) {
		return 0;
	}

	if ( ! function_exists( 'dokan_is_user_seller' ) || ! dokan_is_user_seller( get_current_user_id() ) ) {
		return 0;
	}

	return get_current_user_id();
}

/**
 * Helper: get a user's full name, falling back to display name.
 *
 * @param WP_User $user
 * @return string
 */
function dpl_get_user_full_name( $user ) {
	if ( ! $user || ! ( $user instanceof WP_User ) ) {
		return '';
	}

	$name = trim( $user->first_name . ' ' . $user->last_name );

	return $name ? $name : $user->display_name;
}

/**
 * Helper: get bank details to display on a payment-link checkout.
 *
 * Prefers the vendor's own bank details (Dokan profile) and falls back to the
 * admin store WooCommerce BACS accounts when the vendor has none saved.
 *
 * @param int $vendor_id
 * @return array { source: 'vendor'|'store'|'', rows: array[] }
 */
function dpl_get_bank_details( $vendor_id ) {
	if ( $vendor_id && function_exists( 'dokan_get_store_info' ) ) {
		$store_info = dokan_get_store_info( $vendor_id );
		$bank       = isset( $store_info['payment']['bank'] ) ? $store_info['payment']['bank'] : array();

		$vendor_rows = dpl_format_bank_rows(
			array(
				'ac_name'        => __( 'Account Name', 'dokan-payment-links' ),
				'ac_number'      => __( 'Account Number', 'dokan-payment-links' ),
				'bank_name'      => __( 'Bank Name', 'dokan-payment-links' ),
				'bank_addr'      => __( 'Bank Address', 'dokan-payment-links' ),
				'routing_number' => __( 'Routing Number', 'dokan-payment-links' ),
				'iban'           => __( 'IBAN', 'dokan-payment-links' ),
				'swift'          => __( 'SWIFT / BIC', 'dokan-payment-links' ),
			),
			$bank
		);

		if ( ! empty( $vendor_rows ) ) {
			return array( 'source' => 'vendor', 'rows' => $vendor_rows );
		}
	}

	// Fallback: admin store WooCommerce BACS bank details.
	$bacs = get_option( 'woocommerce_bacs_accounts' );

	if ( is_array( $bacs ) && ! empty( $bacs ) ) {
		$account = $bacs[0];

		$store_rows = dpl_format_bank_rows(
			array(
				'account_name'   => __( 'Account Name', 'dokan-payment-links' ),
				'account_number' => __( 'Account Number', 'dokan-payment-links' ),
				'bank_name'      => __( 'Bank Name', 'dokan-payment-links' ),
				'sort_code'      => __( 'Sort Code', 'dokan-payment-links' ),
				'iban'           => __( 'IBAN', 'dokan-payment-links' ),
				'bic'            => __( 'SWIFT / BIC', 'dokan-payment-links' ),
			),
			$account
		);

		if ( ! empty( $store_rows ) ) {
			return array( 'source' => 'store', 'rows' => $store_rows );
		}
	}

	return array( 'source' => '', 'rows' => array() );
}

/**
 * Helper: map a bank account array to labeled rows, dropping empty fields.
 *
 * @param array $field_labels Key => label map.
 * @param array $data         Raw bank account data.
 * @return array
 */
function dpl_format_bank_rows( $field_labels, $data ) {
	$rows = array();

	foreach ( $field_labels as $key => $label ) {
		if ( ! empty( $data[ $key ] ) ) {
			$rows[] = array(
				'label' => $label,
				'value' => $data[ $key ],
			);
		}
	}

	return $rows;
}

/**
 * Helper: get all plugin settings with defaults merged in.
 * Uses a static cache to avoid repeated get_option calls within a single request.
 *
 * @return array
 */
function dpl_get_setting_all() {
	static $settings = null;

	if ( null === $settings ) {
		$raw = get_option( 'dpl_settings', array() );

		$settings = wp_parse_args( $raw, array(
			'enabled'    => 'yes',
			'max_amount' => 0,
			'rate_limit' => 20,
			'tax_class'  => '',
		) );
	}

	return $settings;
}

/**
 * Helper: get a single plugin setting value.
 *
 * @param string $key     Setting key.
 * @param mixed  $default Default value.
 * @return mixed
 */
function dpl_get_setting( $key, $default = '' ) {
	$settings = dpl_get_setting_all();
	return isset( $settings[ $key ] ) ? $settings[ $key ] : $default;
}

/**
 * Helper: get the main plugin instance.
 */
function dpl() {
	return Dokan_Payment_Links::instance();
}

// Plugin is booted via dpl_bootstrap() on plugins_loaded (priority 20).
// See the dpl_bootstrap function above.
