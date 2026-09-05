import 'package:equatable/equatable.dart';
import 'product.dart';

/// Valid billing intervals for subscriptions.
enum SubscriptionInterval { weekly, monthly, annual }

class CartItem extends Equatable {
  final String cartItemId;
  final Product product;
  int quantity;
  final String? variationId;

  /// Subscription interval override (for subscription products that let
  /// the customer choose between weekly / monthly / annual tiers).
  final SubscriptionInterval? subscriptionInterval;

  /// Booking slot start time (for bookable products).
  final DateTime? bookingDate;

  /// Booking resource ID (for bookable products that require resources).
  final int? bookingResourceId;

  /// Person count selected for the booking (defaults to 1 if unset).
  final int? bookingPersonsCount;

  CartItem({
    required this.cartItemId,
    required this.product,
    this.quantity = 1,
    this.variationId,
    this.subscriptionInterval,
    this.bookingDate,
    this.bookingResourceId,
    this.bookingPersonsCount,
  });

  /// Payload sent to the Store API `booking_configuration` field when adding
  /// this item to the server-side cart. The plugin expects `date` in the
  /// format `Y-m-d H:i:s`.
  Map<String, dynamic>? get bookingConfiguration {
    if (bookingDate == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${bookingDate!.year}-${two(bookingDate!.month)}-'
        '${two(bookingDate!.day)} ${two(bookingDate!.hour)}:'
        '${two(bookingDate!.minute)}:${two(bookingDate!.second)}';
    return <String, dynamic>{
      'date': dateStr,
      if (bookingResourceId != null) 'resource_id': bookingResourceId,
      if (bookingPersonsCount != null) 'persons': bookingPersonsCount,
    };
  }

  /// Human-readable label for the selected booking slot.
  String? get bookingLabel {
    if (bookingDate == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${bookingDate!.year}-${two(bookingDate!.month)}-${two(bookingDate!.day)}';
    final time = '${two(bookingDate!.hour)}:${two(bookingDate!.minute)}';
    return '$date at $time';
  }


  double get _basePrice {
    final price = double.tryParse(product.price) ?? 0.0;
    return price;
  }

  /// Total price after applying any interval multiplier.
  double get totalPrice {
    final base = _basePrice;
    double factor = 1.0;
    switch (subscriptionInterval) {
      case SubscriptionInterval.weekly:
        factor = 1.0;
        break;
      case SubscriptionInterval.monthly:
        factor = 4.0;
        break;
      case SubscriptionInterval.annual:
        factor = 42.0;
        break;
      case null:
        factor = 1.0;
        break;
    }
    return base * quantity * factor;
  }

  /// Human-readable label for the chosen subscription interval.
  String? get intervalLabel {
    switch (subscriptionInterval) {
      case SubscriptionInterval.weekly:
        return 'Per week';
      case SubscriptionInterval.monthly:
        return 'Per month';
      case SubscriptionInterval.annual:
        return 'Per year';
      case null:
        return product.billingIntervalLabel != null
            ? 'Per ${product.billingIntervalLabel!.toLowerCase()}'
            : null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'cartItemId': cartItemId,
      'product': product.toJson(),
      'quantity': quantity,
      'variationId': variationId,
      'subscriptionInterval': subscriptionInterval?.name,
      'bookingDate': bookingDate?.toIso8601String(),
      'bookingResourceId': bookingResourceId,
      'bookingPersonsCount': bookingPersonsCount,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final subName = json['subscriptionInterval']?.toString();
    SubscriptionInterval? interval;
    if (subName != null) {
      for (final v in SubscriptionInterval.values) {
        if (v.name == subName) {
          interval = v;
          break;
        }
      }
    }
    return CartItem(
      cartItemId: json['cartItemId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      product: Product.fromJson(
          Map<String, dynamic>.from(json['product'] ?? {})),
      quantity: json['quantity'] is int
          ? json['quantity'] as int
          : int.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      variationId: json['variationId']?.toString(),
      subscriptionInterval: interval,
      bookingDate: json['bookingDate'] != null
          ? DateTime.tryParse(json['bookingDate'].toString())
          : null,
      bookingResourceId: json['bookingResourceId'] is int
          ? json['bookingResourceId'] as int
          : int.tryParse(json['bookingResourceId']?.toString() ?? ''),
      bookingPersonsCount: json['bookingPersonsCount'] is int
          ? json['bookingPersonsCount'] as int
          : int.tryParse(json['bookingPersonsCount']?.toString() ?? ''),
    );
  }

  @override
  List<Object?> get props => [
        cartItemId,
        product,
        quantity,
        variationId,
        subscriptionInterval,
        bookingDate,
        bookingResourceId,
        bookingPersonsCount,
      ];
}
