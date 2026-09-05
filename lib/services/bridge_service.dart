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
    this.bookingStartDate,   // booking: "2026-09-20" (YYYY-MM-DD) or "2026-09-20 14:00"
    this.bookingStartTime,   // booking: "14:00" (HH:MM)
    this.bookingEndDate,     // booking optional: "2026-09-21"
    this.bookingEndTime,     // booking optional: "15:00"
    this.bookingResourceId,  // booking: ID of selected resource (0 if none)
    this.bookingPersons,     // booking: persons count (1 by default)
    this.bookingConfiguration, // booking: flat legacy object for wc_bookings_compat
  });
  final int productId;
  final int quantity;
  final int? variationId;
  final String? bookingStartDate;
  final String? bookingStartTime;
  final String? bookingEndDate;
  final String? bookingEndTime;
  final int? bookingResourceId;
  final int? bookingPersons;
  final Map<String, dynamic>? bookingConfiguration;

  Map<String, dynamic> toJson() {
    final base = <String, dynamic>{
      'product_id': productId,
      'quantity': quantity,
      'variation_id': variationId ?? 0,
    };
    // Attach booking fields only when present (PHP bridge's add_to_cart logic
    // looks for these keys and passes them through to WooCommerce Bookings
    // cart item meta hooks when rebuilding the cart from the token).
    if (bookingStartDate != null) base['booking_start_date'] = bookingStartDate;
    if (bookingStartTime != null) base['booking_start_time'] = bookingStartTime;
    if (bookingEndDate != null)   base['booking_end_date'] = bookingEndDate;
    if (bookingEndTime != null)   base['booking_end_time'] = bookingEndTime;
    if (bookingResourceId != null && bookingResourceId! > 0) {
      base['booking_resource_id'] = bookingResourceId!;
    }
    if (bookingPersons != null && bookingPersons! > 0) {
      base['booking_persons'] = bookingPersons!;
    }
    if (bookingConfiguration != null) {
      base['booking_configuration'] = bookingConfiguration!;
    }
    // Legacy shape for very old Bookings / custom extensions.
    if (bookingStartDate != null || bookingStartTime != null || (bookingResourceId ?? 0) > 0 || bookingConfiguration != null) {
      base['_legacy_booking'] = <String, dynamic>{
        'start_date': bookingStartDate ?? '',
        'start_time': bookingStartTime ?? '',
        'end_date': bookingEndDate ?? '',
        'end_time': bookingEndTime ?? '',
        'resource_id': bookingResourceId ?? 0,
        'persons': bookingPersons ?? 1,
        if (bookingConfiguration != null) 'configuration': bookingConfiguration!,
      };
    }
    return base;
  }
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
