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
  final Set<int> _selectedIds = {};
  List<Product> _products = [];

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

  /// Comma-separated category IDs for the WooCommerce `category` param
  /// (supports OR-matching across multiple categories), or null for all.
  String? get _categoryQuery =>
      _selectedIds.isEmpty ? null : _selectedIds.join(',');

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
      final products = await _api.getProducts(page: _page, category: _categoryQuery);
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

  void _toggleCategory(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
    _loadProducts();
  }

  void _clearFilters() {
    if (_selectedIds.isEmpty) return;
    setState(() => _selectedIds.clear());
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
          if (_loadingCategories)
            const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: AppColors.goldColor, strokeWidth: 2),
                ),
              ),
            )
          else
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _filterChip(
                    label: 'All',
                    selected: _selectedIds.isEmpty,
                    onTap: _clearFilters,
                  ),
                  ..._categories.map(
                    (c) => _filterChip(
                      label: c.name ?? '',
                      selected: _selectedIds.contains(c.id),
                      onTap: () => _toggleCategory(c.id),
                    ),
                  ),
                ],
              ),
            ),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedIds.length} ${_selectedIds.length == 1 ? 'filter' : 'filters'} active',
                    style: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.close, color: AppColors.coralColor, size: 18),
                  label: const Text('Reset all',
                      style: TextStyle(
                          color: AppColors.coralColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.goldColor : AppColors.whiteColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.goldColor : AppColors.sandColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, color: AppColors.whiteColor, size: 16),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.whiteColor : AppColors.inkColor,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
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
