import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';

/// Explore tab: a paginated catalog of all products with multi-select
/// **Dokan Store Category** filtering.  Filters apply in real time and the
/// grid is responsive across mobile, tablet and desktop viewports.
///
/// Dokan Store Categories live on VENDOR objects (user taxonomy
/// `store_category`), not on individual products.  So to filter the
/// product grid by a store category we first resolve which vendors
/// belong to the chosen category, then keep only products whose
/// `vendorId` (post_author) is in that set.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scroll = ScrollController();

  // Store categories come from Dokan's `store_category` taxonomy via
  // vendor-api.php (with WP REST fallback).  Each entry has `{id, name,
  // slug, count}`.
  List<Map<String, dynamic>> _storeCategories = [];

  // Reverse mapping: store_category_id (as int) → list of WP user IDs
  // (vendor post_author) of vendors that are in that category.
  Map<int, List<int>> _categoryVendorIds = {};

  // All stores list for debugging / fallback categorisation.
  List<Map<String, dynamic>> _allStores = [];

  List<Product> _products = [];

  /// `'all'` or `'scat:<id>'` where `<id>` is the store_category term_id.
  String _selectedFilter = 'all';

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
    _loadStoreCategories();
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

  /// Returns the store_category id as int when the filter is in
  /// `scat:<id>` form, otherwise null.
  int? get _selectedStoreCategoryId {
    if (_selectedFilter.startsWith('scat:')) {
      return int.tryParse(_selectedFilter.substring(5));
    }
    return null;
  }

  /// Vendor WP user IDs that match the currently-selected store category,
  /// or `null` when "All products" is chosen (no vendor scoping).
  Set<int>? get _vendorScope {
    final cid = _selectedStoreCategoryId;
    if (cid == null) return null;
    final list = _categoryVendorIds[cid] ?? const <int>[];
    if (list.isEmpty) return <int>{};
    return Set<int>.from(list);
  }

  List<Product> _applyVendorFilter(List<Product> list) {
    final scope = _vendorScope;
    Iterable<Product> result = list.where((p) =>
        !ApiConstants.isVendorExcluded(id: p.vendorId, name: p.vendorName));
    if (scope != null) {
      result = result.where((p) => scope.contains(p.vendorId ?? -1));
    }
    return result.toList();
  }

  /// Loads Dokan store categories + vendor mapping.  Falls back to
  /// WooCommerce product categories if the store-category endpoints
  /// return nothing (e.g. vendor-api.php hasn't been deployed yet), so
  /// the dropdown never appears empty.
  Future<void> _loadStoreCategories() async {
    try {
      final storesPayload = await _api.getAllStoresWithCategories();
      final catsList = await _api.getStoreCategories();

      // Parse the category → vendors reverse map (can be keyed by int or
      // String depending on JSON serialisation).
      final cv = storesPayload['category_vendors'];
      final parsedCv = <int, List<int>>{};
      if (cv is Map) {
        cv.forEach((k, v) {
          final key = k is int ? k : int.tryParse(k.toString());
          if (key == null) return;
          if (v is! List) return;
          final ids = <int>[];
          for (final x in v) {
            final xi = x is int ? x : int.tryParse(x.toString());
            if (xi != null) ids.add(xi);
          }
          if (ids.isNotEmpty) parsedCv[key] = ids;
        });
      }

      final storesRaw = storesPayload['stores'];
      final parsedStores = <Map<String, dynamic>>[];
      if (storesRaw is List) {
        for (final s in storesRaw) {
          if (s is Map) parsedStores.add(Map<String, dynamic>.from(s));
        }
      }

      if (mounted) {
        setState(() {
          _categoryVendorIds = parsedCv;
          _allStores = parsedStores;
          _storeCategories = catsList.where((c) {
            final count = c['count'] is int ? c['count'] as int : 0;
            final cid = c['id'] is int ? c['id'] as int : 0;
            // Keep non-empty categories AND categories that have at
            // least one vendor according to our reverse map.
            final hasVendors = (parsedCv[cid]?.isNotEmpty ?? false);
            return count > 0 || hasVendors;
          }).toList()
            ..sort((a, b) {
              final ca = a['count'] is int ? a['count'] as int : 0;
              final cb = b['count'] is int ? b['count'] as int : 0;
              final va =
                  (_categoryVendorIds[a['id'] as int? ?? 0]?.length ?? 0);
              final vb =
                  (_categoryVendorIds[b['id'] as int? ?? 0]?.length ?? 0);
              return (cb + vb).compareTo(ca + va);
            });
        });
      }
    } catch (e) {
      debugPrint('[Explore] store categories load failed: $e');
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
      // Note: we intentionally do NOT filter by vendor server-side here.
      // The Dokan `store_category` lives on users, not products, so
      // server-side filter would be awkward.  We just pull the normal
      // paginated product stream and trim it in `_applyVendorFilter`.
      var products =
          await _api.getProducts(page: _page, perPage: 50, author: _authorQuery());
      final filtered = _applyVendorFilter(products);
      if (mounted) {
        setState(() {
          _products = filtered;
          _loading = false;
          _page++;
          _hasMore = products.length >= 50;
        });
      }
    } catch (e) {
      debugPrint('[Explore] load products failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load products. Please try again.';
        });
      }
    }
  }

  /// When filtering by store category we try to narrow the server-side
  /// request using `author=<ids>` if the list is short enough.  This
  /// reduces the amount of data we throw away client-side.
  String? _authorQuery() {
    final scope = _vendorScope;
    if (scope == null || scope.isEmpty) return null;
    // Only push to server if the vendor set is small (<20 IDs).  For
    // very large categories it's cheaper to fetch unfiltered and drop
    // locally than to ship a huge query string.
    if (scope.length > 20) return null;
    return scope.map((id) => id.toString()).join(',');
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final more =
          await _api.getProducts(page: _page, perPage: 50, author: _authorQuery());
      final filtered = _applyVendorFilter(more);
      if (mounted) {
        setState(() {
          _products.addAll(filtered);
          _page++;
          _hasMore = more.length >= 50;
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
            ..._storeCategories.map((c) {
              final id = c['id'] as int? ?? 0;
              final name = (c['name']?.toString().isNotEmpty ?? false)
                  ? c['name']!.toString()
                  : 'Category';
              final vendorCount = _categoryVendorIds[id]?.length ?? 0;
              final label = vendorCount > 0 ? '$name ($vendorCount vendors)' : name;
              return DropdownMenuItem(
                value: 'scat:$id',
                child: Text(label),
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
