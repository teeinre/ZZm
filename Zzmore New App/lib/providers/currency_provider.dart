import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CurrencyProvider with ChangeNotifier {
  String _currencyCode = 'GBP';
  String _currencySymbol = '\u00A3'; // £
  String _currencyPosition = 'left';
  int _decimals = 2;
  String _thousandSeparator = ',';
  String _decimalSeparator = '.';
  bool _loaded = false;

  String get currencyCode => _currencyCode;
  String get currencySymbol => _currencySymbol;
  bool get loaded => _loaded;

  /// Fetch WooCommerce currency settings
  Future<void> loadCurrency() async {
    try {
      final api = ApiService();
      final settings = await api.getWooCommerceSettings();
      if (settings['currency'] != null) {
        _currencyCode = settings['currency']?.toString() ?? 'GBP';
      }
      if (settings['currency_symbol'] != null) {
        _currencySymbol = settings['currency_symbol']?.toString() ?? '\u00A3';
      }
      if (settings['currency_position'] != null) {
        _currencyPosition = settings['currency_position']?.toString() ?? 'left';
      }
      if (settings['price_num_decimals'] != null) {
        _decimals = int.tryParse(settings['price_num_decimals']?.toString() ?? '2') ?? 2;
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Format a price string according to WooCommerce settings
  String formatPrice(double amount) {
    final formatted = amount.toStringAsFixed(_decimals);
    final parts = formatted.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';

    // Add thousand separator
    if (_thousandSeparator.isNotEmpty) {
      final buffer = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) {
          buffer.write(_thousandSeparator);
        }
        buffer.write(intPart[i]);
      }
      intPart = buffer.toString();
    }

    final number = '$intPart$_decimalSeparator$decPart';

    switch (_currencyPosition) {
      case 'left':
        return '$_currencySymbol$number';
      case 'right':
        return '$number$_currencySymbol';
      case 'left_space':
        return '$_currencySymbol $number';
      case 'right_space':
        return '$number $_currencySymbol';
      default:
        return '$_currencySymbol$number';
    }
  }
}
