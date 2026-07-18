import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/category.dart';

class HiveService {
  static const String productsBox = 'products';
  static const String categoriesBox = 'categories';
  static const String cartBox = 'cart';
  static const String settingsBox = 'settings';

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    await Hive.openBox(productsBox);
    await Hive.openBox(categoriesBox);
    await Hive.openBox(cartBox);
    await Hive.openBox(settingsBox);
    _isInitialized = true;
  }

  Box get productsBoxInstance => Hive.box(productsBox);
  Box get categoriesBoxInstance => Hive.box(categoriesBox);
  Box get cartBoxInstance => Hive.box(cartBox);
  Box get settingsBoxInstance => Hive.box(settingsBox);

  Future<void> cacheProducts(List<Product> products) async {
    final box = productsBoxInstance;
    for (final product in products) {
      await box.put(product.id, product.toJson());
    }
  }

  List<Product> getCachedProducts() {
    final box = productsBoxInstance;
    return box.values
        .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> cacheCategories(List<Category> categories) async {
    final box = categoriesBoxInstance;
    for (final category in categories) {
      await box.put(category.id, category.toJson());
    }
  }

  List<Category> getCachedCategories() {
    final box = categoriesBoxInstance;
    return box.values
        .map((json) => Category.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> saveCart(List<Map<String, dynamic>> cartItems) async {
    final box = cartBoxInstance;
    await box.put('items', cartItems);
  }

  List<Map<String, dynamic>> getCart() {
    final box = cartBoxInstance;
    final items = box.get('items', defaultValue: <Map<String, dynamic>>[]);
    return List<Map<String, dynamic>>.from(items);
  }

  Future<void> saveString(String key, String value) async {
    await settingsBoxInstance.put(key, value);
  }

  String? getString(String key) {
    return settingsBoxInstance.get(key);
  }

  Future<void> remove(String key) async {
    await settingsBoxInstance.delete(key);
  }

  Future<void> clearAll() async {
    await productsBoxInstance.clear();
    await categoriesBoxInstance.clear();
    await cartBoxInstance.clear();
  }

  Future<void> close() async {
    await Hive.close();
  }
}
