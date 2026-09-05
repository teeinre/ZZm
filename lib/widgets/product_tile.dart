import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../screens/product_detail_screen.dart';
import '../screens/vendor_profile_screen.dart';

class ProductTile extends StatefulWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductTile({super.key, required this.product, this.onTap});

  @override
  State<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<ProductTile> {
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final isVariable = widget.product.isVariable;
    final color = widget.product.color == AppColors.gold
        ? AppColors.goldColor
        : widget.product.color == AppColors.coral
            ? AppColors.coralColor
            : AppColors.indigoLightColor;
    return GestureDetector(
      onTap: widget.onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: widget.product),
              ),
            );
          },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 108,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: widget.product.images.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            widget.product.images.first,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: widget.product.icon != null
                              ? Text(widget.product.icon!,
                                  style: TextStyle(color: color, fontSize: 34))
                              : Icon(Icons.shopping_bag_outlined,
                                  color: color, size: 40),
                        ),
                ),
                // Variation badge
                if (isVariable)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.goldColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Options',
                          style: TextStyle(
                              color: AppColors.whiteColor,
                              fontSize: 8,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                // Bookable product badge
                if (!isVariable && widget.product.isBookable)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.coralColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Book',
                          style: TextStyle(
                              color: AppColors.whiteColor,
                              fontSize: 8,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                // Like button
                Positioned(
                  top: 8,
                  right: 8,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isLiked = !_isLiked;
                      });
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.whiteColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _isLiked
                            ? AppColors.coralColor
                            : AppColors.inkSoftColor,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.product.name,
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Clickable vendor name
            if (widget.product.vendorName != null &&
                widget.product.vendorName!.isNotEmpty)
              GestureDetector(
                onTap: () {
                  if (widget.product.vendorId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VendorProfileScreen(
                          vendorId: widget.product.vendorId!,
                          vendorName: widget.product.vendorName,
                        ),
                      ),
                    );
                  }
                },
                child: Text(
                  'by ${widget.product.vendorName}',
                  style: const TextStyle(
                    color: AppColors.goldColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isVariable
                      ? 'From \u00A3${widget.product.price}'
                      : '\u00A3${widget.product.price}',
                  style: TextStyle(
                    color: AppColors.indigoColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                InkWell(
                  onTap: () {
                    final isBookable = widget.product.isBookable;
                    if (isVariable || isBookable) {
                      // Booking products MUST navigate to product detail page
                      // so user can select date/time slots before adding to cart.
                      // Variable products already need option selection.
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductDetailScreen(product: widget.product),
                        ),
                      );
                    } else {
                      cartProvider.addToCart(widget.product);
                    }
                  },
                  child: Container(
                    padding: (isVariable || widget.product.isBookable)
                        ? const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)
                        : null,
                    width: (isVariable || widget.product.isBookable) ? null : 28,
                    height: (isVariable || widget.product.isBookable) ? null : 28,
                    decoration: BoxDecoration(
                      color: AppColors.indigoColor,
                      borderRadius: (isVariable || widget.product.isBookable)
                          ? BorderRadius.circular(12)
                          : null,
                      shape:
                          (isVariable || widget.product.isBookable) ? BoxShape.rectangle : BoxShape.circle,
                    ),
                    child: (isVariable || widget.product.isBookable)
                        ? Text(widget.product.isBookable ? 'Book' : 'Choose',
                            style: const TextStyle(
                                color: AppColors.whiteColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold))
                        : const Icon(Icons.add,
                            color: AppColors.whiteColor, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
