import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _displayNameKey = 'user_display_name';
  static const String _locationKey = 'user_location';
  static const String _savedVendorsKey = 'saved_vendor_ids';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> deleteAuthToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<void> saveUserData(String userId, String email, {String? displayName, Map<String, String?>? extraData}) async {
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _userEmailKey, value: email);
    if (displayName != null) {
      await _storage.write(key: _displayNameKey, value: displayName);
    }
    if (extraData != null) {
      for (final entry in extraData.entries) {
        if (entry.value != null) {
          await _storage.write(key: entry.key, value: entry.value);
        }
      }
    }
  }

  Future<Map<String, String?>> getUserData() async {
    return {
      'userId': await _storage.read(key: _userIdKey),
      'email': await _storage.read(key: _userEmailKey),
      'displayName': await _storage.read(key: _displayNameKey),
      'role': await _storage.read(key: 'role'),
      'vendor_store_id': await _storage.read(key: 'vendor_store_id'),
    };
  }

  // Location persistence
  Future<void> saveLocation(String location) async {
    await _storage.write(key: _locationKey, value: location);
  }

  Future<String?> getLocation() async {
    return await _storage.read(key: _locationKey);
  }

  // ── Saved Vendors ──
  Future<List<int>> getSavedVendorIds() async {
    final raw = await _storage.read(key: _savedVendorsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveVendorFollow(int vendorId) async {
    final ids = await getSavedVendorIds();
    if (!ids.contains(vendorId)) {
      ids.add(vendorId);
      await _storage.write(key: _savedVendorsKey, value: jsonEncode(ids));
    }
  }

  Future<void> removeVendorFollow(int vendorId) async {
    final ids = await getSavedVendorIds();
    ids.remove(vendorId);
    await _storage.write(key: _savedVendorsKey, value: jsonEncode(ids));
  }

  Future<bool> isVendorSaved(int vendorId) async {
    final ids = await getSavedVendorIds();
    return ids.contains(vendorId);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
