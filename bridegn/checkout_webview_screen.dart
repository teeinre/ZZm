import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bridge_service.dart';

/// Push this screen when the user taps "Checkout".
/// Usage:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => CheckoutWebviewScreen(
///       bridgeService: bridgeService,
///       cartItems: cartItems,
///     ),
///   ));
class CheckoutWebviewScreen extends StatefulWidget {
  const CheckoutWebviewScreen({
    super.key,
    required this.bridgeService,
    required this.cartItems,
  });

  final BridgeService bridgeService;
  final List<CartItem> cartItems;

  @override
  State<CheckoutWebviewScreen> createState() => _CheckoutWebviewScreenState();
}

class _CheckoutWebviewScreenState extends State<CheckoutWebviewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _handledCompletion = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            _maybeHandleOrderReceived(request.url);
            return NavigationDecision.navigate;
          },
        ),
      );
    _startCheckout();
  }

  Future<void> _startCheckout() async {
    try {
      final token = await widget.bridgeService.generateBridgeToken(widget.cartItems);
      final url = widget.bridgeService.buildWebviewEntryUrl(token);
      await _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start checkout: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  /// WooCommerce redirects to something like:
  /// https://yoursite.com/checkout/order-received/482/?key=wc_order_abc123
  /// We pull the order id out of that path.
  void _maybeHandleOrderReceived(String url) {
    if (_handledCompletion) return;

    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final idx = segments.indexOf('order-received');

    if (idx != -1 && idx + 1 < segments.length) {
      final orderId = int.tryParse(segments[idx + 1]);
      if (orderId != null) {
        _handledCompletion = true;
        _onOrderComplete(orderId);
      }
    }
  }

  Future<void> _onOrderComplete(int orderId) async {
    // Let the thank-you page render briefly, then fetch full details
    // via our own backend (never via WooCommerce keys on-device).
    try {
      final order = await widget.bridgeService.fetchOrder(orderId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order placed, but details could not load: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// Placeholder native order details screen — replace with your real UI.
class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.order});
  final OrderDetails order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order #${order.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Status: ${order.status}'),
          Text('Total: ${order.total} ${order.currency}'),
          Text('Payment: ${order.paymentMethod}'),
          const Divider(height: 32),
          ...order.items.map(
            (i) => ListTile(
              title: Text(i.name),
              subtitle: Text('Qty: ${i.quantity}'),
              trailing: Text(i.total),
            ),
          ),
        ],
      ),
    );
  }
}
