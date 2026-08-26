import 'package:equatable/equatable.dart';

/// A Dokan vendor payment link (a pending WC_Order with a shareable pay URL).
///
/// Mirrors the `format_link_data()` structure returned by the Dokan Payment
/// Links plugin, exposed to the app through the `vendor-bridge/v1/payment-links`
/// REST route (`server/mu-plugin/zzmore-payment-links.php`).
class PaymentLink extends Equatable {
  final int id;
  final String label;
  final double amount;
  final String currency;
  final String status;
  final bool needsShipping;
  final String? deliveryNote;
  final String payUrl;
  final String createdDate;
  final String expires;
  final int expiresTimestamp;
  final bool isExpired;
  final bool isPaid;
  final bool isCancellable;

  const PaymentLink({
    required this.id,
    required this.label,
    required this.amount,
    required this.currency,
    required this.status,
    required this.needsShipping,
    required this.deliveryNote,
    required this.payUrl,
    required this.createdDate,
    required this.expires,
    required this.expiresTimestamp,
    required this.isExpired,
    required this.isPaid,
    required this.isCancellable,
  });

  factory PaymentLink.fromJson(Map<String, dynamic> json) {
    return PaymentLink(
      id: _toInt(json['id']),
      label: json['label']?.toString() ?? 'Payment',
      amount: _toDouble(json['amount']),
      currency: json['currency']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      needsShipping: json['needs_shipping'] == true || json['needs_shipping'] == 1,
      deliveryNote: json['delivery_note']?.toString(),
      payUrl: json['pay_url']?.toString() ?? '',
      createdDate: json['created_date']?.toString() ?? '',
      expires: json['expires']?.toString() ?? '',
      expiresTimestamp: _toInt(json['expires_timestamp']),
      isExpired: json['is_expired'] == true || json['is_expired'] == 1,
      isPaid: json['is_paid'] == true || json['is_paid'] == 1,
      isCancellable: json['is_cancellable'] == true || json['is_cancellable'] == 1,
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
        label,
        amount,
        currency,
        status,
        needsShipping,
        deliveryNote,
        payUrl,
        createdDate,
        expires,
        expiresTimestamp,
        isExpired,
        isPaid,
        isCancellable,
      ];
}
