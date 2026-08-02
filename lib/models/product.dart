import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final int id;
  final String name;
  final String? type;
  final String? description;
  final String? shortDescription;
  final String? sku;
  final String price;
  final String? regularPrice;
  final String? salePrice;
  final bool onSale;
  final bool inStock;
  final int stockQuantity;
  final List<String> images;
  final List<ProductCategory> categories;
  final String? vendorName;
  final int? vendorId;
  final double? rating;
  final int ratingCount;
  final String? icon;
  final String? color;

  // WooCommerce Subscriptions plugin fields
  final bool isSubscription;
  final String? subscriptionPeriod; // day, week, month, year
  final int? subscriptionPeriodInterval;
  final String? subscriptionSignUpFee;
  final int? subscriptionTrialLength;
  final String? subscriptionTrialPeriod;

  const Product({
    required this.id,
    required this.name,
    this.type,
    this.description,
    this.shortDescription,
    this.sku,
    required this.price,
    this.regularPrice,
    this.salePrice,
    required this.onSale,
    required this.inStock,
    required this.stockQuantity,
    required this.images,
    required this.categories,
    this.vendorName,
    this.vendorId,
    this.rating,
    required this.ratingCount,
    this.icon,
    this.color,
    this.isSubscription = false,
    this.subscriptionPeriod,
    this.subscriptionPeriodInterval,
    this.subscriptionSignUpFee,
    this.subscriptionTrialLength,
    this.subscriptionTrialPeriod,
  });

  bool get isVariable => type == 'variable';
  bool get isSubscriptionProduct =>
      isSubscription || type == 'subscription' || type == 'variable-subscription';

  String? get billingIntervalLabel {
    final p = subscriptionPeriod;
    final i = subscriptionPeriodInterval ?? 1;
    if (p == null) return null;
    final intervals = {
      'day': i == 1 ? 'Day' : '$i Days',
      'week': i == 1 ? 'Week' : '$i Weeks',
      'month': i == 1 ? 'Month' : '$i Months',
      'year': i == 1 ? 'Year' : '$i Years',
    };
    return intervals[p];
  }

  String? get trialLabel {
    final length = subscriptionTrialLength;
    final period = subscriptionTrialPeriod;
    if (length == null || length <= 0 || period == null) return null;
    final intervals = {
      'day': length == 1 ? 'day free trial' : '$length-day free trial',
      'week': length == 1 ? 'week free trial' : '$length-week free trial',
      'month': length == 1 ? 'month free trial' : '$length-month free trial',
      'year': length == 1 ? 'year free trial' : '$length-year free trial',
    };
    return intervals[period];
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    List<String> images = [];
    if (json['images'] != null && json['images'] is List) {
      images = (json['images'] as List)
          .map((img) => img['src']?.toString() ?? '')
          .toList();
    }

    List<ProductCategory> categories = [];
    if (json['categories'] != null && json['categories'] is List) {
      categories = (json['categories'] as List)
          .map((cat) => ProductCategory.fromJson(Map<String, dynamic>.from(cat)))
          .toList();
    }

    double? rating;
    int ratingCount = 0;
    if (json['average_rating'] != null) {
      rating = double.tryParse(json['average_rating'].toString());
    }
    if (json['rating_count'] != null) {
      ratingCount = (json['rating_count'] is int) 
          ? json['rating_count'] as int 
          : int.tryParse(json['rating_count'].toString()) ?? 0;
    }

    // Extract vendor name and ID from Dokan store data
    String? vendorName;
    int? vendorId;
    if (json['store'] != null && json['store'] is Map) {
      final store = json['store'] as Map<String, dynamic>;
      vendorName = store['shop_name']?.toString() ?? store['name']?.toString();
      vendorId = store['id'] is int ? store['id'] as int : int.tryParse(store['id']?.toString() ?? '');
    }

    final typeStr = json['type']?.toString();
    final bool isSub = (typeStr == 'subscription' ||
        typeStr == 'variable-subscription' ||
        (json['meta_data'] as List<dynamic>?)?.any((m) {
              final mm = m is Map ? Map<String, dynamic>.from(m) : null;
              if (mm == null) return false;
              final k = mm['key']?.toString() ?? '';
              return k.startsWith('_subscription') ||
                  k.contains('subscription_period');
            }) ==
            true);

    // Subscription fields
    final mList = json['meta_data'] as List<dynamic>?;
    final meta = <String, dynamic>{};
    if (mList != null) {
      for (final m in mList) {
        final mm = m is Map ? Map<String, dynamic>.from(m) : null;
        if (mm != null && mm['key'] != null) {
          meta[mm['key'].toString()] = mm['value'];
        }
      }
    }
    final period =
        (meta['_subscription_period'] ?? json['subscription_period']).toString();
    final intervalRaw =
        meta['_subscription_period_interval'] ?? json['subscription_period_interval'];
    final trialRaw =
        meta['_subscription_trial_length'] ?? json['subscription_trial_length'];
    final signUpFee = (meta['_subscription_sign_up_fee'] ?? json['subscription_sign_up_fee'])
        ?.toString();
    final trialPeriod =
        (meta['_subscription_trial_period'] ?? json['subscription_trial_period'])
            .toString();

    return Product(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      type: typeStr,
      shortDescription: json['short_description']?.toString(),
      sku: json['sku']?.toString(),
      price: json['price']?.toString() ?? '0',
      regularPrice: json['regular_price']?.toString(),
      salePrice: json['sale_price']?.toString(),
      onSale: json['on_sale'] as bool? ?? false,
      inStock: json['stock_status']?.toString() == 'instock' ||
          (json['in_stock'] as bool? ?? true),
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      images: images,
      categories: categories,
      vendorName: vendorName,
      vendorId: vendorId,
      rating: rating,
      ratingCount: ratingCount,
      isSubscription: isSub,
      subscriptionPeriod: period.isNotEmpty ? period : null,
      subscriptionPeriodInterval: intervalRaw is int
          ? intervalRaw
          : int.tryParse(intervalRaw?.toString() ?? ''),
      subscriptionSignUpFee: signUpFee?.isNotEmpty == true ? signUpFee : null,
      subscriptionTrialLength:
          trialRaw is int ? trialRaw : int.tryParse(trialRaw?.toString() ?? ''),
      subscriptionTrialPeriod: trialPeriod.isNotEmpty ? trialPeriod : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'short_description': shortDescription,
      'sku': sku,
      'price': price,
      'regular_price': regularPrice,
      'sale_price': salePrice,
      'on_sale': onSale,
      'in_stock': inStock,
      'stock_quantity': stockQuantity,
      'images': images,
      'categories': categories.map((c) => c.toJson()).toList(),
      'vendor_name': vendorName,
      'vendor_id': vendorId,
      'rating': rating,
      'rating_count': ratingCount,
      'is_subscription': isSubscription,
      'subscription_period': subscriptionPeriod,
      'subscription_period_interval': subscriptionPeriodInterval,
      'subscription_sign_up_fee': subscriptionSignUpFee,
      'subscription_trial_length': subscriptionTrialLength,
      'subscription_trial_period': subscriptionTrialPeriod,
    };
  }

  Product copyWith({
    int? id,
    String? name,
    String? description,
    String? shortDescription,
    String? sku,
    String? price,
    String? regularPrice,
    String? salePrice,
    bool? onSale,
    bool? inStock,
    int? stockQuantity,
    List<String>? images,
    List<ProductCategory>? categories,
    String? vendorName,
    int? vendorId,
    double? rating,
    int? ratingCount,
    String? icon,
    String? color,
    bool? isSubscription,
    String? subscriptionPeriod,
    int? subscriptionPeriodInterval,
    String? subscriptionSignUpFee,
    int? subscriptionTrialLength,
    String? subscriptionTrialPeriod,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      shortDescription: shortDescription ?? this.shortDescription,
      sku: sku ?? this.sku,
      price: price ?? this.price,
      regularPrice: regularPrice ?? this.regularPrice,
      salePrice: salePrice ?? this.salePrice,
      onSale: onSale ?? this.onSale,
      inStock: inStock ?? this.inStock,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      images: images ?? this.images,
      categories: categories ?? this.categories,
      vendorName: vendorName ?? this.vendorName,
      vendorId: vendorId ?? this.vendorId,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isSubscription: isSubscription ?? this.isSubscription,
      subscriptionPeriod: subscriptionPeriod ?? this.subscriptionPeriod,
      subscriptionPeriodInterval: subscriptionPeriodInterval ?? this.subscriptionPeriodInterval,
      subscriptionSignUpFee: subscriptionSignUpFee ?? this.subscriptionSignUpFee,
      subscriptionTrialLength: subscriptionTrialLength ?? this.subscriptionTrialLength,
      subscriptionTrialPeriod: subscriptionTrialPeriod ?? this.subscriptionTrialPeriod,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        shortDescription,
        sku,
        price,
        regularPrice,
        salePrice,
        onSale,
        inStock,
        stockQuantity,
        images,
        categories,
        vendorName,
        vendorId,
        rating,
        ratingCount,
        isSubscription,
        subscriptionPeriod,
        subscriptionPeriodInterval,
        subscriptionSignUpFee,
        subscriptionTrialLength,
        subscriptionTrialPeriod,
      ];
}

class ProductCategory extends Equatable {
  final int id;
  final String name;
  final String? slug;

  const ProductCategory({
    required this.id,
    required this.name,
    this.slug,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
    };
  }

  @override
  List<Object?> get props => [id, name, slug];
}
