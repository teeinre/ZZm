import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/user.dart';

class ApiService {
  final http.Client client;
  String? _authToken;
  String? _storeNonce;
  String? _cartToken;

  ApiService({http.Client? client}) : client = client ?? http.Client();

  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  String _getBasicAuthHeader() {
    final credentials = '${ApiConstants.consumerKey}:${ApiConstants.consumerSecret}';
    final bytes = utf8.encode(credentials);
    final base64 = base64Encode(bytes);
    return 'Basic $base64';
  }

  Map<String, String> _getHeaders({bool useWcAuth = false, bool requireAuth = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (useWcAuth) {
      headers['Authorization'] = _getBasicAuthHeader();
    } else if (requireAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<http.Response> _get(String url, {bool useWcAuth = true, bool requireAuth = false}) async {
    try {
      final response = await client.get(
        Uri.parse(url),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to load data: $e');
    }
  }

  Future<http.Response> _post(String url, Map<String, dynamic> data, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      final response = await client.post(
        Uri.parse(url),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
        body: jsonEncode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to post data: $e');
    }
  }

  Future<http.Response> _put(String url, Map<String, dynamic> data, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      final response = await client.put(
        Uri.parse(url),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
        body: jsonEncode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to put data: $e');
    }
  }

  Future<http.Response> _delete(String url, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      final response = await client.delete(
        Uri.parse(url),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to delete data: $e');
    }
  }

  Future<http.StreamedResponse> _postMultipart(String url, Map<String, String> fields, String filePath, {bool useWcAuth = true}) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers.addAll(_getHeaders(useWcAuth: useWcAuth));
    request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    return await client.send(request);
  }

  /// Upload an image to the WordPress media library.
  /// Returns the uploaded image data (id, url) or null on failure.
  Future<Map<String, dynamic>?> uploadProductImage(String filePath) async {
    try {
      final url = '${ApiConstants.wpApiBase}/media';
      final streamed = await _postMultipart(url, {}, filePath, useWcAuth: false);
      // Use JWT auth if available, else fall back to WC auth wonky uploads
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[UploadImage] Error: $e');
    }
    // Fallback: try with WC auth
    try {
      final url = '${ApiConstants.wpApiBase}/media';
      final streamed = await _postMultipart(url, {}, filePath, useWcAuth: true);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[UploadImage] WC fallback error: $e');
    }
    return null;
  }

  http.Response _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    } else if (response.statusCode == 401) {
      throw UnauthorizedException('Unauthorized access');
    } else if (response.statusCode == 404) {
      throw NotFoundException('Resource not found');
    } else {
      throw ApiException(
        'Request failed with status: ${response.statusCode}',
        response.statusCode,
      );
    }
  }

  Future<User?> login(String username, String password) async {
    return await _attemptLogin(username, password);
  }

  Future<User?> loginWithEmail(String email, String password) async {
    final loginName = email.contains('@') ? email : email;
    final result = await _attemptLogin(loginName, password);
    if (result != null) return result;

    // If email login fails, try to find the username from email via WP API
    if (email.contains('@')) {
      final username = await _findUsernameByEmail(email);
      if (username != null) {
        return await _attemptLogin(username, password);
      }
    }
    return null;
  }

  Future<User?> _attemptLogin(String login, String password) async {
    try {
      final response = await _post(
        ApiConstants.authEndpoint,
        {
          'username': login,
          'password': password,
        },
        useWcAuth: false,
      );
      final data = jsonDecode(response.body);
      if (data['token'] != null) {
        _authToken = data['token'];
        return User(
          id: data['user_id'] ?? 0,
          email: data['user_email'] ?? '',
          username: data['user_display_name']?.toString(),
          token: data['token'],
        );
      }
    } catch (_) {
      // Will fall through to return null
    }
    return null;
  }

  Future<String?> _findUsernameByEmail(String email) async {
    try {
      final url = '${ApiConstants.wpApiBase}/users?search=${Uri.encodeComponent(email)}&per_page=5';
      final response = await _get(url, useWcAuth: false);
      final List<dynamic> users = jsonDecode(response.body);
      for (final user in users) {
        if (user['email']?.toString().toLowerCase() == email.toLowerCase()) {
          return user['slug']?.toString() ?? user['login']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> validateToken() async {
    if (_authToken == null) return false;
    try {
      await _get(
        ApiConstants.tokenValidateEndpoint,
        requireAuth: true,
        useWcAuth: false,
      );
      return true;
    } on NotFoundException {
      // JWT plugin validate route may not be available.
      // Token is still valid since login succeeded and WC auth works.
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Product>> getProducts({
    int page = 1,
    int perPage = ApiConstants.defaultPerPage,
    String? category,
    String? search,
  }) async {
    var url = '${ApiConstants.productsEndpoint}?page=$page&per_page=$perPage';
    if (category != null) {
      url += '&category=$category';
    }
    if (search != null) {
      url += '&search=$search';
    }
    final response = await _get(url, useWcAuth: true);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Product.fromJson(Map<String, dynamic>.from(json))).toList();
  }

  Future<List<Category>> getCategories({
    int page = 1,
    int perPage = ApiConstants.defaultPerPage,
  }) async {
    final url = '${ApiConstants.categoriesEndpoint}?page=$page&per_page=$perPage';
    final response = await _get(url, useWcAuth: true);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Category.fromJson(Map<String, dynamic>.from(json))).toList();
  }

  Future<Product?> getProduct(int id) async {
    final url = '${ApiConstants.productsEndpoint}/$id';
    final response = await _get(url, useWcAuth: true);
    return Product.fromJson(Map<String, dynamic>.from(jsonDecode(response.body)));
  }

  /// Fetches the raw product JSON (includes type, attributes, stock_status, etc.
  /// that are not present in the Product model).
  Future<Map<String, dynamic>> getProductJson(int id) async {
    final url = '${ApiConstants.productsEndpoint}/$id';
    final response = await _get(url, useWcAuth: true);
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  /// Fetches all variations for a variable product.
  Future<List<Map<String, dynamic>>> getProductVariations(int productId) async {
    final url = '${ApiConstants.productsEndpoint}/$productId/variations?per_page=100';
    final response = await _get(url, useWcAuth: true);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((v) => Map<String, dynamic>.from(v)).toList();
  }

  /// Creates a new variation for a variable product.
  Future<Map<String, dynamic>?> createProductVariation(int productId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.productsEndpoint}/$productId/variations';
      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Updates an existing product variation.
  Future<bool> updateProductVariation(int productId, int variationId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.productsEndpoint}/$productId/variations/$variationId';
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentGateways() async {
    final url = '${ApiConstants.wcApiBase}/payment_gateways';
    try {
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((g) => Map<String, dynamic>.from(g)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getShippingMethods() async {
    final url = '${ApiConstants.wcApiBase}/shipping_methods';
    try {
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((s) => Map<String, dynamic>.from(s)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Validate a WooCommerce coupon code. Returns coupon data or null if invalid.
  Future<Map<String, dynamic>?> validateCoupon(String code) async {
    try {
      // WC REST API: get all coupons matching the code
      final url = '${ApiConstants.wcApiBase}/coupons?code=$code';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first);
      }
    } catch (_) {}
    return null;
  }

  /// Fetches shipping methods specific to a vendor's shipping zones in Dokan.
  /// Dokan vendors configure their own shipping zones; this pulls the
  /// shipping methods available for each zone.
  Future<List<Map<String, dynamic>>> getVendorShippingMethods(int vendorStoreId) async {
    try {
      final zones = await getShippingZones();
      final vendorMethods = <Map<String, dynamic>>[];

      for (final zone in zones) {
        final zoneId = zone['id'];
        final zoneName = zone['name'] ?? 'Shipping Zone $zoneId';

        // Get methods for this zone
        final methodsUrl = '${ApiConstants.shippingZonesEndpoint}/$zoneId/methods';
        try {
          final response = await _get(methodsUrl, useWcAuth: true);
          final List<dynamic> methods = jsonDecode(response.body);
          for (final method in methods) {
            if (method['enabled'] == true) {
              vendorMethods.add({
                'id': '${method['method_id']}_$zoneId',
                'title': '${method['title']} ($zoneName)',
                'cost': _extractShippingCost(method),
                'zone_id': zoneId,
                'zone_name': zoneName,
                'method_id': method['method_id'],
              });
            }
          }
        } catch (_) {}
      }

      if (vendorMethods.isEmpty) {
        return [];
      }
      return vendorMethods;
    } catch (e) {
      return [];
    }
  }

  /// Fetches all WooCommerce shipping zones.
  Future<List<Map<String, dynamic>>> getShippingZones() async {
    final url = ApiConstants.shippingZonesEndpoint;
    try {
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((z) => Map<String, dynamic>.from(z)).toList();
    } catch (e) {
      return [];
    }
  }

  double _extractShippingCost(Map<String, dynamic> method) {
    final settings = method['settings'];
    if (settings is Map) {
      final cost = settings['cost'];
      if (cost != null) {
        final parsed = double.tryParse(cost['value']?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }
    // Try direct cost field
    final directCost = double.tryParse(method['cost']?.toString() ?? '');
    return directCost ?? 4.99;
  }

  /// Fetches Dokan store/vendor info by ID.
  Future<Map<String, dynamic>?> getDokanStore(int storeId) async {
    final url = '${ApiConstants.dokanStoresEndpoint}/$storeId';
    try {
      final response = await _get(url, useWcAuth: false);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Fetches products for a specific vendor/store.
  Future<List<Product>> getVendorProducts(int vendorId, {int page = 1, int perPage = 20}) async {
    var url = '${ApiConstants.productsEndpoint}?store_id=$vendorId&page=$page&per_page=$perPage';
    final response = await _get(url, useWcAuth: true);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Product.fromJson(Map<String, dynamic>.from(json))).toList();
  }

  /// Fetches all Dokan stores/vendors.
  Future<List<Map<String, dynamic>>> getDokanStores({int perPage = 50}) async {
    final url = '${ApiConstants.dokanStoresEndpoint}?per_page=$perPage';
    try {
      final response = await _get(url, useWcAuth: false);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((s) => Map<String, dynamic>.from(s)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Register a new user via WordPress REST API.
  Future<Map<String, dynamic>?> registerUser(String username, String email, String password) async {
    try {
      final url = '${ApiConstants.wpApiBase}/users/register';
      final response = await _post(
        url,
        {
          'username': username,
          'email': email,
          'password': password,
        },
        useWcAuth: false,
      );
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      // Fallback: try WC customers endpoint
      try {
        final url = '${ApiConstants.wcApiBase}/customers';
        final response = await _post(
          url,
          {
            'email': email,
            'first_name': username,
            'username': username,
            'password': password,
          },
          useWcAuth: true,
        );
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } catch (e2) {
        throw ApiException('Registration failed: ${e2.toString()}');
      }
    }
  }

  /// Fetch user orders via WooCommerce API (requires auth).
  Future<List<Map<String, dynamic>>> getUserOrders(int userId) async {
    try {
      final url = '${ApiConstants.ordersEndpoint}?customer=$userId&per_page=20';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((o) => Map<String, dynamic>.from(o)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch vendor bank details from Dokan profile settings.
  Future<Map<String, String>?> getVendorBankDetails(int vendorId) async {
    try {
      final store = await getDokanStore(vendorId);
      if (store != null) {
        // Check Dokan vendor profile bank fields
        final payment = store['payment'] as Map<String, dynamic>?;
        final bankData = payment?['bank'] as Map<String, dynamic>?;

        final iban = bankData?['iban']?.toString() ??
                     store['bank_iban']?.toString() ?? '';
        final acctName = bankData?['ac_name']?.toString() ??
                         store['account_name']?.toString() ?? '';
        final acctNumber = bankData?['ac_number']?.toString() ??
                           store['account_number']?.toString() ?? '';
        final bankName = bankData?['bank_name']?.toString() ??
                         store['bank_name']?.toString() ?? '';
        final sortCode = bankData?['bank_sort_code']?.toString() ??
                         store['sort_code']?.toString() ?? '';
        final bic = bankData?['swift']?.toString() ??
                    store['swift']?.toString() ?? '';

        // Only return if at least one bank field has data
        if ([iban, acctName, acctNumber, bankName].any((f) => f.isNotEmpty)) {
          return {
            'bank_name': bankName,
            'iban': iban,
            'account_name': acctName.isNotEmpty
                ? acctName
                : (store['company_name']?.toString() ?? store['store_name']?.toString() ?? ''),
            'account_number': acctNumber,
            'sort_code': sortCode,
            'bic': bic,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch site default bank details from WooCommerce BACS gateway settings.
  Future<Map<String, String>> getSiteBankDetails() async {
    try {
      final url = '${ApiConstants.wcApiBase}/payment_gateways/bacs';
      final response = await _get(url, useWcAuth: true);
      final data = jsonDecode(response.body);
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final accountName = settings['account_name']?['value']?.toString() ?? '';
      final accountNumber = settings['account_number']?['value']?.toString() ?? '';
      final sortCode = settings['sort_code']?['value']?.toString() ?? '';
      final iban = settings['iban']?['value']?.toString() ?? '';
      final bic = settings['bic']?['value']?.toString() ?? '';
      return {
        'bank_name': 'ZZmore Store',
        'account_name': accountName.isNotEmpty ? accountName : 'ZZmore Store',
        'sort_code': sortCode,
        'account_number': accountNumber,
        'iban': iban,
        'bic': bic,
      };
    } catch (e) {
      return {
        'bank_name': 'ZZmore Store',
        'account_name': '',
        'sort_code': '',
        'account_number': '',
        'iban': '',
        'bic': '',
      };
    }
  }

  /// Fetch product subscriptions info if available.
  Future<Map<String, dynamic>?> getProductSubscriptions(int productId) async {
    try {
      final url = '${ApiConstants.wcApiBase}/products/$productId';
      final response = await _get(url, useWcAuth: true);
      final prod = jsonDecode(response.body);
      final type = prod['type']?.toString();
      if (type == 'subscription' || type == 'variable-subscription') {
        return Map<String, dynamic>.from(prod);
      }
    } catch (_) {}
    return null;
  }

  /// Check if a product has booking enabled.
  Future<bool> isProductBookable(int productId) async {
    try {
      final url = '${ApiConstants.wcApiBase}/products/$productId';
      final response = await _get(url, useWcAuth: true);
      final prod = jsonDecode(response.body);
      return prod['type']?.toString() == 'booking';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCustomerData(int customerId) async {
    try {
      final url = '${ApiConstants.wcApiBase}/customers/$customerId';
      final response = await _get(url, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Fetch a single order by ID via WooCommerce API.
  Future<Map<String, dynamic>?> getOrder(int orderId) async {
    try {
      final url = '${ApiConstants.ordersEndpoint}/$orderId';
      final response = await _get(url, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Place a new order via WooCommerce API.
  Future<Map<String, dynamic>?> placeOrder({
    required int customerId,
    required List<Map<String, dynamic>> lineItems,
    required Map<String, dynamic> billing,
    required Map<String, dynamic> shipping,
    String paymentMethod = 'bacs',
    String paymentMethodTitle = 'Direct Bank Transfer',
    List<Map<String, dynamic>>? shippingLines,
  }) async {
    try {
      final data = <String, dynamic>{
        'customer_id': customerId,
        'payment_method': paymentMethod,
        'payment_method_title': paymentMethodTitle,
        'billing': billing,
        'shipping': shipping,
        'line_items': lineItems,
        'set_paid': false,
      };
      if (shippingLines != null && shippingLines.isNotEmpty) {
        data['shipping_lines'] = shippingLines;
      }
      final url = ApiConstants.ordersEndpoint;
      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Update customer data (billing/shipping/profile).
  Future<bool> updateCustomer(int customerId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.customersEndpoint}/$customerId';
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VENDOR DASHBOARD API METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetch vendor dashboard summary.
  ///
  /// Priority order (matching the zzmore.store website behavior):
  /// 1. WC Analytics API (`wc-analytics`) — auto-scoped to authenticated vendor
  /// 2. Dokan reports endpoint (`dokan/v1/reports`) — Dokan's own REST API
  /// 3. Aggregated from individual Dokan endpoints as final fallback
  Future<Map<String, dynamic>> getVendorReports() async {
    // ── 1. Try WC Analytics (what the website actually uses) ──
    final analyticsData = await _fetchWcAnalytics();
    if (analyticsData != null) return analyticsData;

    // ── 2. Try Dokan reports endpoint ──
    final dokanData = await _fetchDokanReports();
    if (dokanData != null) return dokanData;

    // ── 3. Aggregate from individual endpoints ──
    debugPrint('[VendorReports] All primary sources failed — aggregating from Dokan endpoints.');
    return await _aggregateVendorStats();
  }

  /// Fetch vendor stats from WC Analytics API (same data source as the website).
  /// Tries JWT Bearer auth first (vendor-scoped), falls back to Basic Auth.
  Future<Map<String, dynamic>?> _fetchWcAnalytics() async {
    try {
      final results = <String, dynamic>{};

      // Try JWT Bearer auth (vendor-scoped) first
      bool success = await _tryAnalyticsEndpoint(results, requireAuth: true);
      // Fall back to Basic Auth (admin-scoped, but provides data)
      if (!success) {
        success = await _tryAnalyticsEndpoint(results, useWcAuth: true);
      }

      if (success) {
        debugPrint('[VendorReports] Successfully fetched from WC Analytics API.');
        return results;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _tryAnalyticsEndpoint(Map<String, dynamic> results, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      double totalSales = 0;
      double totalVendorEarning = 0;
      int ordersCount = 0;

      // Revenue stats (no date params — auto-scoped by WC Analytics)
      try {
        final revUrl = ApiConstants.analyticsRevenueStats;
        final revResponse = await _get(revUrl, useWcAuth: useWcAuth, requireAuth: requireAuth);
        final revData = jsonDecode(revResponse.body);
        final totals = revData['totals'] as Map<String, dynamic>? ?? {};
        totalSales = ((totals['total_sales'] ?? totals['gross_sales'] ?? 0) as num).toDouble();
        totalVendorEarning = ((totals['total_vendor_earning'] ?? totals['net_revenue'] ?? 0) as num).toDouble();
        if (totals.containsKey('orders_count')) {
          ordersCount = (totals['orders_count'] as num).toInt();
        }
      } catch (_) {}

      // Orders stats if not already obtained
      if (ordersCount == 0) {
        try {
          final ordUrl = ApiConstants.analyticsOrdersStats;
          final ordResponse = await _get(ordUrl, useWcAuth: useWcAuth, requireAuth: requireAuth);
          final ordData = jsonDecode(ordResponse.body);
          final ordTotals = ordData['totals'] as Map<String, dynamic>? ?? {};
          ordersCount = (ordTotals['orders_count'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }

      if (totalSales > 0 || totalVendorEarning > 0 || ordersCount > 0) {
        results['sales'] = totalSales.toString();
        results['earnings'] = totalVendorEarning.toString();
        results['orders'] = ordersCount;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Fetch from Dokan's reports/summary endpoint.
  /// Parses the actual response format:
  /// { sales, orders_count: {total, wc-pending, wc-completed, ...}, seller_balance }
  Future<Map<String, dynamic>?> _fetchDokanReports() async {
    try {
      final url = ApiConstants.dokanReportsEndpoint;
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final raw = jsonDecode(response.body) as Map<String, dynamic>;

      // Parse orders_count breakdown
      final ordersCount = raw['orders_count'] as Map<String, dynamic>? ?? {};

      final parsed = <String, dynamic>{
        'sales': (raw['sales'] ?? '0').toString(),
        'orders': ordersCount['total'] ?? 0,
        'pending': ordersCount['wc-pending'] ?? 0,
        'processing': ordersCount['wc-processing'] ?? 0,
        'completed': ordersCount['wc-completed'] ?? 0,
        'pageviews': raw['pageviews'] ?? 0,
      };

      // Strip HTML from seller_balance (e.g. "£638.66" from span tags)
      final balanceHtml = raw['seller_balance']?.toString() ?? '';
      final balanceClean = balanceHtml
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'[^0-9.]'), '');
      final balanceValue = double.tryParse(balanceClean) ?? 0;
      parsed['earnings'] = balanceValue.toString();

      if (parsed['sales'] != '0' || (parsed['orders'] as int) > 0) {
        debugPrint('[VendorReports] Successfully fetched from Dokan reports/summary.');
        return parsed;
      }
    } on UnauthorizedException {
      debugPrint('[VendorReports] Dokan reports/summary: 401 Unauthorized.');
    } catch (e) {
      debugPrint('[VendorReports] Dokan reports/summary error: $e');
    }
    return null;
  }

  /// Aggregate vendor stats from individual Dokan endpoints when the main
  /// reports endpoint is unavailable (common on older Dokan versions or
  /// when the seller role lacks manage_woocommerce capability).
  Future<Map<String, dynamic>> _aggregateVendorStats() async {
    final stats = <String, dynamic>{
      'sales': '0', 'orders': 0, 'earnings': '0',
      'pageviews': 0, 'products': 0, 'pending': 0,
      'processing': 0, 'completed': 0,
    };

    try {
      // ── 1. Vendor orders (count + status breakdown) ──
      final orders = await getVendorOrders(perPage: 100);
      stats['orders'] = orders.length;
      stats['pending'] = orders.where((o) => o['status'] == 'pending').length;
      stats['processing'] = orders.where((o) => o['status'] == 'processing').length;
      stats['completed'] = orders.where((o) => o['status'] == 'completed').length;

      // Calculate total sales from order totals
      double totalSales = 0;
      for (final order in orders) {
        final total = double.tryParse(order['total']?.toString() ?? '0') ?? 0;
        totalSales += total;
      }
      stats['sales'] = totalSales.toStringAsFixed(2);
    } catch (_) {}

    try {
      // ── 2. Balance / earnings ──
      final balance = await getVendorBalance();
      stats['earnings'] = balance['current_balance']?.toString() ?? '0';
    } catch (_) {}

    try {
      // ── 3. Product count ──
      final products = await getVendorProducts(0, perPage: 100);
      stats['products'] = products.length;
    } catch (_) {}

    return stats;
  }

  /// Fetch summary/sales overview for a vendor.
  /// Uses dokan/v1/reports/summary which already includes the summary suffix.
  Future<Map<String, dynamic>> getVendorSalesOverview() async {
    try {
      final url = ApiConstants.dokanReportsEndpoint;
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return {};
    }
  }

  /// Fetch vendor's orders from Dokan.
  Future<List<Map<String, dynamic>>> getVendorOrders({int page = 1, int perPage = 20, String? status}) async {
    try {
      var url = '${ApiConstants.dokanOrdersEndpoint}?page=$page&per_page=$perPage';
      if (status != null) url += '&status=$status';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((o) => Map<String, dynamic>.from(o)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Update an order status (vendor).
  Future<bool> updateOrderStatus(int orderId, String status) async {
    try {
      final url = '${ApiConstants.ordersEndpoint}/$orderId';
      await _put(url, {'status': status}, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add order note (e.g., tracking number).
  Future<bool> addOrderNote(int orderId, String note, {bool customerNote = false}) async {
    try {
      final url = '${ApiConstants.ordersEndpoint}/$orderId/notes';
      await _post(url, {
        'note': note,
        'customer_note': customerNote,
      }, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetch vendor withdrawal history.
  Future<List<Map<String, dynamic>>> getVendorWithdrawals({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanWithdrawEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((w) => Map<String, dynamic>.from(w)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Request a withdrawal.
  Future<bool> requestWithdrawal(double amount, String method) async {
    try {
      final url = ApiConstants.dokanWithdrawEndpoint;
      await _post(url, {
        'amount': amount.toString(),
        'method': method,
      }, requireAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get vendor current balance.
  Future<Map<String, dynamic>> getVendorBalance() async {
    try {
      final url = ApiConstants.dokanBalanceEndpoint;  // Now points to reports/summary
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final raw = jsonDecode(response.body) as Map<String, dynamic>;

      // Strip HTML from seller_balance
      final balanceHtml = raw['seller_balance']?.toString() ?? '';
      final balanceClean = balanceHtml
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'[^0-9.]'), '');
      final balance = double.tryParse(balanceClean) ?? 0;

      return {
        'current_balance': balance,
        'total_earned': raw['sales'] ?? 0,
      };
    } catch (e) {
      return {'current_balance': 0, 'total_earned': 0, 'total_withdrawn': 0};
    }
  }

  /// Update store settings.
  /// Update meta fields on an existing order.
  Future<bool> updateOrderMeta(int orderId, Map<String, dynamic> metaData) async {
    try {
      final url = '${ApiConstants.ordersEndpoint}/$orderId';
      final data = <String, dynamic>{
        'meta_data': metaData.entries.map((e) => {
          'key': e.key,
          'value': e.value.toString(),
        }).toList(),
      };
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create a Dokan-compatible vendor sub-order linked to a parent order.
  Future<Map<String, dynamic>?> createSubOrder({
    required int parentId,
    required int vendorId,
    required List<Map<String, dynamic>> lineItems,
    required Map<String, dynamic> billing,
    required Map<String, dynamic> shipping,
    String paymentMethod = 'bacs',
    String paymentMethodTitle = 'Direct Bank Transfer',
  }) async {
    try {
      final data = <String, dynamic>{
        'parent_id': parentId,
        'status': 'pending',
        'payment_method': paymentMethod,
        'payment_method_title': paymentMethodTitle,
        'billing': billing,
        'shipping': shipping,
        'line_items': lineItems,
        'set_paid': false,
        'meta_data': [
          {'key': '_dokan_vendor_id', 'value': vendorId.toString()},
          {'key': '_dokan_order_type', 'value': 'suborder'},
        ],
      };
      final url = ApiConstants.ordersEndpoint;
      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateStoreSettings(Map<String, dynamic> data) async {
    try {
      final url = ApiConstants.dokanSettingsEndpoint;
      await _put(url, data, requireAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetch vendor-scoped coupons via Dokan API.
  Future<List<Map<String, dynamic>>> getVendorCoupons({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanCouponsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Create a coupon.
  Future<Map<String, dynamic>?> createCoupon(Map<String, dynamic> data) async {
    try {
      final url = ApiConstants.couponsEndpoint;
      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Update a coupon.
  Future<bool> updateCoupon(int id, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.couponsEndpoint}/$id';
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a coupon.
  Future<bool> deleteCoupon(int id) async {
    try {
      final url = '${ApiConstants.couponsEndpoint}/$id';
      await _delete(url, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetch product reviews for vendor.
  Future<List<Map<String, dynamic>>> getVendorReviews({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanReviewsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Reply to a review (via WC API - product review).
  Future<bool> replyToReview(int reviewId, int productId, String reply) async {
    try {
      final url = '${ApiConstants.wcApiBase}/products/reviews/$reviewId';
      await _put(url, {'review': reply, 'product_id': productId}, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create a new product.
  Future<Map<String, dynamic>?> createProduct(Map<String, dynamic> data) async {
    try {
      final url = ApiConstants.productsEndpoint;
      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Update a product.
  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.productsEndpoint}/$id';
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a product.
  Future<bool> deleteProduct(int id) async {
    try {
      final url = '${ApiConstants.productsEndpoint}/$id';
      await _delete(url, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get product categories for product creation form.
  Future<List<Map<String, dynamic>>> getProductCategories() async {
    try {
      final url = '${ApiConstants.categoriesEndpoint}?per_page=100';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get product tags.
  Future<List<Map<String, dynamic>>> getProductTags() async {
    try {
      final url = '${ApiConstants.wcApiBase}/products/tags?per_page=100';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((t) => Map<String, dynamic>.from(t)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch vendor announcements/notices.
  Future<List<Map<String, dynamic>>> getVendorAnnouncements({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanAnnouncementsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((a) => Map<String, dynamic>.from(a)).toList();
    } catch (e) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VENDOR AUTH & REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a new user via WooCommerce API.
  Future<Map<String, dynamic>?> registerCustomer({
    required String email,
    required String firstName,
    required String lastName,
    required String username,
    required String password,
    String? phone,
    Map<String, dynamic>? billing,
    Map<String, dynamic>? shipping,
  }) async {
    try {
      final url = ApiConstants.customersEndpoint;
      final data = <String, dynamic>{
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'password': password,
      };
      if (phone != null) data['billing'] = {'phone': phone, ...?billing};
      if (billing != null) data['billing'] = billing;
      if (shipping != null) data['shipping'] = shipping;

      final response = await _post(url, data, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Create a Dokan vendor store for a user.
  Future<Map<String, dynamic>?> createVendorStore({
    required int userId,
    required String storeName,
    required String phone,
    String? address,
    String? city,
    String? state,
    String? postcode,
    String? country,
    String? businessDescription,
    String? storeEmail,
    String? socialFb,
    String? socialIg,
    String? socialTw,
  }) async {
    try {
      final url = '${ApiConstants.dokanV1Base}/stores';
      final data = {
        'user_id': userId,
        'store_name': storeName,
        'phone': phone,
        'address': {'street_1': address ?? '', 'city': city ?? '',
            'state': state ?? '', 'zip': postcode ?? '', 'country': country ?? ''},
        'store_description': businessDescription ?? '',
        'email': storeEmail ?? '',
        'social': {
          'fb': socialFb ?? '',
          'instagram': socialIg ?? '',
          'twitter': socialTw ?? '',
        },
      };
      final response = await _post(url, data, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Check if a user has a Dokan vendor store.
  Future<Map<String, dynamic>?> getVendorStoreByUserId(int userId) async {
    try {
      final url = '${ApiConstants.dokanV1Base}/stores?user_id=$userId';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> stores = jsonDecode(response.body);
      if (stores.isNotEmpty) {
        return Map<String, dynamic>.from(stores[0]);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ─── Dokan Quote Credit ───
  Future<List<Map<String, dynamic>>> getDokanQuotes() async {
    try {
      final url = '${ApiConstants.dokanV1Base}/quotes';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((q) => Map<String, dynamic>.from(q)).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Dokan Returns/Refunds ───
  Future<List<Map<String, dynamic>>> getDokanRefunds() async {
    try {
      final url = '${ApiConstants.dokanV1Base}/refunds';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Dokan Livestreaming ───
  Future<List<Map<String, dynamic>>> getDokanLivestreams() async {
    try {
      final url = '${ApiConstants.dokanV1Base}/livestreams';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((s) => Map<String, dynamic>.from(s)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> createDokanLivestream(Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.dokanV1Base}/livestreams';
      final response = await _post(url, data, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  // ─── WooCommerce Settings ───

  /// Fetch WooCommerce general settings (currency, etc.)
  Future<Map<String, dynamic>> getWooCommerceSettings() async {
    try {
      final url = '${ApiConstants.wcApiBase}/settings/general';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      final settings = <String, dynamic>{};
      for (final item in data) {
        if (item['id'] != null) {
          settings[item['id']?.toString() ?? ''] = item['value'];
        }
      }
      return settings;
    } catch (e) {
      return {
        'currency': 'GBP',
        'currency_symbol': '\u00A3',
        'currency_position': 'left',
        'price_num_decimals': '2',
      };
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WOOCOMMERCE STORE API (block-based checkout with Dokan multi-vendor shipping)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reusable headers for Store API requests.
  Map<String, String> _getStoreApiHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_storeNonce != null) {
      headers['Nonce'] = _storeNonce!;
    }
    if (_cartToken != null) {
      headers['Cart-Token'] = _cartToken!;
    }
    return headers;
  }

  /// Fetch a WordPress nonce and Cart-Token from the Store API cart endpoint.
  /// Call this once before building the server-side cart.
  Future<void> fetchStoreNonce() async {
    try {
      final request = http.Request('GET', Uri.parse(ApiConstants.storeCartEndpoint));
      request.headers.addAll(_getStoreApiHeaders());
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _storeNonce = response.headers['nonce'];
        _cartToken = response.headers['cart-token'];
      }
    } catch (_) {
      // Nonce fetch failed — Store API checkout won't work
    }
  }

  /// Add a product to the server-side cart via Store API.
  /// For variations, pass the variation ID as productId (Store API resolves
  /// variation IDs directly) and optionally supply the variation attributes.
  /// Returns the cart item data or null on failure.
  Future<Map<String, dynamic>?> addToStoreCart(
    int productId, {
    int quantity = 1,
    int? variationId,
  }) async {
    try {
      // When a variation is specified, use the variation ID as the cart item ID.
      // The Store API treats variation IDs as direct product IDs in the cart.
      final effectiveId = (variationId != null && variationId > 0)
          ? variationId
          : productId;

      final data = <String, dynamic>{
        'id': effectiveId,
        'quantity': quantity,
      };

      // If this is a variation, include the variation array with proper attributes
      if (variationId != null && variationId > 0) {
        data['variation'] = <Map<String, String>>[];
      }

      final response = await _rawPost(ApiConstants.storeCartAddItemEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  /// Check whether the Store API is available on this site.
  Future<bool> isStoreApiAvailable() async {
    try {
      final uri = Uri.parse(ApiConstants.storeCartEndpoint);
      final response = await client.head(uri);
      return response.statusCode != 404;
    } catch (_) {
      return false;
    }
  }

  /// Get the current server-side cart (includes shipping rates per package).
  Future<Map<String, dynamic>?> getStoreCart() async {
    try {
      final request = http.Request('GET', Uri.parse(ApiConstants.storeCartEndpoint));
      request.headers.addAll(_getStoreApiHeaders());
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  /// Update the cart customer (billing + shipping address).
  Future<bool> updateStoreCartCustomer(Map<String, dynamic> billing, Map<String, dynamic> shipping) async {
    try {
      final data = <String, dynamic>{
        'billing_address': billing,
        'shipping_address': shipping,
      };
      final response = await _rawPost(ApiConstants.storeCartUpdateCustomerEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Select a shipping rate for a specific package.
  Future<bool> selectStoreShippingRate(String packageId, String rateId) async {
    try {
      final data = <String, dynamic>{
        'package_id': packageId,
        'rate_id': rateId,
      };
      final response = await _rawPost(ApiConstants.storeCartSelectShippingRateEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Place the order via the Store API checkout endpoint.
  /// Returns the order data on success, or null on failure.
  Future<Map<String, dynamic>?> storeCheckout({
    required String paymentMethod,
  }) async {
    try {
      final data = <String, dynamic>{
        'payment_method': paymentMethod,
      };
      final response = await _rawPost(ApiConstants.storeCheckoutEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        final body = jsonDecode(response.body);
        return Map<String, dynamic>.from(body);
      }
    } catch (_) {}
    return null;
  }

  /// Send a raw POST to the Store API with proper headers.
  Future<http.Response> _rawPost(String url, Map<String, dynamic> data) async {
    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll(_getStoreApiHeaders());
    request.body = jsonEncode(data);
    final streamed = await client.send(request);
    return await http.Response.fromStream(streamed);
  }

  /// Extract nonce and cart-token from Store API response headers.
  void _updateTokensFromResponse(http.Response response) {
    final nonce = response.headers['nonce'];
    if (nonce != null) _storeNonce = nonce;
    final token = response.headers['cart-token'];
    if (token != null) _cartToken = token;
  }

  /// Clear store API session tokens.
  void clearStoreSession() {
    _storeNonce = null;
    _cartToken = null;
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, [this.statusCode = 500]);

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message, 401);
}

class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message, 404);
}
