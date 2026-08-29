<?php
/**
 * Dokan dashboard integration — registers the "Payment Links" tab, query vars,
 * template loader, and the QR / orders / list views.
 */

// Prevent direct access.
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class DPL_Dashboard {

	/**
	 * Tab/endpoint slug.
	 */
	const ENDPOINT = 'payment-links';

	/**
	 * Sub-action query var for create/orders/qr views.
	 */
	const ACTION_VAR = 'plink-action';

	public function __construct() {
		add_filter( 'dokan_get_dashboard_nav', array( $this, 'add_dashboard_tab' ) );
		add_filter( 'dokan_query_var_filter', array( $this, 'add_query_var' ) );
		add_action( 'dokan_load_custom_template', array( $this, 'load_template' ) );

		// Flush rewrite rules on init if needed.
		add_action( 'init', array( $this, 'maybe_flush_rewrite_rules' ), 99 );
	}

	/**
	 * Add "Payment Links" to the Dokan dashboard nav.
	 */
	public function add_dashboard_tab( $nav ) {
		$nav[ self::ENDPOINT ] = array(
			'title'      => __( 'Payment Links', 'dokan-payment-links' ),
			'icon'       => '<i class="fas fa-link"></i>',
			'url'        => dokan_get_navigation_url( self::ENDPOINT ),
			'pos'        => 65,
			'permission' => 'dokandar',
		);
		return $nav;
	}

	/**
	 * Register the query var so Dokan knows about the custom endpoint.
	 */
	public function add_query_var( $query_vars ) {
		$query_vars[ self::ENDPOINT ] = self::ENDPOINT;
		return $query_vars;
	}

	/**
	 * Load the appropriate template when the payment-links endpoint is active.
	 */
	public function load_template( $query_vars ) {
		if ( ! isset( $query_vars[ self::ENDPOINT ] ) ) {
			return;
		}

		if ( ! current_user_can( 'dokandar' ) ) {
			dokan_get_template_part( 'global/no-permission' );
			return;
		}

		// Determine view: list, create, orders, or qr.
		$action = isset( $_GET[ self::ACTION_VAR ] ) ? sanitize_text_field( wp_unslash( $_GET[ self::ACTION_VAR ] ) ) : 'list';

		switch ( $action ) {
			case 'create':
				$this->render_create();
				break;
			case 'orders':
				$this->render_orders();
				break;
			case 'qr':
				$this->render_qr();
				break;
			default:
				$this->render_list();
				break;
		}
	}

	/**
	 * Render the list view.
	 */
	private function render_list() {
		$vendor_id = dpl_get_current_vendor_id();
		?>
		<div class="dpl-dashboard-wrap">
			<header class="dpl-header">
				<h2><?php esc_html_e( 'Payment Links', 'dokan-payment-links' ); ?></h2>
				<a href="<?php echo esc_url( add_query_arg( 'plink-action', 'create', dokan_get_navigation_url( self::ENDPOINT ) ) ); ?>" class="dpl-btn dpl-btn-primary">
					<?php esc_html_e( 'Create New Link', 'dokan-payment-links' ); ?>
				</a>
			</header>

			<?php if ( ! $vendor_id ) : ?>
				<p><?php esc_html_e( 'You must be a vendor to view this page.', 'dokan-payment-links' ); ?></p>
			<?php else : ?>
				<div id="dpl-links-container">
					<?php $this->render_links_list( $vendor_id ); ?>
				</div>
			<?php endif; ?>
		</div>
		<?php
	}

	/**
	 * Render the table/list of payment links.
	 */
	private function render_links_list( $vendor_id ) {
		$link   = dpl()->payment_link;
		$result = $link->get_vendor_links( $vendor_id, 20, 1 );
		$links  = $result['links'];

		if ( empty( $links ) ) {
			echo '<div class="dpl-empty-state">';
			echo '<p>' . esc_html__( 'No payment links yet. Create your first one!', 'dokan-payment-links' ) . '</p>';
			echo '</div>';
			return;
		}
		?>
		<div class="dpl-table-wrapper">
			<table class="dpl-table">
				<thead>
					<tr>
						<th><?php esc_html_e( 'Label', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Amount', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Orders', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Status', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Shipping?', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Created', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Expires', 'dokan-payment-links' ); ?></th>
						<th><?php esc_html_e( 'Actions', 'dokan-payment-links' ); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ( $links as $link ) : ?>
						<tr class="dpl-link-row" data-link-id="<?php echo absint( $link['id'] ); ?>" data-orders-url="<?php echo esc_url( $link['orders_url'] ); ?>">
							<td class="dpl-label" data-label="<?php esc_attr_e( 'Label', 'dokan-payment-links' ); ?>">
								<a href="<?php echo esc_url( $link['orders_url'] ); ?>" class="dpl-label-link"><?php echo esc_html( $link['label'] ); ?></a>
							</td>
							<td class="dpl-amount" data-label="<?php esc_attr_e( 'Amount', 'dokan-payment-links' ); ?>"><?php echo esc_html( $link['amount_formatted'] ); ?></td>
							<td data-label="<?php esc_attr_e( 'Orders', 'dokan-payment-links' ); ?>">
								<a href="<?php echo esc_url( $link['orders_url'] ); ?>" class="dpl-orders-link">
									<?php echo esc_html( sprintf( /* translators: %d number of orders */ _n( '%d order', '%d orders', $link['order_count'], 'dokan-payment-links' ), $link['order_count'] ) ); ?>
								</a>
							</td>
							<td data-label="<?php esc_attr_e( 'Status', 'dokan-payment-links' ); ?>">
								<span class="dpl-status dpl-status-<?php echo esc_attr( $link['status'] ); ?>">
									<?php echo esc_html( $this->get_status_label( $link ) ); ?>
								</span>
							</td>
							<td data-label="<?php esc_attr_e( 'Shipping', 'dokan-payment-links' ); ?>">
								<?php if ( $link['needs_shipping'] ) : ?>
									<span class="dpl-badge dpl-badge-shipping"><?php esc_html_e( 'Yes', 'dokan-payment-links' ); ?></span>
								<?php else : ?>
									<span class="dpl-badge dpl-badge-no-shipping"><?php esc_html_e( 'No', 'dokan-payment-links' ); ?></span>
								<?php endif; ?>
							</td>
							<td data-label="<?php esc_attr_e( 'Created', 'dokan-payment-links' ); ?>"><?php echo esc_html( $link['created_date'] ); ?></td>
							<td data-label="<?php esc_attr_e( 'Expires', 'dokan-payment-links' ); ?>">
								<?php if ( $link['expires'] ) : ?>
									<?php echo esc_html( $link['expires'] ); ?>
								<?php else : ?>
									&mdash;
								<?php endif; ?>
							</td>
							<td class="dpl-actions" data-label="<?php esc_attr_e( 'Actions', 'dokan-payment-links' ); ?>">
								<a href="<?php echo esc_url( $link['qr_url'] ); ?>" class="dpl-btn-sm" title="<?php esc_attr_e( 'View QR page', 'dokan-payment-links' ); ?>">
									<?php esc_html_e( 'QR Page', 'dokan-payment-links' ); ?>
								</a>
								<button type="button" class="dpl-btn-sm dpl-copy-link" data-url="<?php echo esc_url( $link['pay_url'] ); ?>" title="<?php esc_attr_e( 'Copy link', 'dokan-payment-links' ); ?>">
									<?php esc_html_e( 'Copy', 'dokan-payment-links' ); ?>
								</button>
								<?php if ( $link['is_cancellable'] ) : ?>
									<button type="button" class="dpl-btn-sm dpl-cancel-link" data-link-id="<?php echo absint( $link['id'] ); ?>" title="<?php esc_attr_e( 'Cancel link', 'dokan-payment-links' ); ?>">
										<?php esc_html_e( 'Cancel', 'dokan-payment-links' ); ?>
									</button>
								<?php endif; ?>
							</td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		</div>

		<?php if ( $result['total_pages'] > 1 ) : ?>
			<div class="dpl-pagination">
				<?php for ( $i = 1; $i <= $result['total_pages']; $i++ ) : ?>
					<button type="button" class="dpl-page-btn <?php echo 1 === $i ? 'active' : ''; ?>" data-page="<?php echo absint( $i ); ?>">
						<?php echo absint( $i ); ?>
					</button>
				<?php endfor; ?>
			</div>
		<?php endif; ?>
		<?php
	}

	/**
	 * Render the create view.
	 */
	private function render_create() {
		$vendor_id = dpl_get_current_vendor_id();
		?>
		<div class="dpl-dashboard-wrap">
			<header class="dpl-header">
				<h2><?php esc_html_e( 'Create Payment Link', 'dokan-payment-links' ); ?></h2>
				<a href="<?php echo esc_url( dokan_get_navigation_url( self::ENDPOINT ) ); ?>" class="dpl-btn dpl-btn-secondary">
					<?php esc_html_e( 'Back to List', 'dokan-payment-links' ); ?>
				</a>
			</header>

			<?php if ( ! $vendor_id ) : ?>
				<p><?php esc_html_e( 'You must be a seller to create payment links.', 'dokan-payment-links' ); ?></p>
			<?php else : ?>
				<form id="dpl-create-form" class="dpl-form">
					<div class="dpl-form-row">
						<label for="dpl-label">
							<?php esc_html_e( 'Description / Label', 'dokan-payment-links' ); ?>
							<span class="dpl-required">*</span>
						</label>
						<input type="text" id="dpl-label" name="label" required maxlength="255"
							placeholder="<?php esc_attr_e( 'e.g., Custom Logo Design, Handmade Necklace', 'dokan-payment-links' ); ?>">
						<p class="dpl-help"><?php esc_html_e( 'Shown to the customer on the payment page.', 'dokan-payment-links' ); ?></p>
					</div>

					<div class="dpl-form-row">
						<label class="dpl-checkbox-label">
							<input type="checkbox" id="dpl-needs-shipping" name="needs_shipping" value="1">
							<span><?php esc_html_e( 'Customer must provide a shipping address', 'dokan-payment-links' ); ?></span>
						</label>
						<p class="dpl-help"><?php esc_html_e( 'Check this if you are selling a physical product that needs to be shipped.', 'dokan-payment-links' ); ?></p>
					</div>

					<div class="dpl-form-row dpl-delivery-note-row" style="display:none;">
						<label for="dpl-delivery-note">
							<?php esc_html_e( 'Delivery Note (optional)', 'dokan-payment-links' ); ?>
						</label>
						<textarea id="dpl-delivery-note" name="delivery_note" rows="3" maxlength="500"
							placeholder="<?php esc_attr_e( 'e.g., Ships within 3-5 business days via FedEx.', 'dokan-payment-links' ); ?>"></textarea>
						<p class="dpl-help"><?php esc_html_e( 'A note about delivery that the customer will see.', 'dokan-payment-links' ); ?></p>
					</div>

					<div class="dpl-form-row">
						<label for="dpl-expiry">
							<?php esc_html_e( 'Link Expiry', 'dokan-payment-links' ); ?>
						</label>
						<select id="dpl-expiry" name="expiry">
							<option value="24h"><?php esc_html_e( '24 hours', 'dokan-payment-links' ); ?></option>
							<option value="3d"><?php esc_html_e( '3 days', 'dokan-payment-links' ); ?></option>
							<option value="7d" selected><?php esc_html_e( '7 days', 'dokan-payment-links' ); ?></option>
							<option value="none"><?php esc_html_e( 'No expiry', 'dokan-payment-links' ); ?></option>
						</select>
					</div>

					<div class="dpl-form-row">
						<button type="submit" class="dpl-btn dpl-btn-primary" id="dpl-submit-btn">
							<?php esc_html_e( 'Generate Payment Link', 'dokan-payment-links' ); ?>
						</button>
						<span class="dpl-spinner" style="display:none;"></span>
					</div>

					<div id="dpl-create-result" style="display:none;">
						<div class="dpl-result-card">
							<h3><?php esc_html_e( 'Payment Link Created!', 'dokan-payment-links' ); ?></h3>
							<div class="dpl-result-url">
								<input type="text" id="dpl-result-url-input" readonly>
								<button type="button" class="dpl-btn-sm" id="dpl-copy-result">
									<?php esc_html_e( 'Copy', 'dokan-payment-links' ); ?>
								</button>
							</div>
							<div class="dpl-result-qr">
								<canvas id="dpl-qr-canvas" width="220" height="220"></canvas>
								<br>
								<button type="button" class="dpl-btn-sm" id="dpl-download-qr">
									<?php esc_html_e( 'Download QR (PNG)', 'dokan-payment-links' ); ?>
								</button>
								<button type="button" class="dpl-btn-sm" id="dpl-print-qr" style="margin-left:6px;">
									<?php esc_html_e( 'Print QR', 'dokan-payment-links' ); ?>
								</button>
							</div>
						</div>
					</div>
				</form>
			<?php endif; ?>
		</div>
		<?php
	}

	/**
	 * Render the QR page for a single payment link.
	 */
	private function render_qr() {
		$vendor_id = dpl_get_current_vendor_id();
		$link_id   = isset( $_GET['plink-link'] ) ? absint( $_GET['plink-link'] ) : 0;
		$link      = dpl()->payment_link->get_link( $link_id );

		if ( ! $link || $link['vendor_id'] !== $vendor_id ) {
			echo '<div class="dpl-dashboard-wrap"><div class="dpl-empty-state"><p>' . esc_html__( 'Payment link not found.', 'dokan-payment-links' ) . '</p></div></div>';
			return;
		}

		$pay_url = dpl()->payment_link->get_pay_url( $link_id );
		$qr_src  = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&margin=8&data=' . rawurlencode( $pay_url );
		?>
		<div class="dpl-dashboard-wrap dpl-qr-page">
			<header class="dpl-header">
				<h2><?php esc_html_e( 'QR Payment Page', 'dokan-payment-links' ); ?></h2>
				<a href="<?php echo esc_url( dokan_get_navigation_url( self::ENDPOINT ) ); ?>" class="dpl-btn dpl-btn-secondary">
					<?php esc_html_e( 'Back to List', 'dokan-payment-links' ); ?>
				</a>
			</header>

			<div class="dpl-qr-card">
				<h3 class="dpl-qr-title"><?php echo esc_html( $link['label'] ); ?></h3>
				<div class="dpl-qr-amount"><?php echo esc_html( dpl()->payment_link->get_amount_label( $link ) ); ?></div>

				<div class="dpl-qr-code-box">
					<img src="<?php echo esc_url( $qr_src ); ?>" alt="<?php echo esc_attr( sprintf( /* translators: %s link label */ __( 'QR code for %s', 'dokan-payment-links' ), $link['label'] ) ); ?>" width="280" height="280">
				</div>

				<p class="dpl-qr-scan-instruction"><?php esc_html_e( 'Scan this QR code with your phone camera to pay', 'dokan-payment-links' ); ?></p>

				<div class="dpl-qr-direct-link">
					<label for="dpl-qr-pay-url"><?php esc_html_e( 'Direct checkout link', 'dokan-payment-links' ); ?></label>
					<div class="dpl-qr-direct-link-row">
						<input type="text" id="dpl-qr-pay-url" readonly value="<?php echo esc_attr( $pay_url ); ?>">
						<button type="button" class="dpl-btn-sm" id="dpl-qr-copy-url"><?php esc_html_e( 'Copy', 'dokan-payment-links' ); ?></button>
					</div>
				</div>

				<div class="dpl-qr-actions">
					<button type="button" class="dpl-btn dpl-btn-primary" id="dpl-qr-print"><?php esc_html_e( 'Print QR page', 'dokan-payment-links' ); ?></button>
					<a class="dpl-btn dpl-btn-secondary" href="https://wa.me/?text=<?php echo rawurlencode( $pay_url ); ?>" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Share on WhatsApp', 'dokan-payment-links' ); ?></a>
					<a class="dpl-btn dpl-btn-secondary" href="mailto:?subject=<?php echo rawurlencode( $link['label'] ); ?>&body=<?php echo rawurlencode( $pay_url ); ?>"><?php esc_html_e( 'Share via Email', 'dokan-payment-links' ); ?></a>
				</div>
			</div>
		</div>
		<?php
	}

	/**
	 * Render the orders view for a single payment link.
	 */
	private function render_orders() {
		$vendor_id = dpl_get_current_vendor_id();
		$link_id   = isset( $_GET['plink-link'] ) ? absint( $_GET['plink-link'] ) : 0;
		$link      = dpl()->payment_link->get_link( $link_id );

		if ( ! $link || $link['vendor_id'] !== $vendor_id ) {
			echo '<div class="dpl-dashboard-wrap"><div class="dpl-empty-state"><p>' . esc_html__( 'Payment link not found.', 'dokan-payment-links' ) . '</p></div></div>';
			return;
		}

		$result = dpl()->order->get_link_orders( $link_id, 20, 1 );
		?>
		<div class="dpl-dashboard-wrap">
			<header class="dpl-header">
				<h2><?php echo esc_html( sprintf( /* translators: %s link label */ __( 'Orders for "%s"', 'dokan-payment-links' ), $link['label'] ) ); ?></h2>
				<a href="<?php echo esc_url( dokan_get_navigation_url( self::ENDPOINT ) ); ?>" class="dpl-btn dpl-btn-secondary">
					<?php esc_html_e( 'Back to List', 'dokan-payment-links' ); ?>
				</a>
			</header>

			<p class="dpl-orders-count">
				<?php echo esc_html( sprintf( /* translators: %d number of orders */ _n( '%d order', '%d orders', $result['total'], 'dokan-payment-links' ), $result['total'] ) ); ?>
			</p>

			<?php if ( empty( $result['orders'] ) ) : ?>
				<div class="dpl-empty-state"><p><?php esc_html_e( 'No orders have been placed through this payment link yet.', 'dokan-payment-links' ); ?></p></div>
			<?php else : ?>
				<div class="dpl-table-wrapper">
					<table class="dpl-table">
						<thead>
							<tr>
								<th><?php esc_html_e( 'Order', 'dokan-payment-links' ); ?></th>
								<th><?php esc_html_e( 'Customer', 'dokan-payment-links' ); ?></th>
								<th><?php esc_html_e( 'Date', 'dokan-payment-links' ); ?></th>
								<th><?php esc_html_e( 'Total', 'dokan-payment-links' ); ?></th>
								<th><?php esc_html_e( 'Status', 'dokan-payment-links' ); ?></th>
							</tr>
						</thead>
						<tbody>
							<?php foreach ( $result['orders'] as $order ) : ?>
								<tr>
									<td class="dpl-order-id" data-label="<?php esc_attr_e( 'Order', 'dokan-payment-links' ); ?>">#<?php echo absint( $order['id'] ); ?></td>
									<td data-label="<?php esc_attr_e( 'Customer', 'dokan-payment-links' ); ?>">
									<div class="dpl-order-customer">
										<strong class="dpl-order-customer__name"><?php echo esc_html( $order['customer_name'] ? $order['customer_name'] : $order['customer'] ); ?></strong>
										<?php if ( ! empty( $order['customer_username'] ) ) : ?>
											<span class="dpl-order-customer__username">@<?php echo esc_html( $order['customer_username'] ); ?></span>
										<?php endif; ?>
										<?php if ( ! empty( $order['customer_email'] ) ) : ?>
											<span class="dpl-order-customer__email"><?php echo esc_html( $order['customer_email'] ); ?></span>
										<?php endif; ?>
									</div>
								</td>
									<td data-label="<?php esc_attr_e( 'Date', 'dokan-payment-links' ); ?>"><?php echo esc_html( $order['date'] ); ?></td>
									<td data-label="<?php esc_attr_e( 'Total', 'dokan-payment-links' ); ?>"><?php echo wp_kses_post( wc_price( $order['total'], array( 'currency' => $order['currency'] ) ) ); ?></td>
									<td data-label="<?php esc_attr_e( 'Status', 'dokan-payment-links' ); ?>">
										<span class="dpl-status dpl-status-<?php echo esc_attr( $order['status'] ); ?>"><?php echo esc_html( $this->get_order_status_label( $order['status'] ) ); ?></span>
									</td>
								</tr>
							<?php endforeach; ?>
						</tbody>
					</table>
				</div>
			<?php endif; ?>
		</div>
		<?php
	}

	/**
	 * Get a human-readable status label for a payment link.
	 */
	private function get_status_label( $link ) {
		switch ( $link['status'] ) {
			case 'active':
				return __( 'Active', 'dokan-payment-links' );
			case 'expired':
				return __( 'Expired', 'dokan-payment-links' );
			case 'cancelled':
				return __( 'Cancelled', 'dokan-payment-links' );
			default:
				return ucfirst( $link['status'] );
		}
	}

	/**
	 * Get a human-readable status label for an order.
	 */
	private function get_order_status_label( $status ) {
		$labels = wc_get_order_statuses();

		return isset( $labels[ 'wc-' . $status ] ) ? $labels[ 'wc-' . $status ] : ucfirst( $status );
	}

	/**
	 * Flush rewrite rules once after the reusable-link rewrite rule is added.
	 */
	public function maybe_flush_rewrite_rules() {
		if ( get_option( 'dpl_rewrite_flushed_1_1_0' ) ) {
			return;
		}
		flush_rewrite_rules();
		update_option( 'dpl_rewrite_flushed_1_1_0', true );
	}
}
