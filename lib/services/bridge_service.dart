import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bridge between Flutter app and WooCommerce/WordPress WebView checkout.
///
/// Talks to the "webview-checkout-bridge" PHP plugin installed on the
/// WordPress server. The bridge:
///   1. Generates a single-use token linked to the authenticated user + cart
///   2. WebView loads the /enter endpoint → PHP sets auth cookie, builds cart
///   3. After checkout, fetches order details via authenticated REST endpoint
///
/// Never embeds WooCommerce API keys in the Flutter app — all confidential
/// actions happen server-side.
class BridgeService {
  BridgeService({
    required this.baseUrl,
    required this.authHeaderProvider,
  });

  /// e.g. https://zzmore.store
  final String baseUrl;

  /// Returns the Authorization header value for the CURRENT logged-in user,
  /// e.g. "Bearer <jwt>".
  final Future<String> Function() authHeaderProvider;

  /// POSTs the cart items to the bridge and returns a single-use token.
  /// Call this right before opening the WebView checkout.
  Future<String> generateBridgeToken(List<BridgeCartItem> items) async {
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

  /// Build the URL loaded in the WebView. The PHP /enter endpoint receives
  /// the token, verifies it, logs the user in via cookie, rebuilds the cart,
  /// and redirects to the WooCommerce checkout page.
  String buildWebviewEntryUrl(String token) {
    return '$baseUrl/wp-json/bridge/v1/enter?token=$token';
  }

  /// Called once the WebView reaches the order-received page, to pull full
  /// order details back into native Flutter UI.
  Future<BridgeOrderDetails> fetchOrder(int orderId) async {
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

    return BridgeOrderDetails.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

/// Minimal cart item shape expected by the PHP bridge endpoint.
/// Distinct from the app's CartItem model to avoid implicit dependencies.
class BridgeCartItem {
  BridgeCartItem({
    required this.productId,
    required this.quantity,
    this.variationId,
  });
  final int productId;
  final int quantity;
  final int? variationId;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
        'variation_id': variationId ?? 0,
      };
}

/// Full order details returned by the bridge after checkout completes.
class BridgeOrderDetails {
  BridgeOrderDetails({
    required this.id,
    required this.status,
    required this.total,
    required this.currency,
    required this.paymentMethod,
    required this.dateCreated,
    required this.items,
  });

  final int id;
  final String status;
  final String total;
  final String currency;
  final String paymentMethod;
  final String? dateCreated;
  final List<BridgeOrderLineItem> items;

  factory BridgeOrderDetails.fromJson(Map<String, dynamic> json) {
    return BridgeOrderDetails(
      id: json['id'] as int,
      status: json['status'] as String,
      total: json['total'] as String,
      currency: json['currency'] as String,
      paymentMethod: (json['payment_method'] ?? '') as String,
      dateCreated: json['date_created'] as String?,
      items: (json['items'] as List)
          .map((e) => BridgeOrderLineItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BridgeOrderLineItem {
  BridgeOrderLineItem({
    required this.name,
    required this.quantity,
    required this.total,
  });
  final String name;
  final int quantity;
  final String total;

  factory BridgeOrderLineItem.fromJson(Map<String, dynamic> json) =>
      BridgeOrderLineItem(
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        total: json['total'] as String,
      );
}
