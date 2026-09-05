import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../constants/api_constants.dart';
import '../cache/hive_service.dart';

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

  /// NORMALISED helper: reads `sales`, `total_sales`, `net_sales`, `total_net_sales`,
  /// `gross_sales`, `total_gross_sales` — also aggregates from order totals (items in
  /// `_orders` list) if REST/vendor-api both returned empty/zero.
  double get totalSales {
    // 1) direct numeric map keys
    for (final k in const ['sales', 'total_sales', 'net_sales', 'total_net_sales', 'gross_sales', 'total_gross_sales']) {
      final raw = _dashboardStats[k];
      if (raw == null) continue;
      final d = raw is num
          ? raw.toDouble()
          : double.tryParse(raw.toString());
      if (d != null && d > 0) return d;
    }
    // 2) nested totals from vendor-api.php reports.sales_total shape
    final salesObj = _dashboardStats['sales'];
    if (salesObj is Map) {
      for (final k in const ['total', 'net_total', 'gross_total']) {
        final raw = salesObj[k];
        if (raw == null) continue;
        final d = raw is num
            ? raw.toDouble()
            : double.tryParse(raw.toString());
        if (d != null && d > 0) return d;
      }
    }
    // 3) fallback: aggregate order totals from the loaded orders list
    try {
      double sum = 0.0;
      for (final o in _orders) {
        final totals = o['total'] ?? o['order_total'] ?? o['total_amount'];
        if (totals == null) continue;
        final d = totals is num
            ? totals.toDouble()
            : double.tryParse(totals.toString());
        if (d != null) sum += d;
      }
      if (sum > 0) {
        debugPrint('[VendorProvider] totalSales: aggregated \$$sum from orders list (stats were empty)');
        return sum;
      }
    } catch (_) {}
    // 4) zero fallback
    return 0;
  }

  double get totalEarnings {
    for (final k in const ['earnings', 'current_balance', 'total_earnings', 'net_earnings']) {
      final raw = _dashboardStats[k];
      if (raw == null) continue;
      final d = raw is num
          ? raw.toDouble()
          : double.tryParse(raw.toString());
      if (d != null && d > 0) return d;
    }
    // Fallback to balance map if earnings field missing
    final bal = _balance['current_balance'];
    if (bal != null) {
      final d = bal is num ? bal.toDouble() : double.tryParse(bal.toString());
      if (d != null && d > 0) return d;
    }
    return 0;
  }

  int get totalOrders {
    for (final k in const ['orders', 'total_orders', 'order_count']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fallback: sum per-status counts
    int sum = 0;
    for (final k in const ['pending', 'processing', 'on-hold', 'completed', 'cancelled', 'refunded', 'failed']) {
      final v = _dashboardStats[k];
      if (v is int) sum += v;
      if (v is String) sum += int.tryParse(v) ?? 0;
    }
    if (sum > 0) return sum;
    // Ultimate fallback: loaded orders list length
    if (_orders.isNotEmpty) return _orders.length;
    return 0;
  }

  int get pendingOrders {
    for (final k in const ['pending', 'pending_orders', 'on-hold', 'processing']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fallback: count from orders list
    return _orders.where((o) {
      final s = (o['status'] ?? '').toString().replaceAll('wc-', '');
      return s == 'pending' || s == 'on-hold' || s == 'processing';
    }).length;
  }

  int get completedOrders {
    for (final k in const ['completed', 'completed_orders']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fallback: count from orders list
    return _orders.where((o) {
      final s = (o['status'] ?? '').toString().replaceAll('wc-', '');
      return s == 'completed';
    }).length;
  }

  /// Total unique customers — from dashboard stats (vendor-api.php get_reports)
  int get totalCustomers {
    for (final k in const ['customers', 'total_customers', 'customer_count', 'unique_customers']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fallback: unique customer_id from loaded orders list
    final seen = <int>{};
    for (final o in _orders) {
      final cid = o['customer_id'];
      if (cid is int && cid > 0) seen.add(cid);
      if (cid is String) {
        final p = int.tryParse(cid);
        if (p != null && p > 0) seen.add(p);
      }
    }
    return seen.length;
  }

  /// Store pageviews — from dashboard stats (vendor-api.php get_reports)
  int get pageviews {
    for (final k in const ['pageviews', 'store_pageviews', 'views', 'visits']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 0;
  }

  /// Customer engagement — composite score: orders + customers + reviews + pageviews
  /// (vendor-api.php get_reports computes this server-side; fallback is local computation)
  int get customerEngagement {
    for (final k in const ['customer_engagement', 'engagement', 'engagement_score']) {
      final v = _dashboardStats[k];
      if (v is int && v > 0) return v;
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    // Fallback: engagement breakdown nested
    final breakdown = _dashboardStats['engagement_breakdown'];
    if (breakdown is Map) {
      int sum = 0;
      for (final entry in breakdown.values) {
        if (entry is int) sum += entry;
        if (entry is String) sum += int.tryParse(entry) ?? 0;
      }
      if (sum > 0) return sum;
    }
    // Ultimate fallback: local composite
    return totalOrders + totalCustomers + reviewCount + pageviews;
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
    // 1) dashboard stats numeric
    for (final k in const ['reviews', 'total_reviews', 'rating_count', 'review_count']) {
      final r = _dashboardStats[k];
      if (r is int && r > 0) return r;
      if (r is String) {
        final p = int.tryParse(r);
        if (p != null && p > 0) return p;
      }
    }
    // 2) store info rating_count
    final storeCount = _storeInfo?['rating_count'];
    if (storeCount is int && storeCount > 0) return storeCount;
    if (storeCount is String) {
      final p = int.tryParse(storeCount);
      if (p != null && p > 0) return p;
    }
    // 3) fallback: reviews list length
    return _reviews.length;
  }

  double get averageRating {
    // 1) store info (most up-to-date from public store endpoint / Dokan)
    final storeRating = _storeInfo?['rating'];
    if (storeRating is num && storeRating > 0) return storeRating.toDouble();
    if (storeRating is String) {
      final p = double.tryParse(storeRating);
      if (p != null && p > 0) return p;
    }
    // 2) dashboard stats
    for (final k in const ['average_rating', 'rating']) {
      final v = _dashboardStats[k];
      if (v is num && v > 0) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null && p > 0) return p;
      }
    }
    // 3) fallback: average of loaded review list
    if (_reviews.isNotEmpty) {
      double sum = 0;
      int count = 0;
      for (final r in _reviews) {
        final raw = r['rating'] ?? r['review_rating'];
        if (raw == null) continue;
        final d = raw is num
            ? raw.toDouble()
            : double.tryParse(raw.toString());
        if (d != null) {
          sum += d;
          count++;
        }
      }
      if (count > 0) return sum / count;
    }
    return 0.0;
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

  Future<void> loadDashboardStats({bool retryOnEmpty = true}) async {
    _isLoadingStats = true;
    notifyListeners();

    // ── Primary: vendor-api.php bypass ──────────────────────────────
    // Reads sales/orders/products/balance directly from WooCommerce + Dokan
    // and is immune to intermittent REST auth failures and security-plugin
    // blocks that make the REST chain unreliable.
    try {
      final vendorApiData = await _api.getVendorApiReports();
      if (vendorApiData != null && vendorApiData.isNotEmpty) {
        _dashboardStats = Map<String, dynamic>.from(vendorApiData);
        debugPrint('[VendorProvider] Loaded dashboard from vendor-api.php bypass. Keys: ${_dashboardStats.keys.take(10)}');
      }
    } catch (e) {
      debugPrint('[VendorProvider] vendor-api.php reports failed: $e');
      _dashboardStats = {};
    }

    // ── Fallback: Dokan/WC REST chain (WC Analytics → Dokan → aggregate) ──
    if (_dashboardStats.isEmpty ||
        (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null && _dashboardStats['total_sales'] == null)) {
      try {
        final restData = await _api.getVendorReports(vendorId: _vendorId ?? vendorUserId);
        if (restData.isNotEmpty) {
          _dashboardStats = Map<String, dynamic>.from(restData);
          debugPrint('[VendorProvider] Loaded dashboard from Dokan/WC REST chain. Keys: ${_dashboardStats.keys.take(10)}');
        }
      } catch (e) {
        debugPrint('[VendorProvider] Dokan/WC REST reports failed: $e');
      }
    }

    // ── Fallback: Woo Report plugin ──────────────────────────────────
    if (_dashboardStats.isEmpty ||
        (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null && _dashboardStats['total_sales'] == null)) {
      try {
        final wooData = await _api.getWooReportDashboard();
        if (wooData != null && wooData.isNotEmpty) {
          _dashboardStats = Map<String, dynamic>.from(wooData);
          debugPrint('[VendorProvider] Loaded dashboard from Woo Report plugin.');
        }
      } catch (_) {}
    }

    if (_dashboardStats.isEmpty ||
        (_dashboardStats['sales'] == null && _dashboardStats['orders'] == null && _dashboardStats['total_sales'] == null)) {
      try {
        final wooStats = await _api.getWooReportVendorStats();
        if (wooStats != null && wooStats.isNotEmpty) {
          _dashboardStats = Map<String, dynamic>.from(wooStats);
          debugPrint('[VendorProvider] Loaded dashboard from Woo Report vendor stats.');
        }
      } catch (_) {}
    }

    // ── Retry once on empty (defensive for first-login REST race) ────
    final hasMeaningfulStats = totalSales > 0 ||
        totalOrders > 0 ||
        pendingOrders > 0 ||
        completedOrders > 0 ||
        totalProducts > 0;
    if (!hasMeaningfulStats && retryOnEmpty) {
      debugPrint('[VendorProvider] All stats still zero — retrying loadDashboardStats once after 500ms…');
      _isLoadingStats = false;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await loadDashboardStats(retryOnEmpty: false);
      return;
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
    // Only show loading spinner if we have no cached data — avoids
    // masking cache-restored orders while the background refresh runs.
    if (_orders.isEmpty) {
      _isLoadingOrders = true;
      notifyListeners();
    }
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
    // Only show loading spinner if we have no cached data.
    if (_vendorProducts.isEmpty) {
      _isLoadingProducts = true;
      notifyListeners();
    }
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
        'stock_quantity': p.manageStock ? p.stockQuantity.toString() : null,
        'manage_stock': p.manageStock,
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
          'stock_quantity': p['stock_quantity']?.toString(),
          'manage_stock': p['manage_stock'] == true ||
              (p['stock_quantity'] != null &&
                  p['stock_quantity'].toString().isNotEmpty),
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
    // Fallback via vendor-api.php balance (returns withdrawals array)
    if (_withdrawals.isEmpty) {
      try {
        final apiBalance = await _api.getVendorApiBalance();
        if (apiBalance != null && apiBalance.containsKey('withdrawals')) {
          final wList = apiBalance['withdrawals'];
          if (wList is List && wList.isNotEmpty) {
            _withdrawals = wList.map((w) => Map<String, dynamic>.from(w)).toList();
            debugPrint('[VendorProvider] Loaded withdrawals from vendor-api.php bypass (${_withdrawals.length}).');
          }
        }
      } catch (_) {}
    }
    _isLoadingWithdrawals = false;
    notifyListeners();
    _persistDashboard();
  }

  /// Returns the last withdrawal error for UI display, or null if last attempt succeeded.
  String? get lastWithdrawalError => _lastWithdrawalError;
  String? _lastWithdrawalError;

  Future<bool> requestWithdrawal(double amount, String method) async {
    _lastWithdrawalError = null;
    final result = await _api.requestWithdrawal(amount, method);
    if (!result) {
      // Attempt to pull any vendor-api.php surfaced errors from debug log buffer
      // — for now set a generic hint that the user can compare with the
      // server-side request payload in debugPrint.
      _lastWithdrawalError = 'Withdrawal failed. Please check the amount is within your available balance '
          'and that your withdrawal method (${method}) is configured in the vendor store settings.';
    }
    if (result) {
      await loadBalance();
      await loadWithdrawals();
    }
    notifyListeners();
    return result;
  }

  // ─── Coupons ───

  Future<void> loadCoupons() async {
    _isLoadingCoupons = true;
    notifyListeners();
    try {
      _coupons = await _api.getVendorCoupons();
    } catch (_) {}
    // Fallback to vendor-api.php
    if (_coupons.isEmpty) {
      try {
        _coupons = await _api.getVendorApiCoupons();
        debugPrint('[VendorProvider] Loaded coupons from vendor-api.php bypass (${_coupons.length}).');
      } catch (_) {}
    }
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
      _reviews = await _api.getVendorReviews(vendorUserId: vendorUserId);
      debugPrint('[VendorProvider] Loaded ${_reviews.length} reviews (vendor-scoped)');
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
  /// If [vendorId] is provided it overrides the instance `_vendorId`,
  /// allowing cache restore before the first `loadStoreInfo` call.
  /// Returns `true` if cached data was available and restored.
  bool restoreFromCache({int? vendorId}) {
    final vid = vendorId ?? _vendorId;
    if (_hive == null || vid == null) return false;
    // Keep the resolved ID so subsequent network writes go to the same key.
    if (_vendorId == null) _vendorId = vid;
    final cached = _hive!.getCachedVendorDashboard(vid);
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
