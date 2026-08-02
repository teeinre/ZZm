import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/category.dart' as cat_model;
import '../services/api_service.dart';
import '../cache/hive_service.dart';
import '../constants/api_constants.dart';

class ProductsProvider with ChangeNotifier {
  final ApiService apiService;
  final HiveService hiveService;
  List<Product> _products = [];
  List<cat_model.Category> _categories = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = true;
  String? _selectedCategory;
  String? _searchQuery;
  bool _initialized = false;

  ProductsProvider({
    required this.apiService,
    required this.hiveService,
  });

  List<Product> get products => _filterExcluded(_products);
  List<cat_model.Category> get categories => _filterUncategorized(_categories);

  // ── Helpers ──

  /// Remove the WooCommerce default "Uncategorized" category (slug=uncategorized)
  /// from any category list.
  List<cat_model.Category> _filterUncategorized(List<cat_model.Category> cats) {
    return cats.where((c) => c.slug != 'uncategorized').toList();
  }
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  String? get selectedCategory => _selectedCategory;
  bool get initialized => _initialized;

  /// Filters out products from excluded vendor stores (by name OR by ID).
  List<Product> _filterExcluded(List<Product> list) {
    return list.where((p) {
      if (ApiConstants.isVendorExcluded(
          id: p.vendorId, name: p.vendorName)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Returns only products whose vendor matches the given [vendorId].
  /// Used on the vendor profile screen — also runs the exclusion filter
  /// so blocked vendor products never leak through even if ID matches.
  List<Product> productsByVendor(int vendorId) {
    return _filterExcluded(_products)
        .where((p) => p.vendorId == vendorId)
        .toList();
  }

  Future<void> loadCategories({bool force = false}) async {
    if (_categories.isNotEmpty && !force) return;
    _isLoading = true;
    notifyListeners();
    try {
      final cachedCategories = hiveService.getCachedCategories();
      if (cachedCategories.isNotEmpty) {
        _categories = _filterUncategorized(cachedCategories);
        notifyListeners();
      }
      final categories = await apiService.getCategories(perPage: 100);
      _categories = _filterUncategorized(categories);
      await hiveService.cacheCategories(_categories);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      if (_categories.isEmpty) {
        _categories = _filterUncategorized(hiveService.getCachedCategories());
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadProducts({bool refresh = false}) async {
    if (products.isNotEmpty && !refresh) return;

    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      // Keep existing products during refresh to avoid flicker
    }
    _isLoading = true;
    if (_products.isEmpty) {
      notifyListeners();
    }
    try {
      final freshProducts = await apiService.getProducts(
        page: _currentPage,
        category: _selectedCategory,
        search: _searchQuery,
      );
      // Filter out excluded vendor products before storing
      final filtered = _filterExcluded(freshProducts);
      // Check pagination on original count to avoid premature `hasMore = false`
      // when an entire page gets filtered out
      if (_currentPage == 1) {
        _products = filtered;
        await hiveService.cacheProducts(filtered);
      } else {
        _products.addAll(filtered);
      }
      _currentPage++;
      _hasMore = freshProducts.length >= ApiConstants.defaultPerPage;
      _initialized = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      // Only fall back to cache if we haven't loaded anything yet
      if (_products.isEmpty) {
        _products = _filterExcluded(hiveService.getCachedProducts());
        _initialized = true;
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  void setCategory(String? categoryId) {
    _selectedCategory = categoryId;
    loadProducts(refresh: true);
  }

  void setSearchQuery(String? query) {
    _searchQuery = query;
    loadProducts(refresh: true);
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final moreProducts = await apiService.getProducts(
        page: _currentPage,
        category: _selectedCategory,
        search: _searchQuery,
      );
      _products.addAll(_filterExcluded(moreProducts));
      _currentPage++;
      _hasMore = moreProducts.length >= ApiConstants.defaultPerPage;
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
