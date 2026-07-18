import 'package:equatable/equatable.dart';
import 'product.dart';

class CartItem extends Equatable {
  final String cartItemId;
  final Product product;
  int quantity;
  final String? variationId;

  CartItem({
    required this.cartItemId,
    required this.product,
    this.quantity = 1,
    this.variationId,
  });

  double get totalPrice {
    final price = double.tryParse(product.price) ?? 0.0;
    return price * quantity;
  }

  @override
  List<Object?> get props => [cartItemId, product, quantity, variationId];
}
