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
  List<cat_model.Category> get categories =>
      _sortCategories(_categories);

  // ── Helpers ──

  /// True if the given term matches WooCommerce's default "Uncategorized"
  /// term (matches slug AND name, case-insensitive, to work on both
  /// English and localized installs).
  static bool _isUncategorized(cat_model.Category c) {
    final slug = (c.slug ?? '').toLowerCase().trim();
    final name = c.name.toLowerCase().trim();
    if (slug == 'uncategorized') return true;
    if (name == 'uncategorized') return true;
    if (c.id == 1 && slug.isEmpty) return true;
    return false;
  }

  /// Strict alphabetical A→Z sort with "Uncategorized" ALWAYS at the END.
  static List<cat_model.Category> _sortCategories(
      List<cat_model.Category> cats) {
    final sorted = List<cat_model.Category>.from(cats);
    sorted.sort((a, b) {
      final aU = _isUncategorized(a);
      final bU = _isUncategorized(b);
      if (aU && !bU) return 1;
      if (!aU && bU) return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
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
    List<cat_model.Category> cats = [];
    try {
      // ── 1. vendor-api (primary — includes empty, all product types) ─
      cats = await apiService.getAllProductCategories(hideEmpty: false);
      if (cats.isEmpty) {
        cats = await apiService.getCategories(perPage: 100);
      }
      _categories = _sortCategories(cats);
      await hiveService.cacheCategories(_categories);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      if (_categories.isEmpty) {
        final cached = hiveService.getCachedCategories();
        _categories = _sortCategories(cached);
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
    }
    _isLoading = true;
    if (_products.isEmpty) {
      notifyListeners();
    }
    List<Product> freshProducts = [];
    try {
      final catId = _selectedCategory != null
          ? int.tryParse(_selectedCategory!)
          : null;
      final String? search = _searchQuery;
      final bool needsSearch = search != null && search.trim().isNotEmpty;

      // ── Primary path 1: vendor-api.php (works for booking, sub, etc) ──
      if (catId != null && !needsSearch) {
        try {
          freshProducts = await apiService.getProductsByCategory(
            catId,
            page: _currentPage,
            perPage: ApiConstants.defaultPerPage,
          );
        } catch (_) {
          // fall through to wc-rest
        }
      } else if (catId == null && !needsSearch) {
        // "All products" (no category, no search) — vendor-api all-products.
        try {
          freshProducts = await apiService.getAllProducts(
            page: _currentPage,
            perPage: ApiConstants.defaultPerPage,
          );
        } catch (_) {
          // fall through to wc-rest
        }
      }

      // ── Primary path 2: vendor-api.php searchProducts ─────────────
      if (freshProducts.isEmpty && needsSearch) {
        try {
          freshProducts = await apiService.searchProducts(search,
              perPage: ApiConstants.defaultPerPage);
        } catch (_) {
          // fall through
        }
      }

      // ── Fallback path: WC REST /wc/v3/products ─────────────────────
      if (freshProducts.isEmpty) {
        freshProducts = await apiService.getProducts(
          page: _currentPage,
          category: _selectedCategory,
          search: search,
        );
      }

      final filtered = _filterExcluded(freshProducts);
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
      final catId = _selectedCategory != null
          ? int.tryParse(_selectedCategory!)
          : null;
      final String? search = _searchQuery;
      final bool needsSearch = search != null && search.trim().isNotEmpty;

      List<Product> moreProducts = [];
      if (catId != null && !needsSearch) {
        try {
          moreProducts = await apiService.getProductsByCategory(
            catId,
            page: _currentPage,
            perPage: ApiConstants.defaultPerPage,
          );
        } catch (_) {}
      } else if (catId == null && !needsSearch) {
        try {
          moreProducts = await apiService.getAllProducts(
            page: _currentPage,
            perPage: ApiConstants.defaultPerPage,
          );
        } catch (_) {}
      }
      if (moreProducts.isEmpty) {
        moreProducts = await apiService.getProducts(
          page: _currentPage,
          category: _selectedCategory,
          search: search,
        );
      }

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
