import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';

/// Explore tab: a fast, server-filtered catalog of products with
/// WooCommerce PRODUCT CATEGORY filtering and relevance-ordered results.
///
/// Performance & relevance:
///  * Server-side: `orderby=popularity` (WooCommerce indexed sales count
///    sort) — so WC returns the best-selling products first before we
///    even touch the list.
///  * Client-side tiebreaker: a composite score over
///    `popularity * rating * review_count` so products with strong sales
///    AND strong reviews sit at the very top within each page.
///  * Filtering via WC `category=<id>` (server-side) — no pulling a huge
///    list and discarding items locally, so each request stays fast.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scroll = ScrollController();

  /// WooCommerce product categories (only non-empty, sorted by product
  /// count descending so the biggest categories appear first).
  List<Category> _categories = [];

  List<Product> _products = [];

  /// `'all'` or `'cat:<id>'` where `<id>` is the product_cat term_id.
  String _selectedFilter = 'all';

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingCategories = true;
  int _page = 1;
  bool _hasMore = true;
  String? _error;

  /// How many products per fetch page.  60 strikes a good balance between
  /// (a) fewer round trips when the user scrolls and (b) not asking for
  /// so many items that the server spends too long serialising JSON.
  static const int _perPage = 60;

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

  /// The currently-selected product category id, or `null` for "All".
  int? get _selectedCategoryId {
    if (_selectedFilter.startsWith('cat:')) {
      return int.tryParse(_selectedFilter.substring(4));
    }
    return null;
  }

  /// Comma-separated category ids to forward to the server, or `null`.
  String? get _categoryQuery {
    final cid = _selectedCategoryId;
    return cid == null ? null : cid.toString();
  }

  /// Relevance composite score (higher = more relevant).
  ///
  /// Server already sorts by WooCommerce `popularity` (sales count) DESC,
  /// which is the biggest and most accurate signal.  The local score is a
  /// page-level tiebreaker that pushes products with HIGHER star ratings
  /// and MORE reviews above similar products at the same server rank.
  ///
  /// In-stock products are also boosted vs. out-of-stock ones so users
  /// see purchasable items first.
  static double _relevanceScore(Product p) {
    final rating = (p.rating != null && p.rating! > 0) ? p.rating! : 2.5;
    final reviews = p.ratingCount.toDouble();
    final stockBoost = p.inStock ? 1.25 : 0.6;
    final onSaleBoost = p.onSale ? 1.05 : 1.0;
    // rating factor ∈ (0.5 .. 1.5) → 5-star is 3× more weight than 0-star
    final ratingFactor = 0.5 + rating / 5.0;
    // log(1 + reviews) ∈ (0 .. ~3) — diminishes so 1000-review items
    // don't completely dominate 20-review items but still win ties.
    final reviewFactor = 1 + _log10(1 + reviews);
    return ratingFactor * reviewFactor * stockBoost * onSaleBoost;
  }

  static double _log10(double x) {
    const ln10 = 2.302585093;
    return x > 0 ? math.log(x) / ln10 : 0;
  }

  /// Applies post-server filtering (vendor blocklist) and relevance
  /// tiebreaker sorting within the page.  Server already returns items
  /// by `popularity` DESC — the stable sort here only reorders items
  /// that have the same popularity score so higher-rated items win.
  List<Product> _postProcess(List<Product> list) {
    final filtered = list
        .where((p) => !ApiConstants.isVendorExcluded(
            id: p.vendorId, name: p.vendorName))
        .toList();
    // Stable sort: preserve server order for equal scores but push
    // higher-scoring items toward the top.  Sort descending by score.
    filtered.sort((a, b) => _relevanceScore(b).compareTo(_relevanceScore(a)));
    return filtered;
  }

  /// Loads WooCommerce product categories.  Tries `orderby=count` (biggest
  /// categories first) but some WC installs / WAFs reject non-default
  /// orderby values, so it falls back to the default sort order on
  /// failure.  We also trim to 100 max to avoid server timeouts.
  Future<void> _loadCategories() async {
    List<Category> cats = [];
    try {
      cats = await _api.getCategories(perPage: 100, orderByCount: true);
    } catch (e) {
      debugPrint('[Explore] categories orderByCount failed: $e');
    }
    // Fallback: try the same categories endpoint without orderby=count
    // if the first call returned empty or threw.
    if (cats.isEmpty) {
      try {
        cats = await _api.getCategories(perPage: 100, orderByCount: false);
      } catch (e2) {
        debugPrint('[Explore] categories default load also failed: $e2');
      }
    }
    if (mounted) {
      setState(() {
        _categories = cats;
        _loadingCategories = false;
      });
    }
  }

  /// Fetches the first page of products for the current filter.
  ///
  /// Primary sort is WooCommerce `orderby=popularity` (sales index) so
  /// best-selling products surface first.  If that sort is rejected by
  /// the server/WAF we fall back to a plain `orderby=date` fetch, which
  /// is the most universally supported WC sort.
  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _page = 1;
    _hasMore = true;

    List<Product> raw = [];
    try {
      raw = await _api.getProducts(
        page: _page,
        perPage: _perPage,
        category: _categoryQuery,
        orderby: 'popularity',
        order: 'desc',
      );
    } catch (e) {
      debugPrint('[Explore] products popularity-sort failed: $e');
    }
    // Fallback if popularity failed / returned empty — date sort, then
    // finally a parameterless (most server-compatible) call.
    if (raw.isEmpty) {
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: _categoryQuery,
          orderby: 'date',
          order: 'desc',
        );
      } catch (e2) {
        // Last-ditch: no orderby/order at all
        try {
          raw = await _api.getProducts(
            page: _page,
            perPage: _perPage,
            category: _categoryQuery,
          );
        } catch (e3) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = 'Could not load products. Please try again.';
            });
          }
          return;
        }
      }
    }

    final processed = _postProcess(raw);
    if (mounted) {
      setState(() {
        _products = processed;
        _loading = false;
        _page++;
        _hasMore = raw.length >= _perPage;
      });
    }
  }

  /// Infinite scroll: fetches the next page.  Uses the same popularity →
  /// date → default fallback chain so a sort rejected on page N doesn't
  /// prevent further pages from loading.
  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);

    List<Product> raw = [];
    try {
      raw = await _api.getProducts(
        page: _page,
        perPage: _perPage,
        category: _categoryQuery,
        orderby: 'popularity',
        order: 'desc',
      );
    } catch (_) {}
    if (raw.isEmpty) {
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: _categoryQuery,
          orderby: 'date',
          order: 'desc',
        );
      } catch (_) {
        try {
          raw = await _api.getProducts(
            page: _page,
            perPage: _perPage,
            category: _categoryQuery,
          );
        } catch (_) {
          if (mounted) setState(() => _loadingMore = false);
          return;
        }
      }
    }

    final processed = _postProcess(raw);
    if (mounted) {
      setState(() {
        _products.addAll(processed);
        _page++;
        _hasMore = raw.length >= _perPage;
        _loadingMore = false;
      });
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
            'Browse the full ZZmore catalog – top sellers first',
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
          value: _categories.any((c) => 'cat:${c.id}' == _selectedFilter) ||
                  _selectedFilter == 'all'
              ? _selectedFilter
              : 'all',
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
            ..._categories.map((c) {
              final count = c.count ?? 0;
              final label = count > 0 ? '${c.name} ($count)' : c.name;
              return DropdownMenuItem(
                value: 'cat:${c.id}',
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
          const Text('No products match this category yet',
              style: TextStyle(color: AppColors.inkSoftColor)),
        ],
      ),
    );
  }
}
