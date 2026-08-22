import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/cart_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/cart_item.dart';
import '../widgets/brand_logo.dart';
import 'checkout_webview_screen.dart';
import 'profile_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _discountController = TextEditingController();
  double _discount = 0.0;
  bool _discountApplied = false;
  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _applyDiscount() async {
    final code = _discountController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    // Validate coupon against WooCommerce API
    final api = ApiService();
    final coupon = await api.validateCoupon(code);

    if (!mounted) return;

    if (coupon != null) {
      final discountType = coupon['discount_type']?.toString() ?? 'fixed_cart';
      final amount = double.tryParse(coupon['amount']?.toString() ?? '0') ?? 0;
      if (discountType == 'percent') {
        setState(() {
          _discount = amount / 100.0;
          _discountApplied = true;
        });
      } else {
        // Fixed cart discount — calculate percentage of current subtotal
        final cart = context.read<CartProvider>();
        final subtotal = cart.subtotal;
        setState(() {
          _discount = subtotal > 0 ? amount / subtotal : 0;
          _discountApplied = true;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Coupon "${coupon['code']}" applied!'),
            backgroundColor: AppColors.goldColor,
          ),
        );
      }
    } else {
      setState(() {
        _discount = 0.0;
        _discountApplied = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or expired coupon code'),
            backgroundColor: AppColors.coralColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final subtotal = cartProvider.subtotal;
    final discountAmount = subtotal * _discount;
    final total = subtotal - discountAmount;

    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandLogo(height: 36),
                    const SizedBox(height: 16),
                    Text('Your Shopping Basket',
                        style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Fraunces',
                        )),
                    const SizedBox(height: 20),
                    if (cartProvider.cartItems.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 100, color: AppColors.goldColor.withOpacity(0.5)),
                              const SizedBox(height: 20),
                              Text('Your basket is empty', style: TextStyle(color: AppColors.inkColor, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text('Add some amazing products!', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      ...cartProvider.cartItems.map((item) => _buildCartItem(context, item)),
                      const SizedBox(height: 16),
                      _buildDiscountField(),
                      const SizedBox(height: 20),
                      if (cartProvider.uniqueVendorCount > 1) _buildMultiVendorBanner(cartProvider),
                      _buildSupportBanner(),
                      const SizedBox(height: 20),
                      _buildPriceBreakdown(subtotal, discountAmount, total),
                      const SizedBox(height: 24),
                      _buildCheckoutButton(total),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, CartItem item) {
    final cartProvider = context.read<CartProvider>();
    final color = item.product.color == AppColors.gold ? AppColors.goldColor : 
                  item.product.color == AppColors.coral ? AppColors.coralColor : 
                  AppColors.indigoLightColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: item.product.images.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(item.product.images.first, fit: BoxFit.cover),
                      )
                    : Center(
                        child: item.product.icon != null
                            ? Text(item.product.icon!, style: TextStyle(color: color, fontSize: 24))
                            : Icon(Icons.shopping_bag_outlined, color: color, size: 32),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.product.name, style: TextStyle(color: AppColors.inkColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(item.product.vendorName ?? '', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text('£${(double.tryParse(item.product.price) ?? 0.0).toStringAsFixed(2)}', style: TextStyle(color: AppColors.goldColor, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => cartProvider.removeFromCart(item.cartItemId),
                    icon: Icon(Icons.delete_outline, color: AppColors.coralColor, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.indigoPaleColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => cartProvider.updateQuantity(item.cartItemId, item.quantity - 1),
                          child: Icon(Icons.remove, size: 16, color: AppColors.indigoColor),
                        ),
                        const SizedBox(width: 8),
                        Text('${item.quantity}', style: TextStyle(color: AppColors.indigoColor, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => cartProvider.updateQuantity(item.cartItemId, item.quantity + 1),
                          child: Icon(Icons.add, size: 16, color: AppColors.indigoColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Variation badge
          if (item.variationId != null && item.variationId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Variation #${item.variationId}', style: TextStyle(fontSize: 10, color: AppColors.goldColor)),
            ),
          // Booking slot badge
          if (item.bookingLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available_outlined,
                      size: 13, color: AppColors.goldColor),
                  const SizedBox(width: 4),
                  Text('Booked: ${item.bookingLabel}',
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.goldColor)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscountField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _discountController,
              decoration: InputDecoration(
                hintText: 'Enter coupon code',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                hintStyle: TextStyle(color: AppColors.inkSoftColor),
              ),
              style: TextStyle(color: AppColors.inkColor),
            ),
          ),
          ElevatedButton(
            onPressed: _discountApplied ? null : () => _applyDiscount(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _discountApplied ? AppColors.goldDeepColor : AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(_discountApplied ? 'Applied' : 'Apply', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.goldColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.goldColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: AppColors.goldColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supporting African-owned vendors', style: TextStyle(color: AppColors.inkColor, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('We ship in 1 to 5 business days',
                    style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiVendorBanner(CartProvider cartProvider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.indigoColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.indigoColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, color: AppColors.indigoColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${cartProvider.uniqueVendorCount} vendors in your basket',
                  style: TextStyle(color: AppColors.inkColor, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your order will be split across ${cartProvider.vendorNames.join(", ")} for separate delivery.',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown(double subtotal, double discount, double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 15)),
              Text('£${subtotal.toStringAsFixed(2)}', style: TextStyle(color: AppColors.inkColor, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          if (discount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Discount (-${(_discount * 100).toInt()}%)', style: TextStyle(color: AppColors.coralColor, fontSize: 15)),
                Text('-£${discount.toStringAsFixed(2)}', style: TextStyle(color: AppColors.coralColor, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(color: AppColors.inkColor, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('£${total.toStringAsFixed(2)}', style: TextStyle(color: AppColors.goldColor, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(double total) {
    return ElevatedButton(
      onPressed: () {
        final auth = context.read<AuthProvider>();
        if (!auth.isAuthenticated) {
          // Auth gate: must log in before WebView bridge checkout
          _showAuthGate();
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CheckoutWebviewScreen()),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.goldColor,
        foregroundColor: AppColors.whiteColor,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 0,
      ),
      child: const Text('Proceed to Checkout',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  void _showAuthGate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.creamColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.inkSoftColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.indigoPaleColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.lock_outline, color: AppColors.indigoColor, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Login Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    fontFamily: 'Fraunces', color: AppColors.inkColor)),
            const SizedBox(height: 8),
            const Text('You need to log in to complete your purchase. '
                'This keeps your order history and addresses saved for next time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginPage()));
                },
                icon: const Icon(Icons.login, size: 20),
                label: const Text('Log In to Checkout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()));
                },
                icon: const Icon(Icons.person_add_outlined, size: 20),
                label: const Text('Create an Account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.indigoColor,
                  side: const BorderSide(color: AppColors.indigoColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
