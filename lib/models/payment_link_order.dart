import 'package:equatable/equatable.dart';

/// A single WooCommerce order minted from a Dokan payment link.
///
/// Mirrors `DPL_Order::format_order_data()` from the Dokan Payment Links
/// plugin, exposed via `GET /vendor-bridge/v1/payment-links/{id}/orders`.
class PaymentLinkOrder extends Equatable {
  final int id;
  final String status;
  final double total;
  final String currency;
  final String customer;
  final String customerName;
  final String customerEmail;
  final String customerUsername;
  final String date;

  const PaymentLinkOrder({
    required this.id,
    required this.status,
    required this.total,
    required this.currency,
    required this.customer,
    required this.customerName,
    required this.customerEmail,
    required this.customerUsername,
    required this.date,
  });

  factory PaymentLinkOrder.fromJson(Map<String, dynamic> json) {
    return PaymentLinkOrder(
      id: _toInt(json['id']),
      status: json['status']?.toString() ?? '',
      total: _toDouble(json['total']),
      currency: json['currency']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerEmail: json['customer_email']?.toString() ?? '',
      customerUsername: json['customer_username']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        status,
        total,
        currency,
        customer,
        customerName,
        customerEmail,
        customerUsername,
        date,
      ];
}
