import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:zzmore_app/services/api_service.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  group('ApiService', () {
    late ApiService apiService;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      apiService = ApiService(client: mockClient);
    });

    test('login should return user on success', () async {
      when(mockClient.post(
        Uri.parse('https://zzmore.store/wp-json/jwt-auth/v1/token'),
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer(
        (_) async => http.Response(
          '{"token": "test-token", "user_email": "test@test.com", "user_id": 1}',
          200,
        ),
      );

      final user = await apiService.login('test', 'test');

      expect(user, isNotNull);
      expect(user?.email, 'test@test.com');
    });

    test('getProducts should return list of products', () async {
      when(mockClient.get(
        Uri.parse('https://zzmore.store/wp-json/wc/v3/products?page=1&per_page=10'),
        headers: anyNamed('headers'),
      )).thenAnswer(
        (_) async => http.Response(
          '[{"id": 1, "name": "Test Product", "price": "10.99", "on_sale": false, "in_stock": true, "stock_quantity": 100, "images": [], "categories": [], "rating_count": 0}]',
          200,
        ),
      );

      final products = await apiService.getProducts();

      expect(products, isNotEmpty);
      expect(products.first.name, 'Test Product');
    });
  });
}
