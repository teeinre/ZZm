import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../providers/currency_provider.dart';
import '../providers/cart_provider.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final Map<String, dynamic>? rawProduct;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.rawProduct,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _rawProduct;
  List<Map<String, dynamic>> _variations = [];
  Map<String, String> _selectedAttributes = {};
  Map<String, dynamic>? _selectedVariation;
  int _quantity = 1;
  int _currentImageIndex = 0;
  bool _isDescriptionExpanded = false;
  bool _isAddingToCart = false;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use the provided rawProduct or fetch it
      Map<String, dynamic> raw;
      if (widget.rawProduct != null) {
        raw = widget.rawProduct!;
      } else {
        raw = await _apiService.getProductJson(widget.product.id);
      }

      List<Map<String, dynamic>> variations = [];
      if (raw['type']?.toString() == 'variable') {
        variations = await _apiService.getProductVariations(widget.product.id);
      }

      if (!mounted) return;

      // Initialize attribute selections from the raw product attributes
      final attributes = raw['attributes'] as List<dynamic>? ?? [];
      Map<String, String> initialSelections = {};
      for (final attr in attributes) {
        if (attr is Map<String, dynamic>) {
          final name = attr['name']?.toString() ?? '';
          if (name.isNotEmpty) {
            initialSelections[name] = '';
          }
        }
      }

      setState(() {
        _rawProduct = raw;
        _variations = variations;
        _selectedAttributes = initialSelections;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ─── Variation matching ───────────────────────────────────────────────────

  void _onAttributeChanged(String attributeName, String? value) {
    if (value == null) return;

    setState(() {
      _selectedAttributes[attributeName] = value;
    });

    // Try to find a matching variation
    _matchVariation();
  }

  void _matchVariation() {
    _selectedVariation = null;

    // Only match if all required attributes are selected
    final allSelected = _selectedAttributes.values.every((v) => v.isNotEmpty);
    if (!allSelected) return;

    for (final variation in _variations) {
      final varAttrs = variation['attributes'] as List<dynamic>? ?? [];
      if (varAttrs.isEmpty) continue;

      bool matches = true;
      for (final varAttr in varAttrs) {
        if (varAttr is Map<String, dynamic>) {
          final varName = varAttr['name']?.toString() ?? '';
          final varOption = varAttr['option']?.toString() ?? '';
          if (_selectedAttributes.containsKey(varName) &&
              _selectedAttributes[varName] != varOption) {
            matches = false;
            break;
          }
        }
      }

      if (matches) {
        setState(() {
          _selectedVariation = variation;
          _currentImageIndex = 0;
        });
        return;
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<String> get _displayImages {
    final images = <String>[];
    if (_selectedVariation != null && _selectedVariation!['image'] != null) {
      final vImg = _selectedVariation!['image'] as Map<String, dynamic>;
      final src = vImg['src']?.toString();
      if (src != null && src.isNotEmpty) {
        images.add(src);
      }
    }
    // Add product images, avoiding duplicates
    for (final img in widget.product.images) {
      if (!images.contains(img)) {
        images.add(img);
      }
    }
    return images;
  }

  String get _currentPrice {
    if (_selectedVariation != null) {
      return _selectedVariation!['price']?.toString() ??
          widget.product.price;
    }
    return widget.product.price;
  }

  String? get _currentRegularPrice {
    if (_selectedVariation != null) {
      final reg = _selectedVariation!['regular_price']?.toString();
      if (reg != null && reg.isNotEmpty && reg != _currentPrice) {
        return reg;
      }
      return null;
    }
    if (widget.product.onSale && widget.product.regularPrice != null) {
      return widget.product.regularPrice;
    }
    return null;
  }

  String? get _currentSalePrice {
    if (_selectedVariation != null) {
      final sale = _selectedVariation!['sale_price']?.toString();
      if (sale != null && sale.isNotEmpty && sale != _currentRegularPrice) {
        return sale;
      }
      return null;
    }
    if (widget.product.onSale && widget.product.salePrice != null) {
      return widget.product.salePrice;
    }
    return null;
  }

  String _getStockStatus() {
    if (_selectedVariation != null) {
      return _selectedVariation!['stock_status']?.toString() ?? 'instock';
    }
    return _rawProduct?['stock_status']?.toString() ??
        (widget.product.inStock ? 'instock' : 'outofstock');
  }

  int _getStockQuantity() {
    if (_selectedVariation != null) {
      return _selectedVariation!['stock_quantity'] as int? ?? 0;
    }
    return widget.product.stockQuantity;
  }

  bool get _isOutOfStock {
    final status = _getStockStatus();
    return status == 'outofstock';
  }

  bool get _isOnBackorder {
    final status = _getStockStatus();
    return status == 'onbackorder';
  }

  bool get _isVariableProduct {
    return _rawProduct?['type']?.toString() == 'variable';
  }

  List<Map<String, dynamic>> get _productAttributes {
    final attrs = _rawProduct?['attributes'] as List<dynamic>? ?? [];
    return attrs
        .whereType<Map<String, dynamic>>()
        .where((a) => a['variation'] == true)
        .toList();
  }

  bool get _allAttributesSelected {
    if (!_isVariableProduct) return true;
    if (_productAttributes.isEmpty) return true;
    return _selectedAttributes.values.every((v) => v.isNotEmpty);
  }

  String? get _selectedVariationId {
    return _selectedVariation?['id']?.toString();
  }

  // ─── Cart action ──────────────────────────────────────────────────────────

  Future<void> _addToCart() async {
    if (_isAddingToCart) return;

    if (_isVariableProduct && !_allAttributesSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select all options before adding to cart.'),
          backgroundColor: AppColors.coralColor,
        ),
      );
      return;
    }

    if (_isOutOfStock) return;

    setState(() => _isAddingToCart = true);

    try {
      // Build a Product with the currently-selected variation price
      final displayPrice = _currentSalePrice ?? _currentPrice;
      final cartProduct = widget.product.copyWith(
        price: displayPrice,
        regularPrice: _currentRegularPrice,
        salePrice: _currentSalePrice,
        onSale: _currentRegularPrice != null,
        inStock: !_isOutOfStock,
        stockQuantity: _getStockQuantity(),
      );

      final cartProvider = context.read<CartProvider>();

      // Add with variation ID for variable products, respecting quantity
      for (int i = 0; i < _quantity; i++) {
        await cartProvider.addToCart(
          cartProduct,
          variationId: _selectedVariationId,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_quantity × ${widget.product.name} added to cart',
          ),
          backgroundColor: AppColors.goldColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add to cart: $e'),
          backgroundColor: AppColors.coralColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAddingToCart = false);
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.product.name,
          style: GoogleFonts.fraunces(
            color: AppColors.inkColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoading();
    }

    if (_error != null) {
      return _buildError();
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImageGallery(),
                _buildProductInfo(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  // ─── Loading / Error ──────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.goldColor),
          const SizedBox(height: 16),
          Text(
            'Loading product details...',
            style: GoogleFonts.fraunces(
              color: AppColors.inkSoftColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: AppColors.coralColor),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.inkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.inkSoftColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDetails,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldColor,
                foregroundColor: AppColors.whiteColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Image Gallery ────────────────────────────────────────────────────────

  Widget _buildImageGallery() {
    final images = _displayImages;

    if (images.isEmpty) {
      return Container(
        height: 350,
        color: AppColors.sandColor,
        child: Center(
          child: Icon(Icons.image_not_supported,
              size: 64, color: AppColors.inkSoftColor.withOpacity(0.4)),
        ),
      );
    }

    return Column(
      children: [
        Stack(
          children: [
            SizedBox(
              height: 350,
              child: PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (index) {
                  setState(() => _currentImageIndex = index);
                },
                itemBuilder: (context, index) {
                  return CachedNetworkImage(
                    imageUrl: images[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (context, url) => Container(
                      color: AppColors.sandColor,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.goldColor,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.sandColor,
                      child: const Icon(Icons.broken_image,
                          color: AppColors.inkSoftColor, size: 48),
                    ),
                  );
                },
              ),
            ),
            // Dot indicators
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentImageIndex ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _currentImageIndex
                            ? AppColors.goldColor
                            : AppColors.whiteColor.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─── Product Info ─────────────────────────────────────────────────────────

  Widget _buildProductInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.inkColor.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVendorName(),
          const SizedBox(height: 8),
          _buildProductName(),
          const SizedBox(height: 12),
          _buildRating(),
          const SizedBox(height: 16),
          _buildPrice(),
          const SizedBox(height: 16),
          const Divider(color: AppColors.sandColor),
          const SizedBox(height: 12),
          _buildStockIndicator(),
          if (_isVariableProduct) ...[
            const SizedBox(height: 16),
            _buildVariationOptions(),
          ],
          const SizedBox(height: 20),
          _buildQuantitySelector(),
          const SizedBox(height: 20),
          const Divider(color: AppColors.sandColor),
          const SizedBox(height: 12),
          _buildDescription(),
        ],
      ),
    );
  }

  // ─── Vendor Name ──────────────────────────────────────────────────────────

  Widget _buildVendorName() {
    final vendorName = widget.product.vendorName;
    if (vendorName == null || vendorName.isEmpty) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () {
        // Navigate to vendor profile screen
        // Navigate to vendor profile
      },
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.indigoPaleColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.store_outlined,
              size: 16,
              color: AppColors.indigoColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            vendorName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.indigoColor,
              decoration: TextDecoration.underline,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward_ios,
            size: 10,
            color: AppColors.indigoColor.withOpacity(0.6),
          ),
        ],
      ),
    );
  }

  // ─── Product Name ─────────────────────────────────────────────────────────

  Widget _buildProductName() {
    return Text(
      widget.product.name,
      style: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.inkColor,
        height: 1.3,
      ),
    );
  }

  // ─── Rating ───────────────────────────────────────────────────────────────

  Widget _buildRating() {
    final rating = widget.product.rating;
    final ratingCount = widget.product.ratingCount;

    if (rating == null || rating == 0) {
      return Row(
        children: [
          ...List.generate(5, (i) {
            return const Icon(Icons.star_outline,
                size: 16, color: AppColors.sandColor);
          }),
          const SizedBox(width: 8),
          const Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.inkSoftColor,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        ...List.generate(5, (i) {
          if (i < rating.floor()) {
            return const Icon(Icons.star,
                size: 16, color: AppColors.goldColor);
          } else if (i < rating && rating - i > 0) {
            return const Icon(Icons.star_half,
                size: 16, color: AppColors.goldColor);
          } else {
            return const Icon(Icons.star_outline,
                size: 16, color: AppColors.sandColor);
          }
        }),
        const SizedBox(width: 8),
        Text(
          '${rating.toStringAsFixed(1)} ($ratingCount ${ratingCount == 1 ? 'review' : 'reviews'})',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkSoftColor,
          ),
        ),
      ],
    );
  }

  // ─── Price ────────────────────────────────────────────────────────────────

  Widget _buildPrice() {
    final price = _currentPrice;
    final regularPrice = _currentRegularPrice;
    final salePrice = _currentSalePrice;

    final displayPrice = salePrice ?? price;
    final priceValue = double.tryParse(displayPrice) ?? 0;
    final hasSale = regularPrice != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${context.watch<CurrencyProvider>().currencySymbol}${_formatPrice(priceValue)}',
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: hasSale ? AppColors.coralColor : AppColors.inkColor,
          ),
        ),
        if (hasSale) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '${context.watch<CurrencyProvider>().currencySymbol}${_formatPrice(double.tryParse(regularPrice) ?? 0)}',
              style: GoogleFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.inkSoftColor,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.coralColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Sale',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.coralColor,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatPrice(double value) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  // ─── Stock Indicator ──────────────────────────────────────────────────────

  Widget _buildStockIndicator() {
    final status = _getStockStatus();
    final quantity = _getStockQuantity();

    Color indicatorColor;
    String label;

    switch (status) {
      case 'instock':
        if (quantity > 0 && quantity <= 5) {
          indicatorColor = const Color(0xFFF59E0B); // orange
          label = 'Low Stock – Only $quantity left';
        } else {
          indicatorColor = const Color(0xFF10B981); // green
          label = 'In Stock';
        }
        break;
      case 'outofstock':
        indicatorColor = AppColors.coralColor;
        label = 'Out of Stock';
        break;
      case 'onbackorder':
        indicatorColor = const Color(0xFFF59E0B);
        label = 'On Backorder';
        break;
      default:
        indicatorColor = AppColors.inkSoftColor;
        label = status;
    }

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: indicatorColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: indicatorColor,
          ),
        ),
      ],
    );
  }

  // ─── Variation Options ────────────────────────────────────────────────────

  Widget _buildVariationOptions() {
    if (!_isVariableProduct) return const SizedBox.shrink();

    final attributes = _productAttributes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _allAttributesSelected ? 'Options' : 'Select options',
          style: GoogleFonts.fraunces(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.inkColor,
          ),
        ),
        const SizedBox(height: 12),
        ...attributes.map((attr) {
          final name = attr['name']?.toString() ?? 'Option';
          final options = (attr['options'] as List<dynamic>?)
                  ?.map((o) => o.toString())
                  .toList() ??
              [];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildAttributeDropdown(name, options),
          );
        }),
        if (!_allAttributesSelected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.indigoPaleColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: AppColors.indigoLightColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Please select all options to see the final price and availability.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.indigoLightColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAttributeDropdown(String name, List<String> options) {
    final currentValue = _selectedAttributes[name] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sandColor),
        color: AppColors.creamColor,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue.isEmpty ? null : currentValue,
          hint: Text(
            'Select $name',
            style: const TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 14,
            ),
          ),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.inkSoftColor),
          style: const TextStyle(
            color: AppColors.inkColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          items: [
            DropdownMenuItem<String>(
              value: currentValue.isEmpty ? null : '',
              child: Text(
                'Select $name',
                style: TextStyle(
                  color: AppColors.inkSoftColor.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
            ),
            ...options.map((option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              );
            }),
          ],
          onChanged: (value) {
            if (value != null && value.isNotEmpty) {
              _onAttributeChanged(name, value);
            }
          },
        ),
      ),
    );
  }

  // ─── Quantity Selector ────────────────────────────────────────────────────

  Widget _buildQuantitySelector() {
    return Row(
      children: [
        Text(
          'Quantity',
          style: GoogleFonts.fraunces(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.inkColor,
          ),
        ),
        const Spacer(),
        // Minus button
        _quantityButton(
          icon: Icons.remove,
          onTap: _quantity > 1
              ? () => setState(() => _quantity--)
              : null,
        ),
        // Quantity display
        Container(
          width: 48,
          height: 36,
          alignment: Alignment.center,
          child: Text(
            '$_quantity',
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.inkColor,
            ),
          ),
        ),
        // Plus button
        _quantityButton(
          icon: Icons.add,
          onTap: () => setState(() => _quantity++),
        ),
      ],
    );
  }

  Widget _quantityButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled ? AppColors.goldColor : AppColors.sandColor,
          ),
          color: isEnabled
              ? AppColors.goldColor.withOpacity(0.1)
              : AppColors.sandColor.withOpacity(0.3),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isEnabled ? AppColors.goldColor : AppColors.inkSoftColor,
        ),
      ),
    );
  }

  // ─── Description ──────────────────────────────────────────────────────────

  Widget _buildDescription() {
    final description = widget.product.description;
    if (description == null || description.isEmpty) {
      return const SizedBox.shrink();
    }

    // Strip HTML tags for plain text display
    final plainText = _stripHtml(description);
    if (plainText.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Description',
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.inkColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedCrossFade(
          firstChild: Text(
            plainText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.inkSoftColor,
            ),
          ),
          secondChild: Text(
            plainText,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.inkSoftColor,
            ),
          ),
          crossFadeState: _isDescriptionExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        if (plainText.length > 150)
          GestureDetector(
            onTap: () {
              setState(() => _isDescriptionExpanded = !_isDescriptionExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isDescriptionExpanded ? 'Show Less' : 'Read More',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.goldColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isDescriptionExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.goldColor,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _stripHtml(String html) {
    final regex = RegExp(r'<[^>]*>');
    String text = html.replaceAll(regex, '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return text.trim();
  }

  // ─── Bottom Bar ───────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        boxShadow: [
          BoxShadow(
            color: AppColors.inkColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: _isOutOfStock
            ? _buildOutOfStockButton()
            : _buildAddToCartButton(),
      ),
    );
  }

  Widget _buildOutOfStockButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.inkSoftColor.withOpacity(0.15),
          disabledBackgroundColor: AppColors.inkSoftColor.withOpacity(0.15),
          disabledForegroundColor: AppColors.inkSoftColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildAddToCartButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isAddingToCart ? null : _addToCart,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldColor,
          foregroundColor: AppColors.whiteColor,
          disabledBackgroundColor: AppColors.goldColor.withOpacity(0.6),
          disabledForegroundColor: AppColors.whiteColor.withOpacity(0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isAddingToCart
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.whiteColor),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Add to Cart',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
