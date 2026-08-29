=== Dokan Payment Links ===
Contributors: temitayo
Tags: dokan, woocommerce, payment, vendor, marketplace
Requires at least: 6.0
Tested up to: 6.7
Stable tag: 1.1.4
Requires PHP: 7.4
License: GPL-2.0+
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Let Dokan vendors generate shareable payment links where customers choose the amount to pay.

== Description ==

Dokan Payment Links lets your marketplace vendors create shareable payment links where the customer decides the amount at checkout. Customers pay directly on WooCommerce's native pay-for-order page — no cart, no product page, nothing to click through.

The vendor decides per-link whether to collect a shipping address (physical goods) or billing only (services/digital products). Everything uses WooCommerce and Dokan's built-in behavior — nothing custom on the checkout side.

== Features ==

* One-click payment link generation from the vendor dashboard
* Per-link toggle: "Requires shipping address?" — WooCommerce shows/hides shipping fields automatically
* Native WooCommerce pay-for-order page — no custom checkout, no cart step
* QR code generation (client-side, no external API dependency) and PNG download
* Optional link expiry (24h / 3 days / 7 days / never)
* Rate limiting per vendor
* All sales tracked through Dokan's existing commission/payout system
* Zero custom database tables — everything uses native WooCommerce objects
* Performance optimized: transient caching for placeholder products, single-save order flow, batched cron processing

== Requirements ==

* WordPress 6.0+
* PHP 7.4+
* WooCommerce 4.0+
* Dokan Lite or Dokan Pro

== Installation ==

1. Upload the `dokan-payment-links` folder to `/wp-content/plugins/`
2. Activate "Dokan Payment Links" from the Plugins menu
3. Vendors will now see a "Payment Links" tab in their Dokan dashboard

== Settings ==

The settings page is accessible from:
1. The **Payment Links** menu in the admin sidebar, or
2. **Plugins → Payment Links**, or
3. The **Settings** link next to the plugin on the Plugins page.
* Enable/disable the feature
* Maximum payment amount (limits how much a customer can pay)
* Rate limit per vendor (links per hour)
* Tax class for payment link line items

== Frequently Asked Questions ==

= How are commissions tracked? =

Payment link orders are standard WooCommerce orders attributed to the vendor via Dokan's `_dokan_vendor_id` meta. Commissions flow through Dokan's existing system — the plugin fires `dokan_checkout_update_order_meta` and calls `dokan_sync_insert_order()` to ensure tables are updated.

= Can I use any payment gateway? =

Yes. The payment page lists whatever gateways are enabled on your store.

= What happens when a link expires? =

A daily cron job cancels unpaid expired links in batches of 100. Visitors see an "expired" message instead of the payment form.

= What happens when I deactivate the plugin? =

The cron job is cleaned up. Existing payment link orders remain intact as normal WooCommerce orders.

== Author ==

Created by Temitayo — [Midesigna.com](https://midesigna.com)

== Changelog ==

= 1.1.4 =
* **Mobile order-list layout fix:** Prevented customer/guest names and the "Customer" column label from splitting mid-word, and kept order numbers on a single line in the responsive card view. Version bump to 1.1.4.

= 1.1.3 =
* **Customer-defined amounts:** Vendors no longer enter an amount when creating a link. The customer enters any amount to pay on the checkout page, with live order-total updates and validation.
* Payment links are now open-amount; the maximum payment amount setting limits customer-entered amounts instead of vendor requests.
* Version bump to 1.1.3.

= 1.1.2 =
* Removed the customer email field from the payment-link creation form (obsolete now that links support unlimited customers).
* Redesigned the checkout payment page with a prominent amount header and clearer visual hierarchy.
* Added accessible inline validation styling for billing/shipping fields.
* Version bump to 1.1.2.

= 1.1.1 =
* **Fix repeated-purchase block:** The hidden placeholder product used for payment-link orders was created as private with no price, making WooCommerce's `is_purchasable()` return false and showing "this product cannot be purchased" after the first order. Added a `woocommerce_is_purchasable` filter so placeholder products are always purchasable, allowing unlimited reuse of a link with a fresh order each time.
* Version bump to 1.1.1.

= 1.1.0 =
* **Unlimited reusable links:** Payment links are now persistent records (hidden custom post type) independent of orders. Any customer can pay through the same link as many times as needed; every payment mints a brand-new order with a unique order ID.
* **Per-link order history:** Each order is associated with its originating link. Vendors can click a link's order count to view every individual order (date, customer, total, status) — including orders on cancelled links.
* **Cancellation-only restriction:** Cancelling a link blocks only future transactions; all previously processed orders remain visible in the vendor's history.
* **Dedicated QR payment page:** Every link on the dashboard is now clickable and opens a dedicated QR page showing a server-generated, scannable QR code plus a visible direct checkout URL, with copy, print, WhatsApp and email share actions.
* **Copy link fix:** Copy-to-clipboard now falls back to a hidden-textarea method with explicit success/failure feedback across browsers.
* Version bump to 1.1.0.

= 1.0.10 =
* **QR code dual-fallback (production-grade):** New `generateQR()` helper tries in-browser QRCode.js first (fast, offline-capable), then falls back to api.qrserver.com cloud API via `<img>` tag. Uses error-correction level L for maximum URL capacity. Guarantees QR code generation 100% of the time for all valid payment URLs. Applied to both modal QR (list rows) and create-result QR.
* **Payment page complete redesign:** Full CSS rewrite (925 lines) matching `paymentpagedesig.html` reference design with brand color #e67e14. Card-based layout with 24px border-radius, layered shadow, woven orange top band, and card entrance animation.
* **Theme nuke:** 30+ CSS selectors hide ALL theme headers, footers, sidebars, nav, page builders (Astra, Elementor, Divi, Beaver Builder, block themes). Content area forced to 480px max-width centered card.
* **Vendor info row:** Avatar with orange gradient, store name, "Payment requested by" label, shipping badge — styled per reference design.
* **Order review table:** Rounded card-style table with hover states, dashed separators, orange-tinted total row.
* **Payment methods accordion:** Bordered gateway list with radio buttons, active-state highlight (#FFF6EC), dashed inner separators.
* **Billing/shipping fields:** 15px inputs with 12px border-radius, orange focus rings (4px glow), Select2 overrides, dashed section dividers.
* **Pay button:** Orange gradient (#e67e14 -> #c56008), lock SVG icon via ::before pseudo-element, 12px layered box-shadow, hover lift animation, disabled state.
* **Trust row:** Lock SVG + "Secured checkout" text, centered below button.
* **Stripe Elements:** Matching input border-radius and focus ring styling.
* **Full responsive design:** 4 breakpoints (768px tablet, 480px phone, 360px extra-small) with proportional padding/font reductions. Button uses calc-based width with side margins to prevent overflow.
* **Cross-browser:** Firefox spin-button removal, Safari 16px input zoom fix, IE11/Edge shadow fallbacks, print styles with color-adjust.
* * Version bump to 1.0.10.

= 1.0.9 =
* **Content shifted right:** Dashboard wrapper moved from centered (`margin: 0 auto`) to right-shifted (`margin-left: 310px`) to completely clear the Dokan sidebar. No possible overlap regardless of theme sidebar width.
* **QR modal enriched:** Now displays item label, price, store name, and vendor phone number above the QR code. Info section styled as a bordered card with dotted separators.
* **Scan instruction:** Prominent instructional text ("Scan this QR code with your phone camera to pay") shown below the QR code in both the modal and the print view.
* **Print layout enhanced:** Print window now includes item name (bold), price (orange, large), store name, phone number, QR code, and scan instruction — a complete printable payment slip.
* **Vendor phone integration:** Vendor phone number pulled from Dokan store settings (`dokan_get_store_info`) and passed to the dashboard JS for QR display.
* **Escape key:** Pressing Escape closes the QR modal.
* Version bump to 1.0.9.

= 1.0.8 =
* **QR code reliability:** Added defensive `typeof QRCode` checks and try/catch guards in both `showCreateResult()` and `bindQRButtons()`. Modal lazily initializes so click handlers are always registered even if DPL_Ajax isn't ready. Added Escape-key close and `e.stopPropagation()` for robust modal behavior. Error messages render as canvas text when QR library is missing.
* **Dashboard overlay fix (aggressive):** `isolation: isolate` stacking context on `.dokan-dashboard-content` prevents theme sidebar from ever overlaying content. Sidebar forced to `z-index: 1 !important` with `float: none !important; position: relative !important`. Content area promoted with `z-index: 10` and clearfix.
* **Centering improvements:** `.dpl-dashboard-wrap` has `clear: both`, `width: 100%`, `box-sizing: border-box`. Header uses `flex-wrap: wrap` with gap. Both list table and create form are properly centered via auto margins.
* **Mobile data-labels:** AJAX-rendered table rows now include `data-label` attributes for card-style responsive layout matching server-rendered rows.
* Version bump to 1.0.8.

= 1.0.7 =
* **QR code dashboard integration:** QR buttons on each payment link row open a centered modal. Download QR (PNG) and Print QR actions available in modal. Print opens a clean window with auto-print trigger.
* **AJAX spinner fix:** 15-second defensive timeout forces button restore if AJAX chain hangs. Pre-submission force-reset prevents stuck spinners from prior failed submissions.
* **Payment page redesign:** Full CSS rewrite matching `paymentpagedesig.html` reference design. Brand color #e67e14 applied throughout — gradient buttons, cream background, card shadows, woven-pattern top band, accordion-style payment methods, Stripe styling.
* **Dashboard CSS rewrite:** Complete visual overhaul with centered max-width layout, brand-colored buttons, card-style table with hover states, rounded form inputs with focus rings, status badges, QR modal with backdrop blur.
* **Dashboard PHP:** Added `data-label` attributes to all `<td>` elements for responsive mobile card layout.

= 1.0.6 =
* **Modern payment page design:** Styled WooCommerce's order-pay page with a premium card-based layout using the brand color #e67e14. Cream gradient background, rounded form inputs, gradient pay button, and hidden theme headers/footers for a clean standalone payment experience.
* Vendor info row injected above the payment form (store name, avatar initials, shipping badge, item label, and delivery note).
* Trust/security badge shown below the Place Order button.
* **Dashboard fix:** Dokan sidebar overlay resolved — content area given proper z-index positioning. Create form centered with max-width for better layout.
* **QR Code print feature:** New "Print QR" button in both the QR modal and create-result card. Opens a print-friendly window with the QR code, link label, and auto-triggers browser print dialog — vendors can print and physically post QR codes.
* Google Fonts (Plus Jakarta Sans) loaded on the payment page for modern typography.

= 1.0.5 =
* **Fixed critical bug:** Admin menu never appearing. Root cause — `class_exists('WooCommerce')` check at file-include time failed because `dokan-payment-links` loads before `woocommerce` alphabetically. Entire boot sequence (class loading, menu registration, plugin instantiation) moved to `plugins_loaded` hook (priority 20), which fires after all plugins are guaranteed loaded.
* Menu structure improved: "Payment Links" top-level menu → "Settings" submenu + "Plugins → Payment Links" redundant submenu + "Settings" action link in Plugins row.
* Added `error_log()` debug tracing throughout bootstrap to aid future diagnostics.
* Added class-existence guard in `dpl_render_settings_page()`.

= 1.0.4 =
* Triple menu approach: top-level menu (add_menu_page) + Plugins submenu (add_submenu_page under plugins.php) + "Settings" action link in Plugins row (plugin_action_links filter). Guarantees settings visibility regardless of admin menu quirks.

= 1.0.3 =
* Admin menu completely rewritten — uses standalone `add_menu_page()` with `dashicons-admin-links` icon. No parent slug dependency, no class method callbacks. Menu appears as "Payment Links" in the admin sidebar at position 56.

= 1.0.2 =
* Admin settings page moved to Settings → Payment Links (reliable core menu — no WooCommerce parent slug dependency).
* Menu registration moved from DPL_Admin_Settings class to main plugin file.

= 1.0.1 =
* Fixed admin settings page — registered as a WordPress submenu under WooCommerce → Payment Links (no longer relies on WC_Settings_Page).
* Fixed `find_existing()` placeholder product query — changed from `limit=1` to `limit=-1` with transient caching, preventing wrong product type returns.
* Fixed race condition in placeholder product creation with transient locking.
* Fixed `deactivate_plugins()` availability on activation by requiring `wp-admin/includes/plugin.php`.
* Fixed QR modal close button CSS positioning (added `position: relative` to parent).
* Fixed `wc_price()` HTML leaking into exception messages with `wp_strip_all_tags()`.
* Fixed QR download `toDataURL()` crash with try/catch guards.
* Fixed redundant `set_transient` dead code in `increment_rate_limit()`.
* Optimized order creation to single-save (meta set before `calculate_totals()`).
* Added `_dokan_vendor_id` line item meta for commission calculation robustness.
* Added deactivation cron cleanup hook.
* Added `dpl_get_setting_all()` helper with defaults merging.
* Bumped version to 1.0.1.

= 1.0.0 =
* Initial release.
* Support for shipping/no-shipping payment links.
* QR code generation and PNG download.
* Rate limiting and link expiry.
* Performance optimizations: transient caching, single-save order flow, batched cron.
