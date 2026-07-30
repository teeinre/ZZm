import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
      debugPrint('[Currency] Fetching WooCommerce currency settings…');
      final settings = await api.getWooCommerceSettings();
      // WooCommerce settings IDs use woocommerce_ prefix
      if (settings['woocommerce_currency'] != null) {
        _currencyCode = settings['woocommerce_currency']?.toString() ?? 'GBP';
      }
      if (settings['woocommerce_currency_pos'] != null) {
        _currencyPosition = settings['woocommerce_currency_pos']?.toString() ?? 'left';
      }
      if (settings['woocommerce_price_num_decimals'] != null) {
        _decimals = int.tryParse(settings['woocommerce_price_num_decimals']?.toString() ?? '2') ?? 2;
      }
      if (settings['woocommerce_price_thousand_sep'] != null) {
        _thousandSeparator = settings['woocommerce_price_thousand_sep']?.toString() ?? ',';
      }
      if (settings['woocommerce_price_decimal_sep'] != null) {
        _decimalSeparator = settings['woocommerce_price_decimal_sep']?.toString() ?? '.';
      }
      // Derive the currency symbol from the code if not explicitly provided
      _currencySymbol = _getCurrencySymbol(_currencyCode);
      _loaded = true;
      debugPrint('[Currency] Loaded: $_currencyCode $_currencySymbol (pos=$_currencyPosition, decimals=$_decimals)');
      notifyListeners();
    } catch (e) {
      debugPrint('[Currency] Failed to load settings: $e. Using defaults (GBP).');
      _loaded = true;
      notifyListeners();
    }
  }

  /// Derive a currency symbol from a 3-letter ISO currency code.
  String _getCurrencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'GBP': return '\u00A3';  // £
      case 'USD': return '\u0024';  // $
      case 'EUR': return '\u20AC';  // €
      case 'NGN': return '\u20A6';  // ₦
      case 'JPY': return '\u00A5';  // ¥
      case 'CAD': return '\u0043\u0024'; // C$
      case 'AUD': return '\u0041\u0024'; // A$
      case 'INR': return '\u20B9';  // ₹
      case 'AED': return '\u0625\u002E\u062F'; // إ.د
      default:   return '$code ';   // fallback: code + space
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
