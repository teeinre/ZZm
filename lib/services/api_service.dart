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
  final List<String> storeCookies = [];

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
      // Also send via X-JWT-Token as LiteSpeed-proof alternative header
      headers['X-JWT-Token'] = _authToken!;
    }
    return headers;
  }

  /// Append the JWT token as a ?token= query parameter to [url] if we have one.
  /// This is the LiteSpeed bypass — LiteSpeed strips the Authorization header
  /// but leaves query strings intact.  The mu-plugin reads from $_GET['token']
  /// as a fallback so dokan_get_current_user_id() resolves correctly.
  String _appendTokenParam(String url) {
    if (_authToken == null) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}token=${Uri.encodeComponent(_authToken!)}';
  }

  Future<http.Response> _get(String url, {bool useWcAuth = true, bool requireAuth = false}) async {
    try {
      final effectiveUrl = requireAuth ? _appendTokenParam(url) : url;
      final response = await client.get(
        Uri.parse(effectiveUrl),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to load data: $e');
    }
  }

  Future<http.Response> _post(String url, Map<String, dynamic> data, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      final effectiveUrl = requireAuth ? _appendTokenParam(url) : url;
      final response = await client.post(
        Uri.parse(effectiveUrl),
        headers: _getHeaders(useWcAuth: useWcAuth, requireAuth: requireAuth),
        body: jsonEncode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to post data: $e');
    }
  }

  /// Public POST wrapper — used by notification service for device token registration.
  Future<http.Response> post(String url, Map<String, dynamic> data, {bool useWcAuth = false, bool requireAuth = false}) {
    return _post(url, data, useWcAuth: useWcAuth, requireAuth: requireAuth);
  }

  Future<http.Response> _put(String url, Map<String, dynamic> data, {bool useWcAuth = false, bool requireAuth = false}) async {
    try {
      final effectiveUrl = requireAuth ? _appendTokenParam(url) : url;
      final response = await client.put(
        Uri.parse(effectiveUrl),
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
      final effectiveUrl = requireAuth ? _appendTokenParam(url) : url;
      final response = await client.delete(
        Uri.parse(effectiveUrl),
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
    // Capture WooCommerce session cookies (needed for WebView checkout)
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      storeCookies.add(setCookie);
    }
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
        final token = data['token'] as String;
        _authToken = token;
        // Extract user ID from JWT payload — the standard JWT Auth plugin
        // does NOT return user_id in the login response, only inside the token.
        final userId = _extractUserIdFromJwt(token) ?? (data['user_id'] as int? ?? 0);
        return User(
          id: userId,
          email: data['user_email'] ?? '',
          username: data['user_display_name']?.toString(),
          token: token,
        );
      }
    } catch (_) {
      // Will fall through to return null
    }
    return null;
  }

  /// Decode the JWT payload and extract the WordPress user ID.
  /// The standard JWT Auth for WP REST API token contains:
  /// { "data": { "user": { "id": "123" } } }
  int? _extractUserIdFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      // Add base64 padding if missing (JWTs omit padding)
      final padded = payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
      final decoded = utf8.decode(base64Decode(padded));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final userId = json['data']?['user']?['id'];
      if (userId is int) return userId;
      if (userId is String) return int.tryParse(userId);
    } catch (_) {}
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

  /// Requests a password-reset link for [email].
  /// Returns `null` on success, otherwise an error message to display.
  Future<String?> requestPasswordReset(String email) async {
    try {
      final response = await client.post(
        Uri.parse(ApiConstants.forgotPasswordEndpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = _decodeBody(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      return _extractErrorMessage(data) ?? 'Unable to send the reset link.';
    } catch (_) {
      return 'Something went wrong. Please check your connection and try again.';
    }
  }

  /// Resets a password using a reset key received via email.
  /// Returns `null` on success, otherwise an error message to display.
  Future<String?> resetPassword(String key, String login, String newPassword) async {
    try {
      final response = await client.post(
        Uri.parse(ApiConstants.resetPasswordEndpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'key': key, 'login': login, 'password': newPassword}),
      );
      final data = _decodeBody(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      return _extractErrorMessage(data) ?? 'Unable to reset the password.';
    } catch (_) {
      return 'Something went wrong. Please check your connection and try again.';
    }
  }

  dynamic _decodeBody(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      final msg = data['message'];
      if (msg != null && msg.toString().isNotEmpty) return msg.toString();
    }
    return null;
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

  /// Fetches shipping methods for a specific shipping zone.
  Future<List<Map<String, dynamic>>> getShippingZoneMethods(int zoneId) async {
    try {
      final url = '${ApiConstants.shippingZonesEndpoint}/$zoneId/methods';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Update a shipping zone method (enable/disable, adjust cost, etc.).
  Future<bool> updateShippingZoneMethod(int zoneId, int instanceId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.shippingZonesEndpoint}/$zoneId/methods/$instanceId';
      await _put(url, data, useWcAuth: true);
      return true;
    } catch (e) {
      return false;
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

  /// Resolves the vendor shipping fee for a single product using the
  /// server-side checkout logic (zzmore-shipping-fee.php). Returns the
  /// per-item cost, or null when the server could not resolve a fee.
  Future<double?> getProductShippingFee(int productId, {int quantity = 1}) async {
    final url = Uri.parse(ApiConstants.productShippingFeeEndpoint).replace(
      queryParameters: {
        'product_id': '$productId',
        'quantity': '$quantity',
      },
    );
    try {
      final response = await _get(url.toString(), useWcAuth: false);
      final data = jsonDecode(response.body);
      if (data is Map && data['available'] == true) {
        final cost = data['cost'];
        if (cost != null) {
          final parsed = double.tryParse(cost.toString());
          if (parsed != null) return parsed;
        }
      }
    } catch (_) {}
    return null;
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

  /// Fetches Dokan store/vendor info by ID (legacy REST API — use getVendorBridgeStore instead).
  Future<Map<String, dynamic>?> getDokanStore(int storeId) async {
    final url = '${ApiConstants.dokanStoresEndpoint}/$storeId';
    try {
      final response = await _get(url, useWcAuth: false);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Fetches vendor store settings via the reliable vendor-bridge endpoint.
  /// This reads directly from Dokan's internal PHP objects, bypassing
  /// the inconsistent Dokan REST API.
  Future<Map<String, dynamic>?> getVendorBridgeStore() async {
    final url = '${ApiConstants.baseUrl}/vendor-bridge/v1/store/me';
    try {
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final body = jsonDecode(response.body);
      return Map<String, dynamic>.from(body);
    } catch (e) {
      debugPrint('[ApiService] getVendorBridgeStore error: $e');
      // Fall back to legacy Dokan REST API
      return null;
    }
  }

  /// Updates vendor store settings via the vendor-bridge endpoint.
  Future<bool> updateVendorBridgeStore(Map<String, dynamic> data) async {
    final url = '${ApiConstants.baseUrl}/vendor-bridge/v1/store/me';
    try {
      await _put(url, data, useWcAuth: false, requireAuth: true);
      return true;
    } catch (e) {
      debugPrint('[ApiService] updateVendorBridgeStore error: $e');
      return false;
    }
  }

  /// Fetches products for a specific vendor/store.
  /// Uses [authorUserId] (vendor's WP user ID) as primary filter — this is
  /// the reliable post_author filter. Falls back to store_id if authorUserId
  /// is not provided.
  Future<List<Product>> getVendorProducts(int vendorId, {int? authorUserId, int page = 1, int perPage = 20}) async {
    // Build URL with proper author filter (store_id is not a WC API parameter)
    var url = '${ApiConstants.productsEndpoint}?page=$page&per_page=$perPage';
    if (authorUserId != null && authorUserId > 0) {
      url += '&author=$authorUserId';
    }
    // Note: If authorUserId is not provided, products are NOT filtered by vendor.
    // Callers should always pass authorUserId for vendor-scoped product queries.
    final response = await _get(url, useWcAuth: true);
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Product.fromJson(Map<String, dynamic>.from(json))).toList();
  }

  /// Fetches products for a specific Dokan store using the Dokan REST API.
  /// Uses the public endpoint — no authentication required for browsing.
  Future<List<Product>> getDokanStoreProducts(int storeId, {int page = 1, int perPage = 20}) async {
    final url = '${ApiConstants.dokanStoresEndpoint}/$storeId/products?page=$page&per_page=$perPage';
    try {
      final response = await _get(url, useWcAuth: false);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Product.fromJson(Map<String, dynamic>.from(json))).toList();
    } catch (e) {
      debugPrint('[ApiService] getDokanStoreProducts error: $e');
      return [];
    }
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

  /// Fetch the currently authenticated WP user profile via REST API.
  /// Requires a valid JWT token (set via setAuthToken before calling).
  Future<Map<String, dynamic>?> getCurrentWPUser() async {
    try {
      final url = '${ApiConstants.wpApiBase}/users/me';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return null;
    }
  }

  /// Update the WP user profile (name, email, etc.) via REST API.
  /// Requires a valid JWT token.
  Future<bool> updateWPUser(int userId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.wpApiBase}/users/$userId';
      await _put(url, data, useWcAuth: false, requireAuth: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Find a WooCommerce customer by email (for linking WP user to WC customer).
  Future<Map<String, dynamic>?> getWCCustomerByEmail(String email) async {
    try {
      final url = '${ApiConstants.wcApiBase}/customers?email=${Uri.encodeComponent(email)}';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first);
      }
    } catch (_) {}
    return null;
  }

  /// Find a WooCommerce customer by WordPress user ID (most reliable lookup).
  Future<Map<String, dynamic>?> getWCCustomerById(String userId) async {
    try {
      final url = '${ApiConstants.wcApiBase}/customers/$userId';
      final response = await _get(url, useWcAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (_) {}
    return null;
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
    List<Map<String, dynamic>>? taxLines,
    List<Map<String, dynamic>>? couponLines,
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
      if (taxLines != null && taxLines.isNotEmpty) {
        data['tax_lines'] = taxLines;
      }
      if (couponLines != null && couponLines.isNotEmpty) {
        data['coupon_lines'] = couponLines;
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
  /// [vendorId] is forwarded to the aggregator so client-side order filtering
  /// runs when the aggregated fallback path is used (Dokan REST may leak cross-
  /// vendor orders without the vendorId parameter).
  Future<Map<String, dynamic>> getVendorReports({int? vendorId}) async {
    // ── 1. Try WC Analytics (what the website actually uses) ──
    final analyticsData = await _fetchWcAnalytics();
    if (analyticsData != null) return analyticsData;

    // ── 2. Try Dokan reports endpoint ──
    final dokanData = await _fetchDokanReports();
    if (dokanData != null) return dokanData;

    // ── 3. Aggregate from individual endpoints ──
    debugPrint('[VendorReports] All primary sources failed — aggregating from Dokan endpoints.');
    return await _aggregateVendorStats(vendorId: vendorId);
  }

  /// Fetch vendor stats from WC Analytics API.
  /// ── CRITICAL SECURITY NOTE ──
  /// WC Analytics + WC Basic Auth = ADMIN-LEVEL CREDENTIALS that return
  /// marketplace-wide aggregates (cross-vendor data leak).  So we ONLY try
  /// JWT Bearer auth (vendor-scoped) here.  If the JWT analytics call fails
  /// we fall through to the Dokan REST reports or vendor-api.php bypass
  /// which are both already hard-scoped to the authenticated user's own
  /// vendor identity.  Never use useWcAuth for analytics.
  Future<Map<String, dynamic>?> _fetchWcAnalytics() async {
    try {
      final results = <String, dynamic>{};
      // JWT Bearer auth ONLY — vendor-scoped by the server
      final success = await _tryAnalyticsEndpoint(results, requireAuth: true);
      if (success) {
        debugPrint('[VendorReports] Successfully fetched from WC Analytics API (JWT-scoped).');
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
  /// [vendorId] is required for client-side order filtering — without it,
  /// Dokan REST may return cross-vendor orders for the marketplace.
  Future<Map<String, dynamic>> _aggregateVendorStats({int? vendorId}) async {
    final stats = <String, dynamic>{
      'sales': '0', 'orders': 0, 'earnings': '0',
      'pageviews': 0, 'products': 0, 'pending': 0,
      'processing': 0, 'completed': 0,
    };

    try {
      // ── 1. Vendor orders (count + status breakdown) — vendorId required ──
      final orders = await getVendorOrders(perPage: 100, vendorId: vendorId);
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

  /// Fetch vendor's orders from Dokan (scoped to the authenticated vendor via JWT).
  /// Falls back to WC API with per-product filtering if vendorId is provided and the
  /// Dokan endpoint returns orders not belonging to this vendor.
  Future<List<Map<String, dynamic>>> getVendorOrders({
    int page = 1,
    int perPage = 20,
    String? status,
    int? vendorId,
  }) async {
    try {
      var url = '${ApiConstants.dokanOrdersEndpoint}?page=$page&per_page=$perPage';
      if (status != null) url += '&status=$status';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      final orders = data.map((o) => Map<String, dynamic>.from(o)).toList();

      // Always filter by vendor when vendorId is known — Dokan's REST API
      // may leak cross-vendor orders depending on plugin version/auth state.
      if (vendorId != null && vendorId > 0) {
        return await _filterOrdersByVendor(orders, vendorId);
      }
      return orders;
    } catch (e) {
      // Fallback: fetch via WC API filtered by vendor's product IDs
      if (vendorId != null && vendorId > 0) {
        return await _fetchVendorOrdersViaWcApi(vendorId, page, perPage, status);
      }
      return [];
    }
  }

  /// Filter orders to only those containing products belonging to the given vendor.
  Future<List<Map<String, dynamic>>> _filterOrdersByVendor(
    List<Map<String, dynamic>> orders,
    int vendorId,
  ) async {
    try {
      // Get vendor's product IDs
      final vendorProducts = await getVendorProducts(vendorId, perPage: 100);
      final vendorProductIds = vendorProducts.map((p) => p.id).toSet();

      if (vendorProductIds.isEmpty) return orders; // can't filter — return as-is

      return orders.where((order) {
        final items = order['line_items'] as List<dynamic>? ?? [];
        return items.any((item) {
          final productId = item['product_id'] as int?;
          return productId != null && vendorProductIds.contains(productId);
        });
      }).toList();
    } catch (_) {
      return orders;
    }
  }

  /// Fetch orders containing the vendor's products via WC API.
  /// This is a reliable fallback when the Dokan orders endpoint is unavailable.
  Future<List<Map<String, dynamic>>> _fetchVendorOrdersViaWcApi(
    int vendorId,
    int page,
    int perPage,
    String? status,
  ) async {
    try {
      final vendorProducts = await getVendorProducts(vendorId, perPage: 100);
      final vendorProductIds = vendorProducts.map((p) => p.id).toSet();
      if (vendorProductIds.isEmpty) return [];

      // Fetch all orders, then filter client-side (WC API doesn't support
      // multi-product filter in a single query efficiently)
      var url = '${ApiConstants.ordersEndpoint}?page=$page&per_page=$perPage';
      if (status != null) url += '&status=$status';
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      final allOrders = data.map((o) => Map<String, dynamic>.from(o)).toList();

      return allOrders.where((order) {
        final items = order['line_items'] as List<dynamic>? ?? [];
        return items.any((item) {
          final productId = item['product_id'] as int?;
          return productId != null && vendorProductIds.contains(productId);
        });
      }).toList();
    } catch (_) {
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

  /// Update an order via Dokan REST API (vendor-scoped via JWT).
  /// Uses `dokan/v1/orders/{id}` PUT which checks `dokan_get_seller_id_by_order()`
  /// to ensure the vendor owns this order.
  Future<bool> updateDokanOrder(int orderId, Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.dokanOrdersEndpoint}/$orderId';
      await _put(url, data, requireAuth: true, useWcAuth: false);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add a note to an order via Dokan REST API (vendor-scoped via JWT).
  Future<bool> addDokanOrderNote(int orderId, String note, {bool customerNote = false}) async {
    try {
      final url = '${ApiConstants.dokanOrdersEndpoint}/$orderId/notes';
      final data = <String, dynamic>{
        'note': note,
        'customer_note': customerNote,
      };
      await _post(url, data, requireAuth: true, useWcAuth: false);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a product via Dokan REST API (vendor-scoped via JWT).
  /// Uses `dokan/v1/products/{id}` DELETE which checks `post_author`.
  Future<bool> deleteDokanProduct(int id) async {
    try {
      final url = '${ApiConstants.dokanV1Base}/products/$id';
      await _delete(url, requireAuth: true, useWcAuth: false);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a coupon via Dokan REST API (vendor-scoped via JWT).
  /// Uses `dokan/v1/coupons/{id}` DELETE which checks `post_author`.
  Future<bool> deleteDokanCoupon(int id) async {
    try {
      final url = '${ApiConstants.dokanCouponsEndpoint}/$id';
      await _delete(url, requireAuth: true, useWcAuth: false);
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
  /// Falls back to vendor-api.php bypass if the REST endpoint is blocked or returns empty.
  Future<List<Map<String, dynamic>>> getVendorCoupons({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanCouponsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (e) {
      // Fallback to vendor-api.php bypass
      try {
        final apiCoupons = await getVendorApiCoupons(page: page, perPage: perPage);
        if (apiCoupons.isNotEmpty) {
          debugPrint('[Coupons] Loaded from vendor-api.php bypass (${apiCoupons.length}).');
          return apiCoupons;
        }
      } catch (_) {}
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
  /// [vendorUserId] is the WordPress user ID of the vendor (post_author of products).
  /// When provided, we post-filter the Dokan REST result to keep only reviews
  /// for products whose post_author matches — closing the gap when Dokan's REST
  /// returns marketplace-wide reviews.
  Future<List<Map<String, dynamic>>> getVendorReviews({
    int page = 1,
    int perPage = 20,
    int? vendorUserId,
  }) async {
    try {
      final url = '${ApiConstants.dokanReviewsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      final reviews = data.map((r) => Map<String, dynamic>.from(r)).toList();

      // ── Vendor‑scope defensive filter ──────────────────────────────
      if (vendorUserId != null && vendorUserId > 0) {
        return _filterReviewsForVendor(reviews, vendorUserId);
      }
      return reviews;
    } catch (e) {
      // Fallback to vendor-api.php bypass (already vendor-scoped server-side)
      try {
        final apiReviews = await getVendorApiReviews(page: page, perPage: perPage);
        if (apiReviews.isNotEmpty) {
          debugPrint('[Reviews] Loaded from vendor-api.php bypass (${apiReviews.length}).');
          return apiReviews;
        }
      } catch (_) {}
      return [];
    }
  }

  /// Keep only reviews whose product belongs to [vendorUserId].
  Future<List<Map<String, dynamic>>> _filterReviewsForVendor(
      List<Map<String, dynamic>> reviews, int vendorUserId) async {
    if (reviews.isEmpty) return reviews;

    // Collect unique product IDs from the reviews
    final productIds = <int>{};
    for (final r in reviews) {
      final pid = r['product_id'] is int
          ? r['product_id'] as int
          : int.tryParse(r['product_id']?.toString() ?? '');
      if (pid != null) productIds.add(pid);
    }
    if (productIds.isEmpty) return reviews;

    // Batch-resolve ownership: one WC API call fetching all vendor products
    final ownedProductIds = <int>{};
    try {
      final vendorProducts = await getVendorProducts(0, perPage: 100, authorUserId: vendorUserId);
      for (final p in vendorProducts) {
        ownedProductIds.add(p.id);
      }
    } catch (_) {
      // If the batch call fails, fall back to per-product check
      for (final pid in productIds) {
        try {
          final checkUrl = '${ApiConstants.productsEndpoint}/$pid';
          final checkResponse = await client.get(
            Uri.parse(checkUrl),
            headers: _getHeaders(useWcAuth: true),
          );
          if (checkResponse.statusCode == 200) {
            final p = jsonDecode(checkResponse.body);
            if ((p['author_id'] ?? p['author']) == vendorUserId) {
              ownedProductIds.add(pid);
            }
          }
        } catch (_) {}
      }
    }

    final owned = ownedProductIds; // capture for closure
    return reviews.where((r) {
      final pid = r['product_id'] is int
          ? r['product_id'] as int
          : int.tryParse(r['product_id']?.toString() ?? '');
      return pid != null && owned.contains(pid);
    }).toList();
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
  /// Falls back to vendor-api.php bypass if the REST endpoint is blocked or returns empty.
  Future<List<Map<String, dynamic>>> getVendorAnnouncements({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.dokanAnnouncementsEndpoint}?page=$page&per_page=$perPage';
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((a) => Map<String, dynamic>.from(a)).toList();
    } catch (e) {
      // Fallback to vendor-api.php bypass
      try {
        final apiAnnouncements = await getVendorApiAnnouncements(page: page, perPage: perPage);
        if (apiAnnouncements.isNotEmpty) {
          debugPrint('[Announcements] Loaded from vendor-api.php bypass (${apiAnnouncements.length}).');
          return apiAnnouncements;
        }
      } catch (_) {}
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

  // ─── Vendor API Helpers (token in query param — LiteSpeed strips Authorization header) ───

  /// Build a vendor-api.php URL with the JWT token as a query parameter.
  /// LiteSpeed/LSAPI strips the Authorization header, so we pass the token in the URL.
  String _vendorApiUrl(String pathAndQuery) {
    if (_authToken != null) {
      return '$pathAndQuery&token=${Uri.encodeComponent(_authToken!)}';
    }
    return pathAndQuery;
  }

  Future<http.Response> _vendorApiGet(String url) async {
    return _get(_vendorApiUrl(url), useWcAuth: false, requireAuth: false);
  }

  Future<http.Response> _vendorApiPost(String url, Map<String, dynamic> data) async {
    return _post(_vendorApiUrl(url), data, useWcAuth: false, requireAuth: false);
  }

  // ─── Vendor API Bypass (vendor-api.php — bypasses REST blockage) ───

  /// Fetch vendor reports via vendor-api.php (bypasses REST if /wp-json/ is blocked).
  Future<Map<String, dynamic>?> getVendorApiReports() async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_reports';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[VendorAPI] Reports fetch failed: $e');
    }
    return null;
  }

  /// Fetch vendor store info via vendor-api.php.
  Future<Map<String, dynamic>?> getVendorApiStore() async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_store';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[VendorAPI] Store fetch failed: $e');
    }
    return null;
  }

  /// Update vendor store settings via vendor-api.php.
  Future<bool> updateVendorApiStore(Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=update_store';
      final response = await _vendorApiPost(url, data);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[VendorAPI] Store update failed: $e');
      return false;
    }
  }

  /// Fetch vendor products via vendor-api.php.
  Future<List<Map<String, dynamic>>> getVendorApiProducts({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_products&page=$page&per_page=$perPage';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List<dynamic>? ?? [];
        return products.map((p) => Map<String, dynamic>.from(p)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] Products fetch failed: $e');
    }
    return [];
  }

  /// Fetch vendor orders via vendor-api.php.
  Future<List<Map<String, dynamic>>> getVendorApiOrders({String? status, int page = 1, int perPage = 20}) async {
    try {
      final statusParam = status != null ? '&status=$status' : '';
      final url = '${ApiConstants.vendorApiBase}?action=get_orders&page=$page&per_page=$perPage$statusParam';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final orders = data['orders'] as List<dynamic>? ?? [];
        return orders.map((o) => Map<String, dynamic>.from(o)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] Orders fetch failed: $e');
    }
    return [];
  }

  /// Fetch vendor balance via vendor-api.php.
  Future<Map<String, dynamic>?> getVendorApiBalance() async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_balance';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('[VendorAPI] Balance fetch failed: $e');
    }
    return null;
  }

  // ─── Customer / User API Bypass (vendor-api.php) ───

  /// Fetch vendor reviews via vendor-api.php (already vendor-scoped server-side).
  Future<List<Map<String, dynamic>>> getVendorApiReviews({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_reviews&page=$page&per_page=$perPage';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reviews = data['reviews'] as List<dynamic>? ?? [];
        return reviews.map((r) => Map<String, dynamic>.from(r)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] Reviews fetch failed: $e');
    }
    return [];
  }

  /// Fetch vendor coupons via vendor-api.php.
  Future<List<Map<String, dynamic>>> getVendorApiCoupons({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_coupons&page=$page&per_page=$perPage';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coupons = data['coupons'] as List<dynamic>? ?? [];
        return coupons.map((c) => Map<String, dynamic>.from(c)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] Coupons fetch failed: $e');
    }
    return [];
  }

  /// Fetch vendor announcements via vendor-api.php.
  Future<List<Map<String, dynamic>>> getVendorApiAnnouncements({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_announcements&page=$page&per_page=$perPage';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final announcements = data['announcements'] as List<dynamic>? ?? [];
        return announcements.map((a) => Map<String, dynamic>.from(a)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] Announcements fetch failed: $e');
    }
    return [];
  }

  // ─── Customer / User API Bypass (vendor-api.php) (continued) ───

  /// Fetch WordPress user profile data via vendor-api.php.
  /// Returns display_name, username, email, first_name, last_name, is_vendor.
  Future<Map<String, dynamic>?> getVendorApiUser() async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_user';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.isNotEmpty) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('[VendorAPI] User fetch failed: $e');
    }
    return null;
  }

  /// Fetch WC customer data (billing, shipping) via vendor-api.php.
  Future<Map<String, dynamic>?> getVendorApiCustomer() async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_customer';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.isNotEmpty) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('[VendorAPI] Customer fetch failed: $e');
    }
    return null;
  }

  /// Update WC customer data (billing, shipping) via vendor-api.php.
  Future<bool> updateVendorApiCustomer(Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=update_customer';
      final response = await _vendorApiPost(url, data);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[VendorAPI] Customer update failed: $e');
      return false;
    }
  }

  /// Update WP user profile via vendor-api.php.
  /// Uses wp_update_user() — inherits WP's validation.
  Future<bool> updateVendorApiUser(Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=update_user';
      final response = await _vendorApiPost(url, data);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[VendorAPI] User update failed: $e');
      return false;
    }
  }

  /// Update WP user via vendor-api.php — returns raw response so caller can read error codes.
  Future<Map<String, dynamic>> updateVendorApiUserRaw(Map<String, dynamic> data) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=update_user';
      final response = await _vendorApiPost(url, data);
      final body = jsonDecode(response.body);
      return body is Map ? Map<String, dynamic>.from(body) : {'success': response.statusCode == 200};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Fetch user orders via vendor-api.php.
  Future<List<Map<String, dynamic>>> getVendorApiUserOrders({int page = 1, int perPage = 20}) async {
    try {
      final url = '${ApiConstants.vendorApiBase}?action=get_orders_user&page=$page&per_page=$perPage';
      final response = await _vendorApiGet(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final orders = data['orders'] as List<dynamic>? ?? [];
        return orders.map((o) => Map<String, dynamic>.from(o)).toList();
      }
    } catch (e) {
      debugPrint('[VendorAPI] User orders fetch failed: $e');
    }
    return [];
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

  /// Fetch public live streams for the home page (no auth required).
  /// Queries the mu-plugin bridge endpoint which pulls data from the DLS
  /// (Dokan Live Stream) plugin's vendor user-meta storage.
  Future<List<Map<String, dynamic>>> getPublicLivestreams() async {
    // Priority 1: App bridge endpoint — renders DLS shortcode + vendor meta server-side
    try {
      debugPrint('[LivestreamAPI] Trying: ${ApiConstants.appLivestreamsEndpoint}');
      final response = await _get(ApiConstants.appLivestreamsEndpoint, useWcAuth: false);
      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        debugPrint('[LivestreamAPI] Got ${body is List ? body.length : 'map'} results from app bridge');
        if (body is List) return body.map((s) => Map<String, dynamic>.from(s)).toList();
        if (body is Map && body.containsKey('data')) {
          final data = body['data'];
          if (data is List) return data.map((s) => Map<String, dynamic>.from(s)).toList();
        }
      } else {
        debugPrint('[LivestreamAPI] App bridge returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[LivestreamAPI] App bridge error: $e');
    }

    // Priority 2: Dokan REST API + WP API fallbacks
    final paths = [
      ApiConstants.dokanLiveStreamsEndpoint,
      ApiConstants.dokanLiveStreamsAltEndpoint,
      '${ApiConstants.wpApiBase}/livestreams',
      '${ApiConstants.wpApiBase}/live-streams',
    ];
    for (final path in paths) {
      try {
        debugPrint('[LivestreamAPI] Trying fallback: $path');
        final response = await _get(path, useWcAuth: false);
        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is List) return body.map((s) => Map<String, dynamic>.from(s)).toList();
          if (body is Map && body.containsKey('data')) {
            final data = body['data'];
            if (data is List) return data.map((s) => Map<String, dynamic>.from(s)).toList();
          }
        }
      } catch (e) {
        debugPrint('[LivestreamAPI] Fallback $path error: $e');
      }
    }
    debugPrint('[LivestreamAPI] All endpoints failed — returning empty list');
    return [];
  }

  /// Fetch vendor reports via Woo Report plugin (custom plugin).
  Future<Map<String, dynamic>?> getWooReportDashboard() async {
    try {
      final url = ApiConstants.wooReportDashboard;
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      debugPrint('[WooReport] Dashboard fetch failed: $e');
      return null;
    }
  }

  /// Fetch vendor-specific stats via Woo Report plugin.
  Future<Map<String, dynamic>?> getWooReportVendorStats() async {
    try {
      final url = ApiConstants.wooReportVendorStats;
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      debugPrint('[WooReport] Vendor stats fetch failed: $e');
      return null;
    }
  }

  // ─── WooCommerce Settings ───

  /// Fetch WooCommerce general settings (currency, etc.)
  Future<Map<String, dynamic>> getWooCommerceSettings() async {
    try {
      final url = '${ApiConstants.wcApiBase}/settings/general';
      debugPrint('[WC Settings] Fetching from $url');
      final response = await _get(url, useWcAuth: true);
      final List<dynamic> data = jsonDecode(response.body);
      final settings = <String, dynamic>{};
      for (final item in data) {
        if (item['id'] != null) {
          settings[item['id']?.toString() ?? ''] = item['value'];
        }
      }
      debugPrint('[WC Settings] Loaded: currency=${settings['woocommerce_currency']}');
      return settings;
    } catch (e) {
      debugPrint('[WC Settings] Failed: $e');
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
      debugPrint('[StoreAPI] GET cart (init session)');
      final response = await client.get(
        Uri.parse(ApiConstants.storeCartEndpoint),
        headers: _getStoreApiHeaders(),
      );
      debugPrint('[StoreAPI] Init response ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _storeNonce = response.headers['nonce'];
        _cartToken = response.headers['cart-token'];
        debugPrint('[StoreAPI] Got nonce: ${_storeNonce != null}, cart-token: ${_cartToken != null}');
        final setCookie = response.headers['set-cookie'];
        if (setCookie != null) storeCookies.add(setCookie);
      } else {
        debugPrint('[StoreAPI] Init FAILED: ${response.statusCode} ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
      }
    } catch (e) {
      debugPrint('[StoreAPI] Init exception: $e');
      rethrow;
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
      final effectiveId = (variationId != null && variationId > 0)
          ? variationId
          : productId;

      final data = <String, dynamic>{
        'id': effectiveId,
        'quantity': quantity,
      };

      if (variationId != null && variationId > 0) {
        data['variation'] = <Map<String, String>>[];
      }

      debugPrint('[StoreAPI] addToCart: product=$effectiveId qty=$quantity variationId=$variationId');
      final response = await _storePost(ApiConstants.storeCartAddItemEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        if (body is Map) return Map<String, dynamic>.from(body);
        debugPrint('[StoreAPI] addToCart unexpected response type: ${body.runtimeType}');
      } else {
        debugPrint('[StoreAPI] addToCart FAILED: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[StoreAPI] addToCart exception: $e');
    }
    return null;
  }

  /// Check whether the Store API is available on this site.
  Future<bool> isStoreApiAvailable() async {
    try {
      final response = await client.get(
        Uri.parse(ApiConstants.storeCartEndpoint),
        headers: _getStoreApiHeaders(),
      );
      return response.statusCode != 404;
    } catch (_) {
      return false;
    }
  }

  /// Get the current server-side cart (includes shipping rates per package).
  Future<Map<String, dynamic>?> getStoreCart() async {
    try {
      debugPrint('[StoreAPI] GET cart');
      final response = await client.get(
        Uri.parse(ApiConstants.storeCartEndpoint),
        headers: _getStoreApiHeaders(),
      );
      _updateTokensFromResponse(response);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = Map<String, dynamic>.from(jsonDecode(response.body));
        debugPrint('[StoreAPI] Cart loaded — ${(body["items"] as List?)?.length ?? 0} items, ${(body["payment_methods"] as List?)?.length ?? 0} payments');
        return body;
      } else {
        debugPrint('[StoreAPI] GET cart FAILED: ${response.statusCode} ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
      }
    } catch (e) {
      debugPrint('[StoreAPI] GET cart exception: $e');
    }
    return null;
  }

  /// Update the cart customer (billing + shipping address).
  Future<bool> updateStoreCartCustomer(Map<String, dynamic> billing, Map<String, dynamic> shipping) async {
    try {
      final data = <String, dynamic>{
        'billing_address': billing,
        'shipping_address': shipping,
      };
      final response = await _storePost(ApiConstants.storeCartUpdateCustomerEndpoint, data);
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
      final response = await _storePost(ApiConstants.storeCartSelectShippingRateEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Update a cart item's quantity via Store API.
  Future<bool> updateStoreCartItem(String itemKey, int quantity) async {
    try {
      final data = <String, dynamic>{
        'key': itemKey,
        'quantity': quantity,
      };
      final response = await _storePost(ApiConstants.storeCartUpdateItemEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Remove an item from the cart via Store API.
  Future<bool> removeStoreCartItem(String itemKey) async {
    try {
      final data = <String, dynamic>{'key': itemKey};
      final response = await _storePost(ApiConstants.storeCartRemoveItemEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Apply a coupon code via Store API.
  Future<bool> applyStoreCoupon(String code) async {
    try {
      final data = <String, dynamic>{'code': code};
      final response = await _storePost(ApiConstants.storeCartApplyCouponEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updateTokensFromResponse(response);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Remove a coupon from the cart via Store API.
  Future<bool> removeStoreCoupon(String code) async {
    try {
      final data = <String, dynamic>{'code': code};
      final response = await _storePost(ApiConstants.storeCartRemoveCouponEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Place the order via the Store API checkout endpoint.
  /// Returns the order data on success, or null on failure.
  /// Dokan hooks into woocommerce_store_api_checkout_order_processed to
  /// automatically split the order into vendor sub-orders.
  Future<Map<String, dynamic>?> storeCheckout({
    required String paymentMethod,
  }) async {
    try {
      final data = <String, dynamic>{
        'payment_method': paymentMethod,
      };
      debugPrint('[StoreAPI] POST checkout — payment: $paymentMethod');
      final response = await _storePost(ApiConstants.storeCheckoutEndpoint, data);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        debugPrint('[StoreAPI] Checkout SUCCESS: ${response.statusCode}');
        if (body is Map) return Map<String, dynamic>.from(body);
        debugPrint('[StoreAPI] Checkout unexpected response type: ${body.runtimeType}');
      } else {
        debugPrint('[StoreAPI] Checkout FAILED: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[StoreAPI] Checkout exception: $e');
    }
    return null;
  }

  // ─── App Bridge Checkout (mu-plugin) ───

  /// POST /app/v1/prepare-checkout  (JWT-authenticated)
  /// Sends the local cart items to the server, which stores them in a transient
  /// and returns a single-use opaque code for the WebView to consume.
  Future<Map<String, dynamic>> prepareCheckout({
    required List<Map<String, dynamic>> items,
    String? email,
  }) async {
    debugPrint('[AppBridge] prepare-checkout — ${items.length} items');
    final response = await _post(
      ApiConstants.appPrepareCheckoutEndpoint,
      {
        'items': items,
        if (email != null) 'email': email,
      },
      useWcAuth: false,
      requireAuth: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    final body = jsonDecode(response.body);
    final msg = body is Map ? body['message']?.toString() : 'Server error';
    throw Exception(msg ?? 'Failed to prepare checkout (${response.statusCode})');
  }

  /// GET /app/v1/order/{id}?key=xxx  (JWT-authenticated)
  /// Fetches verified order data. The server checks that the order key matches
  /// and that the order belongs to the authenticated user.
  Future<Map<String, dynamic>?> getAppOrder(int orderId, String orderKey) async {
    try {
      final url = '${ApiConstants.appOrderEndpoint}/$orderId?key=${Uri.encodeComponent(orderKey)}';
      debugPrint('[AppBridge] GET order $orderId');
      final response = await _get(url, useWcAuth: false, requireAuth: true);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      debugPrint('[AppBridge] Order fetch failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('[AppBridge] Order fetch exception: $e');
    }
    return null;
  }

  /// Build the enter-checkout WebView URL from a code.
  Uri buildEnterCheckoutUri(String code) {
    return Uri.parse('${ApiConstants.appEnterCheckoutEndpoint}?code=${Uri.encodeComponent(code)}');
  }

  /// Remove all items from the server-side cart (via Store API).
  /// Call before re-syncing local items to avoid duplicates.
  Future<void> clearStoreCart() async {
    try {
      final cart = await getStoreCart();
      if (cart == null) return;
      final items = (cart['items'] as List<dynamic>?) ?? [];
      for (final item in items) {
        final key = item is Map ? item['key']?.toString() : null;
        if (key != null && key.isNotEmpty) {
          debugPrint('[StoreAPI] Removing cart item: $key');
          await removeStoreCartItem(key);
        }
      }
    } catch (e) {
      debugPrint('[StoreAPI] clearCart exception: $e');
    }
  }

  /// Send a POST to the Store API using cart-token / nonce headers.
  Future<http.Response> _storePost(String url, Map<String, dynamic> data) async {
    debugPrint('[StoreAPI] POST $url');
    final response = await client.post(
      Uri.parse(url),
      headers: _getStoreApiHeaders(),
      body: jsonEncode(data),
    );
    debugPrint('[StoreAPI] ← ${response.statusCode}');
    _updateTokensFromResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[StoreAPI] POST FAILED: ${response.statusCode} ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
    }
    return response;
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
