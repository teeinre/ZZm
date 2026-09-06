import 'package:equatable/equatable.dart';

/// A single available booking slot returned by the WooCommerce Bookings
/// `wc-bookings/v1/products/slots` endpoint.
class BookingSlot extends Equatable {
  final int productId;

  /// Slot start time (parsed from the `Y-m-dTH:i` server format).
  final DateTime date;

  /// Duration of the slot in the product's duration unit.
  final int duration;

  /// Number of remaining places available in this slot.
  final int available;

  /// Number of places already booked in this slot.
  final int booked;

  const BookingSlot({
    required this.productId,
    required this.date,
    required this.duration,
    required this.available,
    required this.booked,
  });

  bool get isAvailable => available > 0;

  factory BookingSlot.fromJson(Map<String, dynamic> json) {
    return BookingSlot(
      productId: json['product_id'] is int
          ? json['product_id'] as int
          : int.tryParse(json['product_id']?.toString() ?? '') ?? 0,
      date: _parseDate(json['date']?.toString()),
      duration: json['duration'] is int
          ? json['duration'] as int
          : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      available: json['available'] is int
          ? json['available'] as int
          : int.tryParse(json['available']?.toString() ?? '') ?? 0,
      booked: json['booked'] is int
          ? json['booked'] as int
          : int.tryParse(json['booked']?.toString() ?? '') ?? 0,
    );
  }

  static DateTime _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    // Server returns e.g. "2026-08-23T14:00" — append seconds if missing.
    final normalized = raw.length == 16 ? '${raw}:00' : raw;
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  @override
  List<Object?> get props => [productId, date, duration, available, booked];
}
