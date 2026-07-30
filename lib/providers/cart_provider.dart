import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../cache/hive_service.dart';
import '../services/api_service.dart';

/// Manages the shopping cart with dual persistence:
///   1. Local Hive storage (instant, offline-safe)
///   2. WooCommerce Store API sync (server-side, cross-session)
///
/// On every cart mutation (add/remove/update quantity/clear), the local Hive
/// copy is saved immediately AND the Store API cart is synced asynchronously.
/// This ensures the cart survives across app restarts and device switches.
class CartProvider with ChangeNotifier {
  final HiveService hiveService;
  ApiService? _storeApi;
  List<CartItem> _cartItems = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _syncError;

  CartProvider({required this.hiveService, ApiService? apiService}) {
    _storeApi = apiService;
  }

  /// Inject the shared ApiService for Store API cart sync.
  /// Called after initialization if apiService was not available at construction time.
  void setStoreApi(ApiService api) {
    _storeApi = api;
  }

  List<CartItem> get cartItems => _cartItems;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  int get itemCount => _cartItems.length;

  double get subtotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  Future<void> loadCart() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Load local Hive cart (always available)
      final savedItems = hiveService.getCart();
      if (savedItems.isNotEmpty) {
        _cartItems = savedItems.map((item) {
          return CartItem(
            cartItemId: item['cartItemId']?.toString() ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            product: Product.fromJson(
                Map<String, dynamic>.from(item['product'] ?? {})),
            quantity: item['quantity'] is int
                ? item['quantity'] as int
                : int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
            variationId: item['variationId']?.toString(),
          );
        }).toList();
      }

      // 2. Try to pull server cart (Store API) and merge if newer
      if (_storeApi != null && _cartItems.isEmpty) {
        await _pullServerCart();
      }
    } catch (_) {
      _cartItems = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Pull the WooCommerce Store API cart and merge into local state.
  /// Only used as fallback when local cart is empty.
  Future<void> _pullServerCart() async {
    try {
      await _storeApi!.fetchStoreNonce();
      final serverCart = await _storeApi!.getStoreCart();
      if (serverCart == null) return;

      final items = serverCart['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return;

      final merged = <CartItem>[];
      for (final item in items) {
        final map = Map<String, dynamic>.from(item);
        final productId = map['id'];
        final qty = map['quantity'] ?? 1;

        // Build a minimal Product from the server cart item
        final product = Product(
          id: productId is int ? productId : int.tryParse(productId.toString()) ?? 0,
          name: map['name']?.toString() ?? '',
          price: (map['prices']?['price'] ?? '0').toString(),
          onSale: false,
          inStock: true,
          stockQuantity: 0,
          images: (map['images'] as List<dynamic>?)
              ?.map((img) => (img is Map ? img['src']?.toString() : img.toString()) ?? '')
              .toList() ?? [],
          categories: [],
          ratingCount: 0,
        );

        merged.add(CartItem(
          cartItemId: DateTime.now().millisecondsSinceEpoch.toString(),
          product: product,
          quantity: qty is int ? qty : int.tryParse(qty.toString()) ?? 1,
          variationId: map['variation_id']?.toString(),
        ));
      }

      debugPrint('[CartProvider] Pulled ${merged.length} items from server cart');
      _cartItems = merged;
      await _saveLocalCart();
    } catch (e) {
      debugPrint('[CartProvider] Failed to pull server cart: $e');
    }
  }

  // ── Mutations (all sync to both local + server) ──

  Future<void> addToCart(Product product, {String? variationId}) async {
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
    await _saveLocalCart();
    _syncToServer(product.id, variationId != null ? int.tryParse(variationId) : null);
  }

  Future<void> removeFromCart(String cartItemId) async {
    _cartItems.removeWhere((item) => item.cartItemId == cartItemId);
    notifyListeners();
    await _saveLocalCart();
    // For server sync after removal, re-sync the full cart
    _syncFullCartToServer();
  }

  Future<void> updateQuantity(String cartItemId, int quantity) async {
    final index = _cartItems.indexWhere((item) => item.cartItemId == cartItemId);
    if (index >= 0) {
      if (quantity <= 0) {
        await removeFromCart(cartItemId);
        return;
      }
      _cartItems[index].quantity = quantity;
      notifyListeners();
      await _saveLocalCart();
      _syncFullCartToServer();
    }
  }

  Future<void> clearCart() async {
    _cartItems.clear();
    notifyListeners();
    _saveLocalCart();
    // Also clear server cart
    if (_storeApi != null) {
      _storeApi!.clearStoreCart().catchError((_) {});
    }
  }

  // ── Server sync helpers ──

  /// Sync a single add-to-cart operation to the Store API.
  void _syncToServer(int productId, int? variationId) {
    if (_storeApi == null) return;
    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    _storeApi!.fetchStoreNonce().then((_) {
      return _storeApi!.addToStoreCart(productId, quantity: 1, variationId: variationId);
    }).then((_) {
      _isSyncing = false;
      notifyListeners();
    }).catchError((e) {
      debugPrint('[CartProvider] Sync to server failed: $e');
      _isSyncing = false;
      _syncError = 'Cart not synced to server.';
      notifyListeners();
    });
  }

  /// Full re-sync: clear server cart then re-add all local items.
  void _syncFullCartToServer() {
    if (_storeApi == null) return;
    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    _storeApi!.fetchStoreNonce().then((_) async {
      // Clear then re-add
      await _storeApi!.clearStoreCart();
      for (final item in _cartItems) {
        final vid = item.variationId != null && item.variationId!.isNotEmpty
            ? int.tryParse(item.variationId!)
            : null;
        await _storeApi!.addToStoreCart(
          item.product.id,
          quantity: item.quantity,
          variationId: vid,
        );
      }
      _isSyncing = false;
      notifyListeners();
    }).catchError((e) {
      debugPrint('[CartProvider] Full sync failed: $e');
      _isSyncing = false;
      _syncError = 'Cart not synced to server.';
      notifyListeners();
    });
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

  Future<void> _saveLocalCart() async {
    final cartJson = _cartItems.map((item) => {
      'cartItemId': item.cartItemId,
      'product': item.product.toJson(),
      'quantity': item.quantity,
      'variationId': item.variationId,
    }).toList();
    await hiveService.saveCart(cartJson);
  }

  /// Returns the number of unique vendors in the cart.
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
