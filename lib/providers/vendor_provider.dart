import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../constants/api_constants.dart';

class VendorProvider with ChangeNotifier {
  final ApiService _api;
  final HiveService? _hive;
  bool _dashboardLoaded = false;
  
  /// Public accessor for the shared (JWT-authenticated) ApiService.
  ApiService get apiService => _api;

  /// WordPress user ID for the currently logged-in vendor.
  /// Set by the dashboard from AuthProvider; used as fallback for
  /// product filtering via the reliable post_author parameter.
  int? _wpUserId;

  VendorProvider({ApiService? apiService, HiveService? hiveService})
      : _api = apiService ?? ApiService(),
        _hive = hiveService;

  // Store info
  Map<String, dynamic>? _storeInfo;
  int? _vendorId;
  bool _isLoadingStore = false;

  // Dashboard stats
  Map<String, dynamic> _dashboardStats = {};
  bool _isLoadingStats = false;

  // Balance
  Map<String, dynamic> _balance = {};
  bool _isLoadingBalance = false;

  // Orders
  List<Map<String, dynamic>> _orders = [];
  bool _isLoadingOrders = false;

  // Products
  List<Map<String, dynamic>> _vendorProducts = [];
  bool _isLoadingProducts = false;

  // Withdrawals
  List<Map<String, dynamic>> _withdrawals = [];
  bool _isLoadingWithdrawals = false;

  // Coupons
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoadingCoupons = false;

  // Reviews
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoadingReviews = false;

  // Announcements
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = false;

  // Getters
  Map<String, dynamic>? get storeInfo => _storeInfo;
  int? get vendorId => _vendorId;
  bool get isLoadingStore => _isLoadingStore;
  bool get hasStoreInfo => _storeInfo != null && _vendorId != null && _vendorId! > 0;
  Map<String, dynamic> get dashboardStats => _dashboardStats;
  bool get isLoadingStats => _isLoadingStats;
  Map<String, dynamic> get balance => _balance;
  bool get isLoadingBalance => _isLoadingBalance;
  List<Map<String, dynamic>> get orders => _orders;
  bool get isLoadingOrders => _isLoadingOrders;
  List<Map<String, dynamic>> get vendorProducts => _vendorProducts;
  bool get isLoadingProducts => _isLoadingProducts;
  List<Map<String, dynamic>> get withdrawals => _withdrawals;
  bool get isLoadingWithdrawals => _isLoadingWithdrawals;
  List<Map<String, dynamic>> get coupons => _coupons;
  bool get isLoadingCoupons => _isLoadingCoupons;
  List<Map<String, dynamic>> get reviews => _reviews;
  bool get isLoadingReviews => _isLoadingReviews;
  List<Map<String, dynamic>> get announcements => _announcements;
  bool get isLoadingAnnouncements => _isLoadingAnnouncements;

  List<Map<String, dynamic>> _vendors = [];

  List<Map<String, dynamic>> get filteredVendors {
    return _vendors.where((v) {
      final id = v['id'] is int ? v['id'] as int : int.tryParse(v['id']?.toString() ?? '');
      final name = v['store_name']?.toString() ?? v['name']?.toString() ?? '';
      return !ApiConstants.isVendorExcluded(id: id, name: name);
    }).toList().cast<Map<String, dynamic>>();
  }

  // Error tracking
  String? _dashboardError;
  String? get dashboardError => _dashboardError;

  // Computed — handles both Dokan v1 field names (e.g. 'sales', 'orders')
  // and WordPress REST field names (e.g. 'total_sales', 'total_orders').

  /// Vendor's WordPress user ID — extracted from store info.
  /// Falls back to the injected WP user ID (from AuthProvider).
  /// Used to reliably filter products/orders by post_author.
  int? get vendorUserId {
    // First try store info (bridge returns user_id)
    if (_storeInfo != null) {
      final uid = _storeInfo!['user_id'];
      if (uid is int && uid > 0) return uid;
      if (uid is String) {
        final parsed = int.tryParse(uid);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fall back to injected WP user ID (from AuthProvider/JWT)
    return _wpUserId;
  }

  /// Injects the WordPress user ID from the auth token.
  /// Call this from the dashboard with auth.user?.id.
  void setWordPressUserId(int? id) {
    _wpUserId = id;
  }

  double get totalSales {
    final s = (_dashboardStats['sales'] ?? _dashboardStats['total_sales'] ?? '0').toString();
    return double.tryParse(s) ?? 0;
  }

  double get totalEarnings {
    final e = (_dashboardStats['earnings'] ?? _dashboardStats['current_balance'] ?? _dashboardStats['total_earnings'] ?? '0').toString();
    return double.tryParse(e) ?? 0;
  }

  int get totalOrders {
    final v = _dashboardStats['orders'] ?? _dashboardStats['total_orders'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  int get pendingOrders {
    final v = _dashboardStats['pending'] ?? _dashboardStats['pending_orders'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  int get completedOrders {
    final v = _dashboardStats['completed'] ?? _dashboardStats['completed_orders'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// Total products count — from dashboard stats if available, else from loaded products list.
  int get totalProducts {
    // Try dashboard stats first (more accurate from server)
    final statsProducts = _dashboardStats['products'];
    if (statsProducts is int && statsProducts > 0) return statsProducts;
    if (statsProducts is String) {
      final parsed = int.tryParse(statsProducts);
      if (parsed != null && parsed > 0) return parsed;
    }
    // Fall back to loaded vendor products list
    return _vendorProducts.length;
  }

  /// ── Inventory levels (computed from loaded vendor products) ──
  int get inStockProducts {
    int count = 0;
    for (final p in _vendorProducts) {
      final s = p['stock_status']?.toString();
      if (s == 'instock' || s == null) count++;
    }
    return count;
  }

  int get outOfStockProducts => totalProducts - inStockProducts;

  int get lowStockProducts {
    int count = 0;
    for (final p in _vendorProducts) {
      final q = int.tryParse(p['stock_quantity']?.toString() ?? '');
      if (q != null && q > 0 && q <= 5) count++;
    }
    return count;
  }

  /// ── Engagement / customer statistics ──
  int get reviewCount {
    // Try dashboard stats first, else fallback to reviews list
    final r = _dashboardStats['reviews'] ?? _dashboardStats['total_reviews'];
    if (r is int) return r;
    if (r is String) return int.tryParse(r) ?? _reviews.length;
    return _reviews.length;
  }

  double get averageRating {
    final v = _storeInfo?['rating'] ?? _dashboardStats['average_rating'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  /// ── Performance report helpers ──
  double get completedOrderRate {
    if (totalOrders <= 0) return 0.0;
    return completedOrders / totalOrders;
  }

  double get averageOrderValue {
    if (totalOrders <= 0) return 0.0;
    return totalSales / totalOrders;
  }

  /// ── Withdrawal summary ──
  double get withdrawnTotal {
    double sum = 0.0;
    for (final w in _withdrawals) {
      final amount = double.tryParse(
          (w['amount'] ?? w['amount_display'] ?? '0').toString());
      if (amount != null) sum += amount;
    }
    return sum;
  }

  double get currentBalance {
    final b = _balance['current_balance']?.toString() ?? '0';
    return double.tryParse(b) ?? 0;
  }

  // ─── Store Info ───

  Future<void> loadStoreInfo(int storeId) async {
    _isLoadingStore = true;
    _dashboardError = null;
    notifyListeners();
    try {
      // Primary: use the reliable vendor bridge (reads from Dokan's internal PHP objects)
      _storeInfo = await _api.getVendorBridgeStore();

      // Fallback: use legacy Dokan REST API if bridge is unavailable
      if (_storeInfo == null) {
        debugPrint('[VendorProvider] Bridge unavailable — falling back to legacy Dokan REST API.');
        _storeInfo = await _api.getDokanStore(storeId);
      }

      // Ultimate fallback: vendor-api.php bypass
      if (_storeInfo == null) {
        debugPrint('[VendorProvider] Dokan REST unavailable — falling back to vendor-api.php bypass.');
        _storeInfo = await _api.getVendorApiStore();
      }

      if (_storeInfo != null && _storeInfo!['id'] != null) {
        _vendorId = _storeInfo!['id'] is int
            ? _storeInfo!['id'] as int
            : int.tryParse(_storeInfo!['id']?.toString() ?? '');
      } else {
        _dashboardError = 'Could not load store information. Please try again.';
      }
    } catch (e) {
      _dashboardError = 'Failed to connect to server. Check your connection.';
    }
    _isLoadingStore = false;
    notifyListeners();
    _persistDashboard();
  }

  // ─── Dashboard ───

  Future<void> loadDashboardStats() async {
    _isLoadingStats = true;
    notifyListeners();
    try {
      _dashboardStats = await _api.getVendorReports();
    } catch (_) {
      _dashboardStats = {};
    }

    // Fallback chain: Woo Report → vendor-api.php (bypasses REST blockage)
    if (_dashboardStats.isEmpty || (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null)) {
      try {
        final wooData = await _api.getWooReportDashboard();
        if (wooData != null && wooData.isNotEmpty) {
          _dashboardStats = wooData;
          debugPrint('[VendorProvider] Loaded dashboard from Woo Report plugin.');
        }
      } catch (_) {}
    }

    if (_dashboardStats.isEmpty || (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null)) {
      try {
        final wooStats = await _api.getWooReportVendorStats();
        if (wooStats != null && wooStats.isNotEmpty) {
          _dashboardStats = wooStats;
          debugPrint('[VendorProvider] Loaded dashboard from Woo Report vendor stats.');
        }
      } catch (_) {}
    }

    // Ultimate fallback: vendor-api.php (bypasses REST entirely)
    if (_dashboardStats.isEmpty || (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null)) {
      try {
        final vendorApiData = await _api.getVendorApiReports();
        if (vendorApiData != null && vendorApiData.isNotEmpty) {
          _dashboardStats = vendorApiData;
          debugPrint('[VendorProvider] Loaded dashboard from vendor-api.php bypass.');
        }
      } catch (_) {}
    }

    _isLoadingStats = false;
    notifyListeners();
  }

  Future<void> loadBalance() async {
    _isLoadingBalance = true;
    notifyListeners();
    try {
      _balance = await _api.getVendorBalance();
    } catch (_) {}
    // Fallback to vendor-api.php
    if (_balance.isEmpty) {
      try {
        final apiBalance = await _api.getVendorApiBalance();
        if (apiBalance != null && apiBalance.isNotEmpty) {
          _balance = apiBalance;
          debugPrint('[VendorProvider] Loaded balance from vendor-api.php bypass.');
        }
      } catch (_) {}
    }
    _isLoadingBalance = false;
    notifyListeners();
  }

  Future<void> loadDashboard() async {
    await Future.wait([loadDashboardStats(), loadBalance(), loadAnnouncements()]);
    _persistDashboard();
  }

  // ─── Orders ───

  Future<void> loadOrders({String? status}) async {
    _isLoadingOrders = true;
    notifyListeners();
    try {
      _orders = await _api.getVendorOrders(
        status: status,
        vendorId: _vendorId ?? vendorUserId,
      );
    } catch (_) {}

    // Fallback to vendor-api.php
    if (_orders.isEmpty) {
      try {
        _orders = await _api.getVendorApiOrders(status: status);
        debugPrint('[VendorProvider] Loaded orders from vendor-api.php bypass (${_orders.length}).');
      } catch (_) {}
    }

    _isLoadingOrders = false;
    notifyListeners();
    _persistDashboard();
  }

  Future<bool> updateOrderStatus(int orderId, String status) async {
    final result = await _api.updateDokanOrder(orderId, {'status': status});
    if (result) {
      await loadOrders();
      await loadDashboardStats();
    }
    return result;
  }

  Future<bool> addOrderNote(int orderId, String note, {bool customerNote = false}) async {
    return await _api.addDokanOrderNote(orderId, note, customerNote: customerNote);
  }

  // ─── Products ───

  Future<void> loadVendorProducts({int vendorId = 0}) async {
    final effectiveId = vendorId > 0 ? vendorId : (_vendorId ?? 0);
    if (effectiveId <= 0) {
      debugPrint('[VendorProvider] Cannot load products — no vendor ID available.');
      _isLoadingProducts = false;
      notifyListeners();
      return;
    }
    _isLoadingProducts = true;
    notifyListeners();
    try {
      final products = await _api.getVendorProducts(effectiveId,
        perPage: 100,
        authorUserId: vendorUserId, // reliable post_author filter
      );
      _vendorProducts = products.map((p) => {
        'id': p.id,
        'name': p.name,
        'price': p.price,
        'regular_price': p.regularPrice,
        'stock_status': p.inStock ? 'instock' : 'outofstock',
        'stock_quantity': p.stockQuantity.toString(),
        'status': 'publish',
        'images': p.images,
        'categories': p.categories,
        'on_sale': p.onSale,
      }).toList();
    } catch (e) {
      debugPrint('[VendorProvider] loadVendorProducts error: $e');
    }

    // Fallback to vendor-api.php
    if (_vendorProducts.isEmpty) {
      try {
        final apiProducts = await _api.getVendorApiProducts(perPage: 100);
        _vendorProducts = apiProducts.map((p) => {
          'id': int.tryParse(p['id']?.toString() ?? '') ?? 0,
          'name': p['name']?.toString() ?? '',
          'price': p['price']?.toString() ?? '',
          'regular_price': p['regular_price']?.toString() ?? '',
          'stock_status': p['stock_status']?.toString() ?? 'instock',
          'stock_quantity': p['stock_quantity']?.toString() ?? '0',
          'status': p['status']?.toString() ?? 'publish',
          'images': (p['images'] as List<dynamic>?)?.map((i) => Map<String, dynamic>.from(i)).toList() ?? [],
          'categories': (p['categories'] as List<dynamic>?)?.map((c) => Map<String, dynamic>.from(c)).toList() ?? [],
          'on_sale': p['on_sale'] == true,
        }).toList();
        debugPrint('[VendorProvider] Loaded ${_vendorProducts.length} products from vendor-api.php bypass.');
      } catch (_) {}
    }
    _isLoadingProducts = false;
    notifyListeners();
    _persistDashboard();
  }

  Future<bool> deleteVendorProduct(int id) async {
    final result = await _api.deleteDokanProduct(id);
    if (result) {
      _vendorProducts.removeWhere((p) => p['id'] == id);
      notifyListeners();
    }
    return result;
  }

  // ─── Withdrawals ───

  Future<void> loadWithdrawals() async {
    _isLoadingWithdrawals = true;
    notifyListeners();
    try {
      _withdrawals = await _api.getVendorWithdrawals();
    } catch (_) {}
    _isLoadingWithdrawals = false;
    notifyListeners();
    _persistDashboard();
  }

  Future<bool> requestWithdrawal(double amount, String method) async {
    final result = await _api.requestWithdrawal(amount, method);
    if (result) {
      await loadBalance();
      await loadWithdrawals();
    }
    return result;
  }

  // ─── Coupons ───

  Future<void> loadCoupons() async {
    _isLoadingCoupons = true;
    notifyListeners();
    try {
      _coupons = await _api.getVendorCoupons();
    } catch (_) {}
    _isLoadingCoupons = false;
    notifyListeners();
    _persistDashboard();
  }

  Future<bool> deleteCouponById(int id) async {
    final result = await _api.deleteDokanCoupon(id);
    if (result) {
      _coupons.removeWhere((c) => c['id'] == id);
      notifyListeners();
    }
    return result;
  }

  // ─── Reviews ───

  Future<void> loadReviews() async {
    _isLoadingReviews = true;
    notifyListeners();
    try {
      _reviews = await _api.getVendorReviews();
      debugPrint('[VendorProvider] Loaded ${_reviews.length} reviews');
    } catch (e) {
      debugPrint('[VendorProvider] loadReviews error: $e');
    }
    _isLoadingReviews = false;
    notifyListeners();
    _persistDashboard();
  }

  // ─── Announcements ───

  Future<void> loadAnnouncements() async {
    _isLoadingAnnouncements = true;
    notifyListeners();
    try {
      _announcements = await _api.getVendorAnnouncements();
    } catch (_) {}
    _isLoadingAnnouncements = false;
    notifyListeners();
    _persistDashboard();
  }

  /// Clear all vendor data (for logout / session isolation).
  void clearAll() {
    _storeInfo = null;
    _vendorId = null;
    _dashboardStats = {};
    _balance = {};
    _orders.clear();
    _vendorProducts.clear();
    _withdrawals.clear();
    _coupons.clear();
    _reviews.clear();
    _announcements.clear();
    _dashboardLoaded = false;
    notifyListeners();
  }

  // ── Hive Persistence ──────────────────────────────────────────────────────

  /// Serialise all dashboard data into a single map for caching.
  Map<String, dynamic> _serializeDashboard() {
    return {
      'store_info': _storeInfo,
      'vendor_id': _vendorId,
      'dashboard_stats': _dashboardStats,
      'balance': _balance,
      'orders': _orders,
      'vendor_products': _vendorProducts,
      'withdrawals': _withdrawals,
      'coupons': _coupons,
      'reviews': _reviews,
      'announcements': _announcements,
      'saved_at': DateTime.now().toIso8601String(),
    };
  }

  /// Persist current dashboard state to Hive.
  Future<void> _persistDashboard() async {
    if (_hive == null || _vendorId == null) return;
    await _hive!.saveVendorDashboard(_vendorId!, _serializeDashboard());
  }

  /// Restore dashboard state from Hive (cache-first, no network).
  /// Returns `true` if cached data was available and restored.
  bool _restoreFromCache() {
    if (_hive == null || _vendorId == null) return false;
    final cached = _hive!.getCachedVendorDashboard(_vendorId!);
    if (cached == null) return false;

    _storeInfo = cached['store_info'] is Map
        ? Map<String, dynamic>.from(cached['store_info'])
        : null;
    _dashboardStats = cached['dashboard_stats'] is Map
        ? Map<String, dynamic>.from(cached['dashboard_stats'])
        : {};
    _balance = cached['balance'] is Map
        ? Map<String, dynamic>.from(cached['balance'])
        : {};
    _orders = (cached['orders'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _vendorProducts = (cached['vendor_products'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _withdrawals = (cached['withdrawals'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _coupons = (cached['coupons'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _reviews = (cached['reviews'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _announcements = (cached['announcements'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    _dashboardLoaded = true;
    notifyListeners();
    return true;
  }
}
