import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

class LocationProvider with ChangeNotifier {
  static const _locationKey = 'user_location';
  final StorageService _storage;

  String _city = 'London';
  String _country = 'UK';
  bool _isLoading = false;

  LocationProvider({required StorageService storage}) : _storage = storage;

  String get city => _city;
  String get country => _country;
  String get displayLocation => '$_city, $_country';
  bool get isLoading => _isLoading;

  final List<Map<String, String>> _availableLocations = const [
    {'city': 'London', 'country': 'UK'},
    {'city': 'Birmingham', 'country': 'UK'},
    {'city': 'Manchester', 'country': 'UK'},
    {'city': 'Leeds', 'country': 'UK'},
    {'city': 'Bournemouth', 'country': 'UK'},
    {'city': 'Edinburgh', 'country': 'UK'},
    {'city': 'Cardiff', 'country': 'UK'},
    {'city': 'Belfast', 'country': 'UK'},
  ];

  List<Map<String, String>> get availableLocations => _availableLocations;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    final saved = await _storage.getLocation();
    if (saved != null) {
      final parts = saved.split(', ');
      if (parts.length == 2) {
        _city = parts[0];
        _country = parts[1];
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  void setLocation(String city, String country) {
    _city = city;
    _country = country;
    _storage.saveLocation('$city, $country');
    notifyListeners();
  }
}
