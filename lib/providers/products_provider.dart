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

  List<Product> get products => _products;
  List<cat_model.Category> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  String? get selectedCategory => _selectedCategory;
  bool get initialized => _initialized;

  Future<void> loadCategories({bool force = false}) async {
    if (_categories.isNotEmpty && !force) return;
    _isLoading = true;
    notifyListeners();
    try {
      final cachedCategories = hiveService.getCachedCategories();
      if (cachedCategories.isNotEmpty) {
        _categories = cachedCategories;
        notifyListeners();
      }
      final categories = await apiService.getCategories(perPage: 100);
      _categories = categories;
      await hiveService.cacheCategories(categories);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      if (_categories.isEmpty) {
        _categories = hiveService.getCachedCategories();
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
      if (freshProducts.length < ApiConstants.defaultPerPage) {
        _hasMore = false;
      }
      if (_currentPage == 1) {
        _products = freshProducts;
        await hiveService.cacheProducts(freshProducts);
      } else {
        _products.addAll(freshProducts);
      }
      _currentPage++;
      _initialized = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      // Only fall back to cache if we haven't loaded anything yet
      if (_products.isEmpty) {
        _products = hiveService.getCachedProducts();
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
      if (moreProducts.length < ApiConstants.defaultPerPage) {
        _hasMore = false;
      }
      _products.addAll(moreProducts);
      _currentPage++;
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
