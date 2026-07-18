import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService apiService;
  final StorageService storageService;
  User? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;
  bool _isVendor = false;

  AuthProvider({
    required this.apiService,
    required this.storageService,
  });

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isVendor => _isVendor;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      final token = await storageService.getAuthToken();
      if (token != null) {
        apiService.setAuthToken(token);
        final userData = await storageService.getUserData();
        if (userData['userId'] != null) {
          _user = User(
            id: int.tryParse(userData['userId'] ?? '0') ?? 0,
            email: userData['email'] ?? '',
            username: userData['displayName'],
            token: token,
            role: userData['role'],
            vendorStoreId: int.tryParse(userData['vendor_store_id'] ?? ''),
          );
          _isAuthenticated = true;
          _isVendor = userData['role'] == 'vendor' ||
              (int.tryParse(userData['vendor_store_id'] ?? '') ?? 0) > 0;
        } else {
          await storageService.deleteAuthToken();
          apiService.clearAuthToken();
          _isAuthenticated = false;
        }
      }
    } catch (_) {
      _isAuthenticated = false;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String usernameOrEmail, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      User? user;
      // If input contains '@', try email-based login first
      if (usernameOrEmail.contains('@')) {
        user = await apiService.loginWithEmail(usernameOrEmail, password);
      }
      // Fall back to username-based login
      user ??= await apiService.login(usernameOrEmail, password);

      if (user != null && user.token != null) {
        _user = user;
        _isAuthenticated = true;
        apiService.setAuthToken(user.token!);

        // Detect vendor role
        if (user.isVendor) {
          _isVendor = true;
          _user = user;
        } else {
          // Check Dokan store
          try {
            final store = await apiService.getVendorStoreByUserId(user.id);
            if (store != null && store['id'] != null) {
              _isVendor = true;
              _user = User(
                id: user.id,
                email: user.email,
                firstName: user.firstName,
                lastName: user.lastName,
                username: user.username,
                token: user.token,
                role: 'vendor',
                vendorStoreId: store['id'] is int
                    ? store['id'] as int
                    : int.tryParse(store['id'].toString()),
              );
            }
          } catch (_) {
            _isVendor = false;
          }
        }

        await storageService.saveAuthToken(user.token!);
        // Save user data with vendor info
        await storageService.saveUserData(
          user.id.toString(),
          user.email,
          displayName: user.username ?? user.email,
          extraData: {
            'role': _user!.role,
            'vendor_store_id': _user!.vendorStoreId?.toString(),
          },
        );
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Invalid credentials';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginAsVendor(String email, String password) async {
    final success = await login(email, password);
    if (success && !_isVendor) {
      _errorMessage = 'This account is not a vendor. Please register as a vendor first.';
      _isAuthenticated = false;
      _user = null;
      _isVendor = false;
      notifyListeners();
      return false;
    }
    return success;
  }

  Future<void> logout() async {
    _user = null;
    _isAuthenticated = false;
    _isVendor = false;
    apiService.clearAuthToken();
    await storageService.deleteAuthToken();
    await storageService.clearAll();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
