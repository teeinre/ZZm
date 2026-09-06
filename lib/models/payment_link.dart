import 'package:equatable/equatable.dart';

/// A reusable Dokan vendor payment link.
///
/// Mirrors `DPL_Payment_Link::format_link_data()` + `get_link_stats()` from the
/// Dokan Payment Links plugin (v1.1.x), exposed to the app through the
/// `vendor-bridge/v1/payment-links` REST route.
///
/// A link can be paid by any number of customers; each payment mints its own
/// independent order, so `paidCount`/`orderCount` track usage rather than a
/// single `isPaid` flag.
class PaymentLink extends Equatable {
  final int id;
  final String label;
  final double amount;
  final String currency;
  final String? amountFormatted;
  final String status;
  final bool needsShipping;
  final String? deliveryNote;
  final String payUrl;
  final String createdDate;
  final String expires;
  final int expiresTimestamp;
  final bool isExpired;
  final bool isCancelled;
  final bool isCancellable;
  final int orderCount;
  final int paidCount;
  final double totalPaid;

  const PaymentLink({
    required this.id,
    required this.label,
    required this.amount,
    required this.currency,
    this.amountFormatted,
    required this.status,
    required this.needsShipping,
    required this.deliveryNote,
    required this.payUrl,
    required this.createdDate,
    required this.expires,
    required this.expiresTimestamp,
    required this.isExpired,
    required this.isCancelled,
    required this.isCancellable,
    required this.orderCount,
    required this.paidCount,
    required this.totalPaid,
  });

  factory PaymentLink.fromJson(Map<String, dynamic> json) {
    return PaymentLink(
      id: _toInt(json['id']),
      label: json['label']?.toString() ?? 'Payment',
      amount: _toDouble(json['amount']),
      currency: json['currency']?.toString() ?? '',
      amountFormatted: json['amount_formatted']?.toString(),
      status: json['status']?.toString() ?? 'active',
      needsShipping: _toBool(json['needs_shipping']),
      deliveryNote: json['delivery_note']?.toString(),
      payUrl: json['pay_url']?.toString() ?? '',
      createdDate: json['created_date']?.toString() ?? '',
      expires: json['expires']?.toString() ?? '',
      expiresTimestamp: _toInt(json['expires_timestamp']),
      isExpired: _toBool(json['is_expired']),
      isCancelled: _toBool(json['is_cancelled']),
      isCancellable: _toBool(json['is_cancellable']),
      orderCount: _toInt(json['order_count']),
      paidCount: _toInt(json['paid_count']),
      totalPaid: _toDouble(json['total_paid']),
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

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    return v == 1 || v == '1' || v == 'yes' || v == 'true';
  }

  @override
  List<Object?> get props => [
        id,
        label,
        amount,
        currency,
        amountFormatted,
        status,
        needsShipping,
        deliveryNote,
        payUrl,
        createdDate,
        expires,
        expiresTimestamp,
        isExpired,
        isCancelled,
        isCancellable,
        orderCount,
        paidCount,
        totalPaid,
      ];
}
