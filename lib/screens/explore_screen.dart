import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/category.dart' as cat_model;
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';

/// Explore tab: a paginated catalog of all products with multi-select
/// category filtering. Filters apply in real time (no page reload) and the
/// grid is responsive across mobile, tablet and desktop viewports.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scroll = ScrollController();

  List<cat_model.Category> _categories = [];
  List<Product> _products = [];
  String _selectedFilter = 'all'; // 'all' | 'services' | 'cat:<id>'

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingCategories = true;
  int _page = 1;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadCategories();
    _loadProducts();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  /// Comma-separated category IDs for the WooCommerce `category` param,
  /// or null for all. The Services option maps to the "services" category.
  String? get _categoryQuery {
    if (_selectedFilter == 'services') {
      final id = _servicesCategoryId;
      if (id != null) return '$id';
      return null;
    }
    if (_selectedFilter.startsWith('cat:')) {
      return _selectedFilter.substring(4);
    }
    return null;
  }

  int? get _servicesCategoryId {
    for (final c in _categories) {
      final name = c.name.toLowerCase();
      final slug = c.slug?.toLowerCase() ?? '';
      if (name.contains('service') || slug.contains('service')) {
        return c.id;
      }
    }
    return null;
  }

  List<Product> _filterExcluded(List<Product> list) => list
      .where((p) => !ApiConstants.isVendorExcluded(id: p.vendorId, name: p.vendorName))
      .toList();

  Future<void> _loadCategories() async {
    try {
      final cats = await _api.getCategories(perPage: 100);
      final filtered = cats.where((c) => c.slug != 'uncategorized').toList();
      if (mounted) setState(() => _categories = filtered);
    } catch (_) {
      // Non-fatal: products still load without category filters.
    }
    if (mounted) setState(() => _loadingCategories = false);
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _page = 1;
    _hasMore = true;
    try {
      var products = await _api.getProducts(page: _page, category: _categoryQuery);
      final filtered = _filterExcluded(products);
      if (mounted) {
        setState(() {
          _products = filtered;
          _loading = false;
          _page++;
          _hasMore = products.length >= ApiConstants.defaultPerPage;
        });
      }
    } catch (e) {
      debugPrint('[Explore] load products failed: $e');
      // If a category filter caused the failure, fall back to unfiltered.
      if (_categoryQuery != null) {
        try {
          final products = await _api.getProducts(page: _page);
          final filtered = _filterExcluded(products);
          if (mounted) {
            setState(() {
              _products = filtered;
              _loading = false;
              _page++;
              _hasMore = products.length >= ApiConstants.defaultPerPage;
            });
          }
          return;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load products. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _api.getProducts(page: _page, category: _categoryQuery);
      final filtered = _filterExcluded(more);
      if (mounted) {
        setState(() {
          _products.addAll(filtered);
          _page++;
          _hasMore = more.length >= ApiConstants.defaultPerPage;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onFilterChanged(String? value) {
    if (value == null) return;
    if (_selectedFilter == value) return;
    setState(() => _selectedFilter = value);
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (_error != null)
              SliverToBoxAdapter(child: _buildError())
            else if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.goldColor),
                ),
              )
            else if (_products.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyProducts(),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= _products.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                                color: AppColors.goldColor, strokeWidth: 2),
                          ),
                        );
                      }
                      return ProductTile(product: _products[index]);
                    },
                    childCount: _products.length + (_hasMore ? 1 : 0),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explore products',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Browse the full ZZmore catalog',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildFilterDropdown(),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    if (_loadingCategories) {
      return Container(
        height: 52,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.sandColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
              color: AppColors.goldColor, strokeWidth: 2),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sandColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFilter,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.inkSoftColor),
          style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All products'),
            ),
            const DropdownMenuItem(
              value: 'services',
              child: Text('Services'),
            ),
            ..._categories.map((c) {
              return DropdownMenuItem(
                value: 'cat:${c.id}',
                child: Text(c.name ?? 'Category'),
              );
            }),
          ],
          onChanged: _onFilterChanged,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.wifi_off,
              size: 48, color: AppColors.goldColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('Could not load products',
              style: TextStyle(color: AppColors.inkColor, fontSize: 15)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadProducts,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined,
              size: 64, color: AppColors.goldColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('No products match these filters',
              style: TextStyle(color: AppColors.inkSoftColor)),
        ],
      ),
    );
  }
}
