import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:zzmore_app/providers/cart_provider.dart';
import 'package:zzmore_app/cache/hive_service.dart';
import 'package:zzmore_app/models/product.dart';

class MockHiveService extends Mock implements HiveService {}

void main() {
  group('CartProvider', () {
    late CartProvider cartProvider;
    late MockHiveService mockHiveService;

    setUp(() {
      mockHiveService = MockHiveService();
      when(mockHiveService.getCart()).thenReturn([]);
      cartProvider = CartProvider(hiveService: mockHiveService);
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
