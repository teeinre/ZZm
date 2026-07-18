import 'package:equatable/equatable.dart';

class Vendor extends Equatable {
  final int id;
  final String name;
  final String? email;
  final String? tag;
  final double rating;
  final int ratingCount;
  final String? color;
  final String? image;
  final bool verified;

  const Vendor({
    required this.id,
    required this.name,
    this.email,
    this.tag,
    required this.rating,
    required this.ratingCount,
    this.color,
    this.image,
    this.verified = true,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        tag,
        rating,
        ratingCount,
        color,
        image,
        verified,
      ];
}
