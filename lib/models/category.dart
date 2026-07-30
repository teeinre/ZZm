import 'package:equatable/equatable.dart';

class Category extends Equatable {
  final int id;
  final String name;
  final String? slug;
  final String? icon;
  final String? description;
  final String? image;
  final int count;

  const Category({
    required this.id,
    required this.name,
    this.slug,
    this.icon,
    this.description,
    this.image,
    this.count = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug']?.toString(),
      description: json['description']?.toString(),
      image: json['image']?['src']?.toString(),
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'count': count,
    };
  }

  @override
  List<Object?> get props => [id, name, slug, description, image, count];
}
