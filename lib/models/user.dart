import 'package:equatable/equatable.dart';

class User extends Equatable {
  final int id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? avatarUrl;
  final String? token;
  final String? role;
  final int? vendorStoreId;

  const User({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.username,
    this.avatarUrl,
    this.token,
    this.role,
    this.vendorStoreId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email']?.toString() ?? json['user_email']?.toString() ?? '',
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      username: json['username']?.toString() ?? json['user_display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString() ?? json['user_role']?.toString(),
      vendorStoreId: json['vendor_store_id'] is int
          ? json['vendor_store_id'] as int
          : int.tryParse(json['vendor_store_id']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'avatar_url': avatarUrl,
      'role': role,
      'vendor_store_id': vendorStoreId,
    };
  }

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return username ?? email;
  }

  bool get isVendor =>
      role == 'vendor' || role == 'seller' || vendorStoreId != null;

  @override
  List<Object?> get props => [
        id,
        email,
        firstName,
        lastName,
        username,
        avatarUrl,
        token,
        role,
        vendorStoreId,
      ];
}
