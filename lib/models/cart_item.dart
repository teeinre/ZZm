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

  CartItem({
    required this.cartItemId,
    required this.product,
    this.quantity = 1,
    this.variationId,
    this.subscriptionInterval,
  });

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
    );
  }

  @override
  List<Object?> get props =>
      [cartItemId, product, quantity, variationId, subscriptionInterval];
}
