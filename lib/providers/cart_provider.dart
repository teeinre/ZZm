import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../cache/hive_service.dart';

class CartProvider with ChangeNotifier {
  final HiveService hiveService;
  List<CartItem> _cartItems = [];
  bool _isLoading = false;

  CartProvider({required this.hiveService});

  List<CartItem> get cartItems => _cartItems;
  bool get isLoading => _isLoading;
  int get itemCount => _cartItems.length;

  double get subtotal {
    return _cartItems.fold(
        0.0, (sum, item) => sum + item.totalPrice);
  }

  Future<void> loadCart() async {
    _isLoading = true;
    notifyListeners();
    final cart = hiveService.getCart();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addToCart(Product product, {String? variationId}) async {
    // For variable products, each variation is a separate cart entry
    final existingIndex = _cartItems.indexWhere(
      (item) => item.product.id == product.id && item.variationId == variationId);
    if (existingIndex >= 0) {
      _cartItems[existingIndex].quantity++;
    } else {
      final cartItem = CartItem(
        cartItemId: DateTime.now().millisecondsSinceEpoch.toString(),
        product: product,
        variationId: variationId,
      );
      _cartItems.add(cartItem);
    }
    notifyListeners();
    await _saveCart();
  }

  void removeFromCart(String cartItemId) async {
    _cartItems.removeWhere((item) => item.cartItemId == cartItemId);
    notifyListeners();
    await _saveCart();
  }

  void updateQuantity(String cartItemId, int quantity) async {
    final index = _cartItems.indexWhere((item) => item.cartItemId == cartItemId);
    if (index >= 0) {
      if (quantity <= 0) {
        removeFromCart(cartItemId);
      } else {
        _cartItems[index].quantity = quantity;
        notifyListeners();
        await _saveCart();
      }
    }
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
    _saveCart();
  }

  bool isInCart(int productId) {
    return _cartItems.any((item) => item.product.id == productId);
  }

  CartItem? getCartItem(int productId) {
    try {
      return _cartItems.firstWhere((item) => item.product.id == productId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveCart() async {
    final cartJson = _cartItems.map((item) => {
      'cartItemId': item.cartItemId,
      'product': item.product.toJson(),
      'quantity': item.quantity,
      'variationId': item.variationId,
    }).toList();
    await hiveService.saveCart(cartJson);
  }

  /// Returns the number of unique vendors in the cart.
  /// Dokan supports multi-vendor carts by default (splits orders into sub-orders per vendor).
  int get uniqueVendorCount {
    return _cartItems
        .where((item) => item.product.vendorId != null)
        .map((item) => item.product.vendorId)
        .toSet()
        .length;
  }

  /// Returns distinct vendor names in the cart.
  List<String> get vendorNames {
    return _cartItems
        .where((item) => item.product.vendorName != null)
        .map((item) => item.product.vendorName!)
        .toSet()
        .toList();
  }
}
