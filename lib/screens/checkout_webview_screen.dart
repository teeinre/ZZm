import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/currency_provider.dart';
import '../services/bridge_service.dart';

/// WebView-based checkout using the PHP bridge plugin.
///
/// Flow:
///   1. User taps "Checkout" from cart screen
///   2. Cart items → POST to /bridge/v1/generate-token → get single-use token
///   3. WebView loads /bridge/v1/enter?token=XYZ
///   4. PHP: verifies token, sets auth cookie, rebuilds cart, redirects to /checkout/
///   5. User completes payment in WebView
///   6. WooCommerce redirects to /checkout/order-received/{id}/
///   7. Flutter NavigationDelegate detects this URL → fetches order details
///   8. Native OrderSuccessScreen shown with full order info
class CheckoutWebviewScreen extends StatefulWidget {
  const CheckoutWebviewScreen({super.key});

  @override
  State<CheckoutWebviewScreen> createState() => _CheckoutWebviewScreenState();
}

class _CheckoutWebviewScreenState extends State<CheckoutWebviewScreen> {
  late final WebViewController _controller;
  late final BridgeService _bridgeService;
  bool _loading = true;
  bool _handledCompletion = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final auth = context.read<AuthProvider>();
    _bridgeService = BridgeService(
      baseUrl: 'https://zzmore.store',
      authHeaderProvider: () async {
        final token = auth.user?.token ?? '';
        if (token.isEmpty) {
          // Fall back to storage service if user token not in memory
          final stored = await auth.storageService.getAuthToken();
          return 'Bearer ${stored ?? ''}';
        }
        return 'Bearer $token';
      },
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            debugPrint('[CheckoutWebView] Error: ${error.description}');
          },
          onNavigationRequest: (request) {
            _maybeHandleOrderReceived(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startCheckout());
  }

  Future<void> _startCheckout() async {
    try {
      final cart = context.read<CartProvider>();
      final items = cart.cartItems.map((item) {
        return BridgeCartItem(
          productId: item.product.id,
          quantity: item.quantity,
          variationId: item.variationId != null
              ? int.tryParse(item.variationId!)
              : null,
        );
      }).toList();

      if (items.isEmpty) {
        setState(() {
          _error = 'Your cart is empty.';
          _loading = false;
        });
        return;
      }

      debugPrint('[CheckoutWebView] Generating bridge token for ${items.length} items');
      final token = await _bridgeService.generateBridgeToken(items);
      final url = _bridgeService.buildWebviewEntryUrl(token);
      debugPrint('[CheckoutWebView] Loading: $url');
      await _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      debugPrint('[CheckoutWebView] Start failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not start checkout: $e';
          _loading = false;
        });
      }
    }
  }

  /// WooCommerce redirects to:
  ///   https://zzmore.store/checkout/order-received/482/?key=wc_order_abc123
  void _maybeHandleOrderReceived(String url) {
    if (_handledCompletion) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final segments = uri.pathSegments;
    final idx = segments.indexOf('order-received');

    if (idx != -1 && idx + 1 < segments.length) {
      final orderId = int.tryParse(segments[idx + 1]);
      if (orderId != null) {
        _handledCompletion = true;
        debugPrint('[CheckoutWebView] Order completed: #$orderId');
        _onOrderComplete(orderId);
      }
    }

    // Also handle failed/canceled checkout — WooCommerce may redirect to cart
    if (uri.path.contains('/cart/') || uri.path.contains('/checkout/') && uri.queryParameters['cancel_order'] != null) {
      debugPrint('[CheckoutWebView] Checkout was canceled or returned to cart');
      // Keep WebView open in case user wants to try again
    }
  }

  Future<void> _onOrderComplete(int orderId) async {
    try {
      debugPrint('[CheckoutWebView] Fetching order details for #$orderId');
      final order = await _bridgeService.fetchOrder(orderId);
      if (!mounted) return;

      // Clear local cart since order was placed
      await context.read<CartProvider>().clearCart();

      // Navigate to native order success screen, replacing the WebView
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WebviewOrderSuccessScreen(order: order),
        ),
      );
    } catch (e) {
      debugPrint('[CheckoutWebView] Failed to fetch order: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order placed, but details could not load: $e'),
          backgroundColor: AppColors.coralColor,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () {
            if (_handledCompletion) return;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cancel Checkout?'),
                content: const Text('Your cart items will be kept for later.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Continue Shopping'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel Checkout',
                        style: TextStyle(color: AppColors.coralColor)),
                  ),
                ],
              ),
            );
          },
        ),
        title: const Text('Checkout',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.inkSoftColor),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkColor, fontSize: 15)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startCheckout,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: AppColors.goldColor)),
      ],
    );
  }
}

/// Native order success screen shown after WebView checkout completes.
/// Displays order ID, status, total, items, and payment method.
class WebviewOrderSuccessScreen extends StatelessWidget {
  const WebviewOrderSuccessScreen({super.key, required this.order});

  final BridgeOrderDetails order;

  @override
  Widget build(BuildContext context) {
    final currencySymbol = context.watch<CurrencyProvider>().currencySymbol;
    final displayTotal = (double.tryParse(order.total) ?? 0);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.creamColor,
        appBar: AppBar(
          backgroundColor: AppColors.whiteColor,
          elevation: 0,
          leading: const SizedBox.shrink(),
          title: const Text('Order Confirmed',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Success icon
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 48),
              ),
              const SizedBox(height: 20),
              const Text('Order Confirmed!',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700,
                      color: AppColors.inkColor, fontFamily: 'Fraunces')),
              const SizedBox(height: 24),

              // Order details card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _detailRow('Order Number', '#${order.id}'),
                    const Divider(height: 24),
                    _detailRow('Status', _formatStatus(order.status)),
                    const Divider(height: 24),
                    _detailRow('Payment Method', order.paymentMethod),
                    const Divider(height: 24),
                    _detailRow('Total',
                        '$currencySymbol${displayTotal == displayTotal.roundToDouble() ? displayTotal.toStringAsFixed(0) : displayTotal.toStringAsFixed(2)}',
                        isAmount: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Items list
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Items (${order.items.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            fontFamily: 'Fraunces', color: AppColors.inkColor)),
                    const SizedBox(height: 12),
                    ...order.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(item.name,
                                style: const TextStyle(fontSize: 13, color: AppColors.inkColor)),
                          ),
                          const SizedBox(width: 8),
                          Text('Qty: ${item.quantity}',
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
                          const SizedBox(width: 12),
                          Text('$currencySymbol${item.total}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Continue Shopping
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Continue Shopping',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isAmount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoftColor)),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: isAmount ? AppColors.goldColor : AppColors.inkColor)),
      ],
    );
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'completed': return 'Completed';
      case 'processing': return 'Processing';
      case 'pending': return 'Pending Payment';
      case 'on-hold': return 'On Hold';
      case 'cancelled': return 'Cancelled';
      case 'refunded': return 'Refunded';
      case 'failed': return 'Failed';
      default: return status.replaceAll('-', ' ').split(' ').map((w) =>
          w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
    }
  }
}
