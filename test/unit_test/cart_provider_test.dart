import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:zzmore_app/providers/cart_provider.dart';
import 'package:zzmore_app/cache/hive_service.dart';
import 'package:zzmore_app/models/product.dart';

/// In-memory HiveService fake that only implements the cart methods the
/// CartProvider exercises. `Fake` provides safe no-op defaults for the rest.
class FakeHiveService extends Fake implements HiveService {
  List<Map<String, dynamic>> _cart = [];

  @override
  List<Map<String, dynamic>> getCart() => List<Map<String, dynamic>>.from(_cart);

  @override
  Future<void> saveCart(List<Map<String, dynamic>> cartItems) async {
    _cart = List<Map<String, dynamic>>.from(cartItems);
  }
}

void main() {
  group('CartProvider', () {
    late CartProvider cartProvider;
    late FakeHiveService hiveService;

    setUp(() {
      hiveService = FakeHiveService();
      cartProvider = CartProvider(hiveService: hiveService);
    });

    test('initial state should be empty cart', () {
      expect(cartProvider.cartItems, isEmpty);
      expect(cartProvider.itemCount, 0);
    });

    test('addToCart should add item to cart', () async {
      final product = Product(
        id: 1,
        name: 'Test Product',
        price: '10.99',
        onSale: false,
        inStock: true,
        stockQuantity: 100,
        images: [],
        categories: [],
        ratingCount: 0,
      );

      await cartProvider.addToCart(product);

      expect(cartProvider.cartItems, isNotEmpty);
      expect(cartProvider.itemCount, 1);
    });

    test('subtotal should calculate correctly', () async {
      final product = Product(
        id: 1,
        name: 'Test Product',
        price: '10.00',
        onSale: false,
        inStock: true,
        stockQuantity: 100,
        images: [],
        categories: [],
        ratingCount: 0,
      );

      await cartProvider.addToCart(product);

      expect(cartProvider.subtotal, 10.00);
    });
  });
}
