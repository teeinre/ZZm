import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';

/// Explore tab: WooCommerce product_cat taxonomy-based catalog.
///
/// Architecture (FIXED — Sept 2026):
///  * Category source: vendor-api.php → `get_all_product_categories`
///    (uses WP `get_terms('product_cat')` directly — never Dokan store_category,
///    includes empty categories, sorted A-Z).
///  * Product source (All filter): vendor-api.php → `get_products_by_category`
///    fallback + WC REST `?category=` as alternate path — both use the
///    post_type=product + product_cat term_relationship INNER JOIN, so every
///    product type works: simple, variable, booking, subscription, bundle,
///    downloadable, virtual, grouped, external.
///  * Category listing sort: strict alphabetical A→Z, Uncategorized always
///    last regardless of alphabetical position.
///  * Product listing sort: strict alphabetical A→Z by product title
///    (relevance/popularity removed per requirements).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scroll = ScrollController();

  /// WooCommerce PRODUCT categories (taxonomy=product_cat).  Sorted
  /// alphabetically A→Z with Uncategorized forced to the END of the list.
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

  int? get _selectedCategoryId {
    if (_selectedFilter.startsWith('cat:')) {
      return int.tryParse(_selectedFilter.substring(4));
    }
    return null;
  }

  /// Returns true if the category slug/name matches the WooCommerce
  /// default "Uncategorized" term (case-insensitive match on both slug
  /// and name so it works regardless of site language).
  static bool _isUncategorized(Category c) {
    final slug = (c.slug ?? '').toLowerCase().trim();
    final name = c.name.toLowerCase().trim();
    if (slug == 'uncategorized') return true;
    if (name == 'uncategorized') return true;
    // Fallback: the Uncategorized term is almost always ID=1 on a fresh
    // WooCommerce install.  The match above already covers the canonical
    // case so this shouldn't be needed, but we keep it for robustness.
    if (c.id == 1 && slug.isEmpty) return true;
    return false;
  }

  /// Applies strict A-Z sorting to a category list, with the
  /// "Uncategorized" term forced to the END of the list no matter what.
  static List<Category> _sortCategories(List<Category> input) {
    final sorted = List<Category>.from(input);
    sorted.sort((a, b) {
      final aU = _isUncategorized(a);
      final bU = _isUncategorized(b);
      if (aU && !bU) return 1;
      if (!aU && bU) return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  /// Applies:
  ///   1) vendor blocklist filter (unchanged from before),
  ///   2) strict ALPHABETICAL A→Z sort by product title (relevance removed).
  List<Product> _postProcess(List<Product> list) {
    final filtered = list
        .where((p) => !ApiConstants.isVendorExcluded(
            id: p.vendorId, name: p.vendorName))
        .toList();
    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  /// Loads the WooCommerce product_cat taxonomy terms.
  ///
  /// PRIMARY PATH (new, preferred): vendor-api.php get_all_product_categories
  ///   — Bypasses WC REST entirely.  Uses WP get_terms('product_cat') directly.
  ///   Returns: ALL terms (hide_empty=false on first call so categories with
  ///   only non-physical products still appear).
  ///
  /// FALLBACK PATHS (if vendor-api not yet deployed or unreachable):
  ///   1) WC REST /products/categories?hide_empty=true&orderby=count
  ///   2) WC REST /products/categories?hide_empty=true default order
  ///
  /// After loading: categories are sorted A-Z with Uncategorized always last.
  Future<void> _loadCategories() async {
    List<Category> cats = [];

    // ── Path 1: vendor-api.php (authoritative — includes all terms) ────
    try {
      cats = await _api.getAllProductCategories(hideEmpty: false);
      debugPrint(
          '[Explore] categories vendor-api primary: returned ${cats.length}');
    } catch (e) {
      debugPrint('[Explore] categories vendor-api primary FAILED: $e');
    }

    // ── Path 2: WC REST orderByCount (if vendor-api returned empty/threw) ─
    if (cats.isEmpty) {
      try {
        cats = await _api.getCategories(perPage: 100, orderByCount: true);
        debugPrint('[Explore] categories wc-rest count-sort: ${cats.length}');
      } catch (e) {
        debugPrint('[Explore] categories wc-rest count-sort FAILED: $e');
      }
    }

    // ── Path 3: WC REST default order ──────────────────────────────────
    if (cats.isEmpty) {
      try {
        cats = await _api.getCategories(perPage: 100, orderByCount: false);
        debugPrint('[Explore] categories wc-rest default: ${cats.length}');
      } catch (e2) {
        debugPrint('[Explore] categories wc-rest default FAILED: $e2');
      }
    }

    // ── Post-load: STRICT A-Z + Uncategorized at the END ──────────────
    final sorted = _sortCategories(cats);

    debugPrint('[Explore] final category list (total=${sorted.length}). '
        'Uncategorized at index: '
        '${sorted.indexWhere((c) => _isUncategorized(c))} '
        '(should be = length-1 when present)');

    if (mounted) {
      setState(() {
        _categories = sorted;
        _loadingCategories = false;
      });
    }
  }

  /// Fetches one page of products for the current filter.
  ///
  /// Product fetch path priority:
  ///
  ///   1) vendor-api.php get_products_by_category
  ///      — DIRECT SQL (term_relationships INNER JOIN product_cat)
  ///      — works for simple, variable, booking, subscription, all types
  ///      — returns [] (HTTP 200) on "no matches" instead of 4xx/5xx
  ///   2) vendor-api.php search_products (pool for All filter)
  ///   3) WC REST /wc/v3/products?category=X (fallback, may miss booking types)
  ///
  /// If the user has "All products" selected we do a wider sweep by:
  ///   a) calling getProducts() without category restriction
  ///   b) using the same 3-attempt (popularity → date → default) structure,
  ///      but now a 4th path: vendor-api search_products with a tiny
  ///      pool-building query.
  ///
  /// ERROR POLICY: error banner is ONLY shown when ALL paths threw
  /// exceptions (we literally got zero HTTP 200 responses).  Any path
  /// that returned HTTP 200 (even with empty list) counts as success →
  /// render the "no products yet" card.
  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _page = 1;
    _hasMore = true;

    List<Product> raw = [];
    int throwCount = 0;
    int triedPaths = 0;

    final cid = _selectedCategoryId;

    // ── Path 1 (PREFERRED): vendor-api.php get_products_by_category ───
    // Works for ALL product types: simple, booking, subscription, etc.
    // If cid == null ("All products") we SKIP this path since it needs
    // a specific category_id — we handle "All" via Paths 2..4.
    if (cid != null) {
      triedPaths++;
      try {
        raw = await _api.getProductsByCategory(cid,
            page: _page, perPage: _perPage);
        debugPrint(
            '[Explore] p1 vendor-api cat=$cid: returned ${raw.length}');
      } catch (e) {
        throwCount++;
        debugPrint('[Explore] p1 vendor-api cat=$cid THREW: $e');
      }
    }

    // ── Path 2: vendor-api.php search_products pool builder (for "All") ─
    // Cheap way to get a cross-section of all product types when no
    // category is filtered — useful for sites where WC REST skips
    // booking/subscription types.
    if (raw.isEmpty && cid == null) {
      triedPaths++;
      try {
        raw = await _api.searchProducts(' ', perPage: _perPage);
        debugPrint('[Explore] p2 vendor-api pool (All): ${raw.length}');
      } catch (e) {
        throwCount++;
        debugPrint('[Explore] p2 vendor-api pool THREW: $e');
      }
    }

    // ── Path 3: WC REST category filter (best-effort fallback) ────────
    //   3 attempts: popularity → date → default sort (to beat WAF)
    int wcThrowCount = 0;
    const wcAttempts = 3;
    if (raw.isEmpty) {
      triedPaths++;
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: cid?.toString(),
          orderby: 'popularity',
          order: 'desc',
        );
        debugPrint('[Explore] p3 wc popularity: returned ${raw.length}');
      } catch (e) {
        wcThrowCount++;
        debugPrint('[Explore] p3 wc popularity THREW: $e');
      }
    }
    if (raw.isEmpty && wcThrowCount >= 1) {
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: cid?.toString(),
          orderby: 'date',
          order: 'desc',
        );
        debugPrint('[Explore] p3 wc date: returned ${raw.length}');
      } catch (e) {
        wcThrowCount++;
        debugPrint('[Explore] p3 wc date THREW: $e');
      }
    }
    if (raw.isEmpty && wcThrowCount >= 2) {
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: cid?.toString(),
        );
        debugPrint('[Explore] p3 wc default: returned ${raw.length}');
      } catch (e) {
        wcThrowCount++;
        debugPrint('[Explore] p3 wc default THREW: $e');
      }
    }
    if (wcThrowCount == wcAttempts) throwCount++;

    // ── Path 4: For "All" filter only: broader WC REST sweep ──────────
    // (extra attempt without any restrictions)
    if (cid == null && raw.isEmpty) {
      triedPaths++;
      try {
        raw = await _api.getProducts(
            page: _page, perPage: _perPage, orderby: 'title', order: 'asc');
        debugPrint('[Explore] p4 wc all-title-sort: returned ${raw.length}');
      } catch (e) {
        throwCount++;
        debugPrint('[Explore] p4 wc all-title-sort THREW: $e');
      }
    }

    // ── Decision: error banner or (possibly empty) result ──────────────
    final anyPathRan = triedPaths > 0;
    final everyPathThrew = throwCount >= triedPaths && triedPaths > 0;

    if (mounted) {
      if (everyPathThrew && raw.isEmpty && anyPathRan) {
        setState(() {
          _loading = false;
          _error = 'Could not load products. Please try again.';
        });
        return;
      }

      final processed = _postProcess(raw);
      setState(() {
        _products = processed;
        _loading = false;
        _page++;
        _hasMore = raw.length >= _perPage;
      });
    }
  }

  /// Infinite scroll.  Same multi-path priority as _loadProducts but
  /// without the pool-builder search step (simpler because the user is
  /// already seeing at least one page of products).
  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    setState(() => _loadingMore = true);

    List<Product> raw = [];
    int throwCount = 0;
    int triedPaths = 0;
    final cid = _selectedCategoryId;

    if (cid != null) {
      triedPaths++;
      try {
        raw = await _api.getProductsByCategory(cid,
            page: _page, perPage: _perPage);
      } catch (_) {
        throwCount++;
      }
    }
    if (raw.isEmpty) {
      triedPaths++;
      try {
        raw = await _api.getProducts(
          page: _page,
          perPage: _perPage,
          category: cid?.toString(),
        );
      } catch (_) {
        throwCount++;
      }
    }
    if (raw.isEmpty && cid == null) {
      triedPaths++;
      try {
        raw = await _api.getProducts(
            page: _page, perPage: _perPage, orderby: 'title', order: 'asc');
      } catch (_) {
        throwCount++;
      }
    }

    final everyPathThrew = throwCount >= triedPaths && triedPaths > 0;
    if (everyPathThrew && raw.isEmpty) {
      if (mounted) setState(() => _loadingMore = false);
      return;
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
            'Browse the full ZZmore catalog – sorted A–Z',
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
              final label =
                  '${c.name}${c.count > 0 ? ' (${c.count})' : ''}';
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
