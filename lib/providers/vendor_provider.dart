import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class VendorProvider with ChangeNotifier {
  final ApiService _api;
  
  /// Public accessor for the shared (JWT-authenticated) ApiService.
  ApiService get apiService => _api;

  VendorProvider({ApiService? apiService}) : _api = apiService ?? ApiService();

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

  // Computed — handles both Dokan v1 field names (e.g. 'sales', 'orders')
  // and WordPress REST field names (e.g. 'total_sales', 'total_orders').
  double get totalSales {
    final s = (_dashboardStats['sales'] ?? _dashboardStats['total_sales'] ?? '0').toString();
    return double.tryParse(s) ?? 0;
  }

  double get totalEarnings {
    final e = (_dashboardStats['earnings'] ?? _dashboardStats['total_earnings'] ?? '0').toString();
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

  double get currentBalance {
    final b = _balance['current_balance']?.toString() ?? '0';
    return double.tryParse(b) ?? 0;
  }

  // ─── Store Info ───

  Future<void> loadStoreInfo(int storeId) async {
    _isLoadingStore = true;
    notifyListeners();
    try {
      _storeInfo = await _api.getDokanStore(storeId);
      if (_storeInfo != null && _storeInfo!['id'] != null) {
        _vendorId = _storeInfo!['id'] is int
            ? _storeInfo!['id'] as int
            : int.tryParse(_storeInfo!['id']?.toString() ?? '');
      }
    } catch (_) {}
    _isLoadingStore = false;
    notifyListeners();
  }

  // ─── Dashboard ───

  Future<void> loadDashboardStats() async {
    _isLoadingStats = true;
    notifyListeners();
    try {
      _dashboardStats = await _api.getVendorReports();
    } catch (_) {}
    _isLoadingStats = false;
    notifyListeners();
  }

  Future<void> loadBalance() async {
    _isLoadingBalance = true;
    notifyListeners();
    try {
      _balance = await _api.getVendorBalance();
    } catch (_) {}
    _isLoadingBalance = false;
    notifyListeners();
  }

  Future<void> loadDashboard() async {
    await Future.wait([loadDashboardStats(), loadBalance(), loadAnnouncements()]);
  }

  // ─── Orders ───

  Future<void> loadOrders({String? status}) async {
    _isLoadingOrders = true;
    notifyListeners();
    try {
      _orders = await _api.getVendorOrders(status: status);
    } catch (_) {}
    _isLoadingOrders = false;
    notifyListeners();
  }

  Future<bool> updateOrderStatus(int orderId, String status) async {
    final result = await _api.updateOrderStatus(orderId, status);
    if (result) {
      await loadOrders();
      await loadDashboardStats();
    }
    return result;
  }

  Future<bool> addOrderNote(int orderId, String note, {bool customerNote = false}) async {
    return await _api.addOrderNote(orderId, note, customerNote: customerNote);
  }

  // ─── Products ───

  Future<void> loadVendorProducts({int vendorId = 0}) async {
    _isLoadingProducts = true;
    notifyListeners();
    try {
      final products = await _api.getVendorProducts(vendorId, perPage: 100);
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
    } catch (_) {}
    _isLoadingProducts = false;
    notifyListeners();
  }

  Future<bool> deleteVendorProduct(int id) async {
    final result = await _api.deleteProduct(id);
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
  }

  Future<bool> deleteCouponById(int id) async {
    final result = await _api.deleteCoupon(id);
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
    } catch (_) {}
    _isLoadingReviews = false;
    notifyListeners();
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
  }

  /// Clear all vendor data (for logout / session isolation).
  void clearAll() {
    _storeInfo = null;
    _vendorId = null;
    _dashboardStats = {};
    _balance = {};
    _orders = [];
    _vendorProducts = [];
    _withdrawals = [];
    _coupons = [];
    _reviews = [];
    _announcements = [];
    notifyListeners();
  }
}
