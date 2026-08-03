import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/category.dart' as cat_model;
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';
import '../providers/products_provider.dart';
import 'main_screen.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: Consumer<ProductsProvider>(
          builder: (context, provider, child) {
            final categories = provider.categories;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Explore vendors',
                            style: TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Fraunces',
                            )),
                        const SizedBox(height: 20),
                        if (categories.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Text('Loading categories...',
                                  style: TextStyle(color: AppColors.inkSoftColor)),
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.5,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              return _buildCategoryCard(category, context);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryCard(cat_model.Category category, BuildContext context) {
    return GestureDetector(
      onTap: () {
        MainScreen.innerNavigatorOf(context, 1)?.push(
          MaterialPageRoute(
            builder: (_) => CategoryProductsPage(
              categoryId: category.id.toString(),
              categoryName: category.name ?? 'Products',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.indigoColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: AdirePatternPainter(),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${category.count}+ items', style: const TextStyle(color: AppColors.goldColor, fontSize: 13)),
                const SizedBox(height: 8),
                Text(category.name ?? '', style: const TextStyle(color: AppColors.whiteColor, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AdirePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.indigoLightColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 30) {
      for (double y = 0; y < size.height; y += 30) {
        canvas.drawCircle(Offset(x + 15, y + 15), 8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Category Products Listing Page ───
class CategoryProductsPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryProductsPage({super.key, required this.categoryId, required this.categoryName});

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  final ScrollController _scrollController = ScrollController();
  final ApiService _api = ApiService();
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProducts();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _api.getProducts(page: _page, category: widget.categoryId);
      // Filter out excluded vendor products
      final filtered = products.where((p) =>
          !ApiConstants.isVendorExcluded(id: p.vendorId, name: p.vendorName)).toList();
      if (mounted) {
        setState(() {
          _products = filtered;
          _isLoading = false;
          if (products.length < 10) _hasMore = false;
          _page++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final more = await _api.getProducts(page: _page, category: widget.categoryId);
      // Filter out excluded vendor products
      final moreFiltered = more.where((p) =>
          !ApiConstants.isVendorExcluded(id: p.vendorId, name: p.vendorName)).toList();
      if (mounted) {
        setState(() {
          _products.addAll(moreFiltered);
          _page++;
          if (more.length < 10) _hasMore = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.categoryName,
            style: const TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_bag_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text('No products in this category yet', style: TextStyle(color: AppColors.inkSoftColor)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.goldColor,
                  onRefresh: () async {
                    setState(() {
                      _page = 1;
                      _hasMore = true;
                      _isLoadingMore = false;
                    });
                    await _loadProducts();
                  },
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _products.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _products.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(color: AppColors.goldColor, strokeWidth: 2),
                          ),
                        );
                      }
                      return ProductTile(product: _products[index]);
                    },
                  ),
                ),
    );
  }
}
