import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zzmore_app/services/api_service.dart';

void main() {
  group('ApiService', () {
    test('login should return user on success', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://zzmore.store/wp-json/jwt-auth/v1/token',
        );
        return http.Response(
          jsonEncode({
            'token': 'test-token',
            'user_email': 'test@test.com',
            'user_id': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiService = ApiService(client: mockClient);

      final user = await apiService.login('test', 'test');

      expect(user, isNotNull);
      expect(user?.email, 'test@test.com');
    });

    test('getProducts should return list of published products', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.queryParameters['status'],
          'publish',
        );
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'name': 'Test Product',
              'price': '10.99',
              'on_sale': false,
              'in_stock': true,
              'stock_quantity': 100,
              'images': <dynamic>[],
              'categories': <dynamic>[],
              'rating_count': 0,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiService = ApiService(client: mockClient);

      final products = await apiService.getProducts();

      expect(products, isNotEmpty);
      expect(products.first.name, 'Test Product');
    });
  });
}
