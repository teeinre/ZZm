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
  static const String storeCartUpdateCustomerEndpoint = '$storeApiBase/cart/update-customer';
  static const String storeCartSelectShippingRateEndpoint = '$storeApiBase/cart/select-shipping-rate';
  static const String storeCheckoutEndpoint = '$storeApiBase/checkout';

  // WooCommerce Analytics (used by Dokan vendor dashboard — scoped to authenticated vendor)
  static const String analyticsBase = '$baseUrl/wc-analytics';
  static const String analyticsRevenueStats = '$analyticsBase/reports/revenue/stats';
  static const String analyticsOrdersStats = '$analyticsBase/reports/orders/stats';
  static const String analyticsProductsStats = '$analyticsBase/reports/products/stats';

  // WooCommerce shipping zones
  static const String shippingZonesEndpoint = '$wcApiBase/shipping/zones';
  static const String shippingMethodsEndpoint = '$wcApiBase/shipping_methods';

  // WooCommerce API credentials
  static const String consumerKey = 'ck_537f3489368abb26297c733faf5dafb8b659a411';
  static const String consumerSecret = 'cs_e8b0de9db4df97bf5797e13aa8c4dd80a45d96d5';

  static const int defaultPerPage = 10;
  static const int maxPerPage = 100;
}
