import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the WordPress "webview-checkout-bridge" plugin.
class BridgeService {
  BridgeService({required this.baseUrl, required this.authHeaderProvider});

  /// e.g. https://yoursite.com
  final String baseUrl;

  /// Returns the Authorization header value for the CURRENT logged-in user,
  /// e.g. "Bearer <jwt>" or an Application Password basic-auth string.
  /// This is whatever your app already uses to talk to your WP REST API.
  final Future<String> Function() authHeaderProvider;

  /// Cart item shape expected by the PHP endpoint.
  /// Call this right before the user taps "Checkout".
  Future<String> generateBridgeToken(List<CartItem> items) async {
    final auth = await authHeaderProvider();

    final response = await http.post(
      Uri.parse('$baseUrl/wp-json/bridge/v1/generate-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': auth,
      },
      body: jsonEncode({
        'items': items.map((e) => e.toJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to create checkout session (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['token'] as String;
  }

  /// Builds the URL to load in the WebView.
  String buildWebviewEntryUrl(String token) {
    return '$baseUrl/wp-json/bridge/v1/enter?token=$token';
  }

  /// Called once the WebView reaches the order-received page, to pull
  /// full order details back into native UI.
  Future<OrderDetails> fetchOrder(int orderId) async {
    final auth = await authHeaderProvider();

    final response = await http.get(
      Uri.parse('$baseUrl/wp-json/bridge/v1/order/$orderId'),
      headers: {'Authorization': auth},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch order (${response.statusCode}): ${response.body}',
      );
    }

    return OrderDetails.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}

class CartItem {
  CartItem({required this.productId, required this.quantity, this.variationId = 0});
  final int productId;
  final int quantity;
  final int variationId;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
        'variation_id': variationId,
      };
}

class OrderDetails {
  OrderDetails({
    required this.id,
    required this.status,
    required this.total,
    required this.currency,
    required this.paymentMethod,
    required this.items,
  });

  final int id;
  final String status;
  final String total;
  final String currency;
  final String paymentMethod;
  final List<OrderLineItem> items;

  factory OrderDetails.fromJson(Map<String, dynamic> json) {
    return OrderDetails(
      id: json['id'] as int,
      status: json['status'] as String,
      total: json['total'] as String,
      currency: json['currency'] as String,
      paymentMethod: (json['payment_method'] ?? '') as String,
      items: (json['items'] as List)
          .map((e) => OrderLineItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OrderLineItem {
  OrderLineItem({required this.name, required this.quantity, required this.total});
  final String name;
  final int quantity;
  final String total;

  factory OrderLineItem.fromJson(Map<String, dynamic> json) => OrderLineItem(
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        total: json['total'] as String,
      );
}
