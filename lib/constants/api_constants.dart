class ApiConstants {
  static const String baseUrl = 'https://zzmore.store/wp-json';
  static const String wpApiBase = '$baseUrl/wp/v2';
  static const String wcApiBase = '$baseUrl/wc/v3';
  static const String authEndpoint = '$baseUrl/jwt-auth/v1/token';
  static const String tokenValidateEndpoint = '$baseUrl/jwt-auth/v1/token/validate';
  static const String productsEndpoint = '$wcApiBase/products';
  static const String categoriesEndpoint = '$wcApiBase/products/categories';
  static const String ordersEndpoint = '$wcApiBase/orders';
  static const String customersEndpoint = '$wcApiBase/customers';

  // Dokan REST API endpoints
  static const String dokanV1Base = '$baseUrl/dokan/v1';
  static const String dokanV2Base = '$baseUrl/dokan/v2';
  static const String dokanStoresEndpoint = '$dokanV1Base/stores';
  static const String dokanOrdersEndpoint = '$dokanV1Base/orders';
  static const String dokanWithdrawEndpoint = '$dokanV1Base/withdraw';
  static const String dokanReportsEndpoint = '$dokanV1Base/reports/summary';
  static const String dokanReviewsEndpoint = '$dokanV1Base/reviews';
  static const String dokanCouponsEndpoint = '$dokanV1Base/coupons';
  static const String dokanSettingsEndpoint = '$dokanV1Base/settings';
  static const String dokanBalanceEndpoint = '$dokanV1Base/reports/summary';  // balance is in reports/summary as seller_balance
  static const String dokanAnnouncementsEndpoint = '$dokanV1Base/announcement';
  static const String couponsEndpoint = '$wcApiBase/coupons';

  // WooCommerce Store API (block-based checkout — enables Dokan multi-vendor shipping)
  static const String storeApiBase = '$baseUrl/wc/store/v1';
  static const String storeCartEndpoint = '$storeApiBase/cart';
  static const String storeCartAddItemEndpoint = '$storeApiBase/cart/add-item';
  static const String storeCartUpdateItemEndpoint = '$storeApiBase/cart/update-item';
  static const String storeCartRemoveItemEndpoint = '$storeApiBase/cart/remove-item';
  static const String storeCartUpdateCustomerEndpoint = '$storeApiBase/cart/update-customer';
  static const String storeCartSelectShippingRateEndpoint = '$storeApiBase/cart/select-shipping-rate';
  static const String storeCartApplyCouponEndpoint = '$storeApiBase/cart/apply-coupon';
  static const String storeCartRemoveCouponEndpoint = '$storeApiBase/cart/remove-coupon';
  static const String storeCheckoutEndpoint = '$storeApiBase/checkout';

  // WooCommerce Analytics (used by Dokan vendor dashboard — scoped to authenticated vendor)
  static const String analyticsBase = '$baseUrl/wc-analytics';
  static const String analyticsRevenueStats = '$analyticsBase/reports/revenue/stats';
  static const String analyticsOrdersStats = '$analyticsBase/reports/orders/stats';
  static const String analyticsProductsStats = '$analyticsBase/reports/products/stats';

  // WooCommerce shipping zones
  static const String shippingZonesEndpoint = '$wcApiBase/shipping/zones';
  static const String shippingMethodsEndpoint = '$wcApiBase/shipping_methods';

  // Live Streams (Dokan Live Stream module + App bridge)
  static const String dokanLiveStreamsEndpoint = '$dokanV1Base/livestreams';
  static const String dokanLiveStreamsAltEndpoint = '$dokanV1Base/live-streams';
  static const String appLivestreamsEndpoint = '$appV1Base/livestreams';

  // Push Notifications (device token registration)
  static const String registerDeviceEndpoint = '$appV1Base/register-device';
  static const String unregisterDeviceEndpoint = '$appV1Base/unregister-device';

  // Woo Report Plugin (custom vendor reporting)
  static const String wooReportBase = '$baseUrl/woo-report/v1';
  static const String wooReportVendorStats = '$wooReportBase/vendor-stats';
  static const String wooReportDashboard = '$wooReportBase/dashboard';

  // Vendor API bypass (vendor-api.php — bypasses REST blockage)
  // Must point to the WordPress root, NOT under /wp-json/
  static const String vendorApiBase = 'https://zzmore.store/vendor-api.php';

  // App Bridge (mu-plugin: zzmore-app-checkout.php)
  static const String appV1Base = '$baseUrl/app/v1';

  // ── Product / Vendor Exclusion ──
  /// Vendor store names/slugs whose products should be hidden from customer-facing views.
  static const List<String> excludedVendorNames = [
    'zzmore-wholesale',
  ];

  /// Vendor IDs whose content (profile + products) should be completely hidden
  /// from the app. Prefer ID-based filtering for deterministic behaviour.
  static const List<int> excludedVendorIds = [
    126,
  ];

  /// Returns `true` if a vendor with the given [id] or [name] is in the
  /// exclusion lists and should be suppressed from all customer-facing UI.
  static bool isVendorExcluded({int? id, String? name}) {
    if (id != null && excludedVendorIds.contains(id)) return true;
    if (name != null && name.isNotEmpty) {
      final lower = name.toLowerCase();
      if (excludedVendorNames.any((e) => lower.contains(e.toLowerCase()))) {
        return true;
      }
    }
    return false;
  }
  static const String appPrepareCheckoutEndpoint = '$appV1Base/prepare-checkout';
  static const String appEnterCheckoutEndpoint = '$appV1Base/enter-checkout';
  static const String appOrderEndpoint = '$appV1Base/order'; // append /{id}?key=xxx

  // Password reset (mu-plugin: zzmore-password-reset.php)
  static const String forgotPasswordEndpoint = '$appV1Base/forgot-password';
  static const String resetPasswordEndpoint = '$appV1Base/reset-password';

  // Shipping fee (mu-plugin: zzmore-shipping-fee.php)
  static const String productShippingFeeEndpoint = '$appV1Base/product-shipping-fee';

  // WooCommerce API credentials
  static const String consumerKey = 'ck_537f3489368abb26297c733faf5dafb8b659a411';
  static const String consumerSecret = 'cs_e8b0de9db4df97bf5797e13aa8c4dd80a45d96d5';

  static const int defaultPerPage = 10;
  static const int maxPerPage = 100;
}
