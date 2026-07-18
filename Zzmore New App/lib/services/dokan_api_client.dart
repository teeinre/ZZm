/// ═══════════════════════════════════════════════════════════════════════════
/// Dokan REST API Client for ZZmore Store
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Comprehensive API integration module for the Dokan Multivendor plugin
/// (v2.8+) REST API. All type definitions, request/response interfaces,
/// endpoint constants, and helper functions are derived from the official
/// Dokan API documentation at https://getdokan.github.io/dokan/
///
/// ## Authentication
/// Dokan supports two authentication mechanisms:
///   - **HTTP Basic Auth**: WordPress username + password (requires Basic-Auth plugin)
///   - **JWT Bearer Token**: `Authorization: Bearer <token>` (requires
///     JWT Authentication for WP REST API plugin)
///
/// ## Error Format
/// All Dokan API errors follow the WordPress REST API error structure:
/// ```json
/// {
///   "code": "rest_invalid_param",
///   "message": "Invalid parameter(s): name",
///   "data": { "status": 400, "params": { "name": "Name is required" } }
/// }
/// ```
///
/// ## Rate Limiting
/// Dokan inherits WordPress REST API rate-limiting. The API respects
/// standard HTTP cache headers. Pagination uses `page` and `per_page`
/// query parameters (default per_page=10, max=100).
///
/// ## Base URL
/// All Dokan endpoints are relative to: `{site_url}/wp-json/dokan/v1/`
/// – defined in [ApiConstants].
///
/// ## Usage
/// ```dart
/// import '../constants/api_constants.dart';
///
/// final api = DokanApiClient(
///   baseUrl: ApiConstants.dokanV1Base,
///   getHeaders: () async => { 'Authorization': 'Bearer $token' },
/// );
/// final products = await api.getProducts(status: 'publish');
/// ```
library dokan_api_client;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1: Exception Types
// ═══════════════════════════════════════════════════════════════════════════

/// Base exception for all Dokan API errors.
class DokanApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? data;

  const DokanApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.data,
  });

  factory DokanApiException.fromResponse(http.Response response) {
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }
    return DokanApiException(
      code: body?['code']?.toString() ?? 'http_error',
      message: body?['message']?.toString() ?? response.reasonPhrase ?? 'Unknown error',
      statusCode: response.statusCode,
      data: body?['data'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'DokanApiException($statusCode): [$code] $message';
}

/// 401 Unauthorized – invalid or expired credentials.
class DokanUnauthorizedException extends DokanApiException {
  const DokanUnauthorizedException({
    super.code = 'rest_unauthorized',
    super.message = 'Authentication required',
    super.statusCode = 401,
  });
}

/// 403 Forbidden – insufficient permissions.
class DokanForbiddenException extends DokanApiException {
  const DokanForbiddenException({
    super.code = 'rest_forbidden',
    super.message = 'You do not have permission to access this resource',
    super.statusCode = 403,
  });
}

/// 404 Not Found – resource does not exist.
class DokanNotFoundException extends DokanApiException {
  const DokanNotFoundException({
    super.code = 'rest_not_found',
    super.message = 'The requested resource was not found',
    super.statusCode = 404,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2: Typed Interfaces — All Dokan API Resources
// ═══════════════════════════════════════════════════════════════════════════

// ── 2.1 Products ──────────────────────────────────────────────────────────

/// Represents a product managed through the Dokan vendor API.
/// Mirrors the Dokan product properties as specified in:
/// https://getdokan.github.io/dokan/#product-properties
abstract class IDokanProduct {
  int get id;
  String get name;
  String get slug;
  String get permalink;
  String get postAuthor;
  DateTime? get dateCreated;
  String get type; // simple | grouped | external | variable
  String get status; // draft | pending | publish
  bool get featured;
  String get catalogVisibility;
  String get description;
  String get shortDescription;
  String get sku;
  String get price; // READ-ONLY – current price
  String get regularPrice;
  String? get salePrice;
  bool get onSale;
  bool get purchasable;
  int get totalSales;
  bool get virtual;
  bool get downloadable;
  bool get manageStock;
  int? get stockQuantity;
  String get stockStatus; // instock | outofstock | onbackorder
  String get taxStatus;
  String? get taxClass;
  double? get weight;
  DokanProductDimensions? get dimensions;
  List<DokanProductImage> get images;
  List<DokanProductCategory> get categories;
  List<DokanProductTag>? get tags;
  List<DokanProductAttribute>? get attributes;
  List<DokanProductMeta>? get metaData;
}

class DokanProduct implements IDokanProduct {
  @override final int id;
  @override final String name;
  @override final String slug;
  @override final String permalink;
  @override final String postAuthor;
  @override final DateTime? dateCreated;
  @override final String type;
  @override final String status;
  @override final bool featured;
  @override final String catalogVisibility;
  @override final String description;
  @override final String shortDescription;
  @override final String sku;
  @override final String price;
  @override final String regularPrice;
  @override final String? salePrice;
  @override final bool onSale;
  @override final bool purchasable;
  @override final int totalSales;
  @override final bool virtual;
  @override final bool downloadable;
  @override final bool manageStock;
  @override final int? stockQuantity;
  @override final String stockStatus;
  @override final String taxStatus;
  @override final String? taxClass;
  @override final double? weight;
  @override final DokanProductDimensions? dimensions;
  @override final List<DokanProductImage> images;
  @override final List<DokanProductCategory> categories;
  @override final List<DokanProductTag>? tags;
  @override final List<DokanProductAttribute>? attributes;
  @override final List<DokanProductMeta>? metaData;

  const DokanProduct({
    required this.id,
    required this.name,
    this.slug = '',
    this.permalink = '',
    this.postAuthor = '',
    this.dateCreated,
    this.type = 'simple',
    this.status = 'publish',
    this.featured = false,
    this.catalogVisibility = 'visible',
    this.description = '',
    this.shortDescription = '',
    this.sku = '',
    this.price = '0',
    this.regularPrice = '0',
    this.salePrice,
    this.onSale = false,
    this.purchasable = true,
    this.totalSales = 0,
    this.virtual = false,
    this.downloadable = false,
    this.manageStock = false,
    this.stockQuantity,
    this.stockStatus = 'instock',
    this.taxStatus = 'taxable',
    this.taxClass,
    this.weight,
    this.dimensions,
    this.images = const [],
    this.categories = const [],
    this.tags,
    this.attributes,
    this.metaData,
  });

  factory DokanProduct.fromJson(Map<String, dynamic> json) {
    return DokanProduct(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      permalink: json['permalink']?.toString() ?? '',
      postAuthor: json['post_author']?.toString() ?? '',
      dateCreated: json['date_created'] != null
          ? DateTime.tryParse(json['date_created'].toString())
          : null,
      type: json['type']?.toString() ?? 'simple',
      status: json['status']?.toString() ?? 'publish',
      featured: json['featured'] == true,
      catalogVisibility: json['catalog_visibility']?.toString() ?? 'visible',
      description: json['description']?.toString() ?? '',
      shortDescription: json['short_description']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      price: json['price']?.toString() ?? '0',
      regularPrice: json['regular_price']?.toString() ?? '0',
      salePrice: json['sale_price']?.toString(),
      onSale: json['on_sale'] == true,
      purchasable: json['purchasable'] != false,
      totalSales: (json['total_sales'] as num?)?.toInt() ?? 0,
      virtual: json['virtual'] == true,
      downloadable: json['downloadable'] == true,
      manageStock: json['manage_stock'] == true,
      stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
      stockStatus: json['stock_status']?.toString() ?? 'instock',
      taxStatus: json['tax_status']?.toString() ?? 'taxable',
      taxClass: json['tax_class']?.toString(),
      weight: double.tryParse(json['weight']?.toString() ?? ''),
      dimensions: json['dimensions'] != null
          ? DokanProductDimensions.fromJson(json['dimensions'])
          : null,
      images: (json['images'] as List<dynamic>?)
              ?.map((i) => DokanProductImage.fromJson(i))
              .toList() ??
          [],
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => DokanProductCategory.fromJson(c))
              .toList() ??
          [],
      tags: (json['tags'] as List<dynamic>?)
          ?.map((t) => DokanProductTag.fromJson(t))
          .toList(),
      attributes: (json['attributes'] as List<dynamic>?)
          ?.map((a) => DokanProductAttribute.fromJson(a))
          .toList(),
      metaData: (json['meta_data'] as List<dynamic>?)
          ?.map((m) => DokanProductMeta.fromJson(m))
          .toList(),
    );
  }

  /// Serialize to JSON for create/update requests.
  Map<String, dynamic> toJson() => {
        if (id != 0) 'id': id,
        'name': name,
        'type': type,
        'status': status,
        'featured': featured,
        'description': description,
        'short_description': shortDescription,
        'sku': sku,
        'regular_price': regularPrice,
        if (salePrice != null) 'sale_price': salePrice,
        'manage_stock': manageStock,
        if (stockQuantity != null) 'stock_quantity': stockQuantity,
        'stock_status': stockStatus,
        'tax_status': taxStatus,
        if (taxClass != null) 'tax_class': taxClass,
        if (weight != null) 'weight': weight,
        if (dimensions != null) 'dimensions': dimensions!.toJson(),
        'images': images.map((i) => i.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        if (tags != null) 'tags': tags!.map((t) => t.toJson()).toList(),
        if (attributes != null)
          'attributes': attributes!.map((a) => a.toJson()).toList(),
        if (metaData != null)
          'meta_data': metaData!.map((m) => m.toJson()).toList(),
      };
}

class DokanProductDimensions {
  final String length;
  final String width;
  final String height;

  const DokanProductDimensions({
    this.length = '',
    this.width = '',
    this.height = '',
  });

  factory DokanProductDimensions.fromJson(Map<String, dynamic> json) =>
      DokanProductDimensions(
        length: json['length']?.toString() ?? '',
        width: json['width']?.toString() ?? '',
        height: json['height']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'length': length,
        'width': width,
        'height': height,
      };
}

class DokanProductImage {
  final int id;
  final String src;
  final String name;
  final String? alt;
  final int position; // 0 = featured image

  const DokanProductImage({
    this.id = 0,
    required this.src,
    this.name = '',
    this.alt,
    this.position = 0,
  });

  factory DokanProductImage.fromJson(Map<String, dynamic> json) =>
      DokanProductImage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        src: json['src']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        alt: json['alt']?.toString(),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (id != 0) 'id': id,
        'src': src,
        'position': position,
        if (alt != null) 'alt': alt,
      };
}

class DokanProductCategory {
  final int id;
  final String name;
  final String slug;

  const DokanProductCategory({required this.id, this.name = '', this.slug = ''});

  factory DokanProductCategory.fromJson(Map<String, dynamic> json) =>
      DokanProductCategory(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id};
}

class DokanProductTag {
  final int id;
  final String name;
  final String slug;

  const DokanProductTag({required this.id, this.name = '', this.slug = ''});

  factory DokanProductTag.fromJson(Map<String, dynamic> json) => DokanProductTag(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id};
}

class DokanProductAttribute {
  final int? id;
  final String name;
  final int position;
  final bool visible;
  final bool variation;
  final List<String> options;

  const DokanProductAttribute({
    this.id,
    required this.name,
    this.position = 0,
    this.visible = true,
    this.variation = false,
    this.options = const [],
  });

  factory DokanProductAttribute.fromJson(Map<String, dynamic> json) =>
      DokanProductAttribute(
        id: (json['id'] as num?)?.toInt(),
        name: json['name']?.toString() ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
        visible: json['visible'] == true,
        variation: json['variation'] == true,
        options: (json['options'] as List<dynamic>?)
                ?.map((o) => o.toString())
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'position': position,
        'visible': visible,
        'variation': variation,
        'options': options,
      };
}

class DokanProductMeta {
  final int? id;
  final String key;
  final dynamic value;

  const DokanProductMeta({this.id, required this.key, this.value});

  factory DokanProductMeta.fromJson(Map<String, dynamic> json) =>
      DokanProductMeta(
        id: (json['id'] as num?)?.toInt(),
        key: json['key']?.toString() ?? '',
        value: json['value'],
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
      };
}

// ── 2.2 Orders ────────────────────────────────────────────────────────────

abstract class IDokanOrder {
  int get id;
  int get parentId;
  String get orderNumber;
  String get status; // pending | processing | on-hold | completed | cancelled | refunded | failed
  String get currency;
  String get total;
  DateTime? get dateCreated;
  Map<String, dynamic> get billing;
  Map<String, dynamic> get shipping;
  String get paymentMethod;
  String get paymentMethodTitle;
  List<Map<String, dynamic>> get lineItems;
}

class DokanOrder implements IDokanOrder {
  @override final int id;
  @override final int parentId;
  @override final String orderNumber;
  @override final String status;
  @override final String currency;
  @override final String total;
  @override final DateTime? dateCreated;
  @override final Map<String, dynamic> billing;
  @override final Map<String, dynamic> shipping;
  @override final String paymentMethod;
  @override final String paymentMethodTitle;
  @override final List<Map<String, dynamic>> lineItems;

  const DokanOrder({
    required this.id,
    this.parentId = 0,
    this.orderNumber = '',
    this.status = 'pending',
    this.currency = 'GBP',
    this.total = '0',
    this.dateCreated,
    this.billing = const {},
    this.shipping = const {},
    this.paymentMethod = '',
    this.paymentMethodTitle = '',
    this.lineItems = const [],
  });

  factory DokanOrder.fromJson(Map<String, dynamic> json) => DokanOrder(
        id: json['id'] as int,
        parentId: (json['parent_id'] as num?)?.toInt() ?? 0,
        orderNumber: json['number']?.toString() ?? '#${json['id']}',
        status: json['status']?.toString() ?? 'pending',
        currency: json['currency']?.toString() ?? 'GBP',
        total: json['total']?.toString() ?? '0',
        dateCreated: json['date_created'] != null
            ? DateTime.tryParse(json['date_created'].toString())
            : null,
        billing: json['billing'] is Map
            ? Map<String, dynamic>.from(json['billing'])
            : {},
        shipping: json['shipping'] is Map
            ? Map<String, dynamic>.from(json['shipping'])
            : {},
        paymentMethod: json['payment_method']?.toString() ?? '',
        paymentMethodTitle: json['payment_method_title']?.toString() ?? '',
        lineItems: (json['line_items'] as List<dynamic>?)
                ?.map((li) => Map<String, dynamic>.from(li))
                .toList() ??
            [],
      );
}

/// Summary statistics for a vendor's orders.
class DokanOrdersSummary {
  final int totalOrders;
  final int pendingOrders;
  final int processingOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int refundedOrders;
  final int failedOrders;

  const DokanOrdersSummary({
    this.totalOrders = 0,
    this.pendingOrders = 0,
    this.processingOrders = 0,
    this.completedOrders = 0,
    this.cancelledOrders = 0,
    this.refundedOrders = 0,
    this.failedOrders = 0,
  });

  factory DokanOrdersSummary.fromJson(Map<String, dynamic> json) =>
      DokanOrdersSummary(
        totalOrders: (json['total'] as num?)?.toInt() ?? 0,
        pendingOrders: (json['pending'] as num?)?.toInt() ?? 0,
        processingOrders: (json['processing'] as num?)?.toInt() ?? 0,
        completedOrders: (json['completed'] as num?)?.toInt() ?? 0,
        cancelledOrders: (json['cancelled'] as num?)?.toInt() ?? 0,
        refundedOrders: (json['refunded'] as num?)?.toInt() ?? 0,
        failedOrders: (json['failed'] as num?)?.toInt() ?? 0,
      );
}

// ── 2.3 Stores (Vendors) ──────────────────────────────────────────────────

/// Vendor store information as returned by the Dokan Stores API.
abstract class IDokanStore {
  int get id;
  String get storeName;
  String get shopName;
  String get storeUrl;
  String get address;
  String get phone;
  String get email;
  String? get banner;
  String? get gravatar;
  bool get enabled;
  bool get trusted;
  double get rating;
  Map<String, dynamic> get payment; // bank details, payment methods
}

class DokanStore implements IDokanStore {
  @override final int id;
  @override final String storeName;
  @override final String shopName;
  @override final String storeUrl;
  @override final String address;
  @override final String phone;
  @override final String email;
  @override final String? banner;
  @override final String? gravatar;
  @override final bool enabled;
  @override final bool trusted;
  @override final double rating;
  @override final Map<String, dynamic> payment;

  const DokanStore({
    required this.id,
    this.storeName = '',
    this.shopName = '',
    this.storeUrl = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.banner,
    this.gravatar,
    this.enabled = true,
    this.trusted = false,
    this.rating = 0,
    this.payment = const {},
  });

  factory DokanStore.fromJson(Map<String, dynamic> json) => DokanStore(
        id: (json['id'] as num).toInt(),
        storeName: json['store_name']?.toString() ?? '',
        shopName: json['shop_name']?.toString() ?? json['store_name']?.toString() ?? '',
        storeUrl: json['store_url']?.toString() ?? json['url']?.toString() ?? '',
        address: json['address'] is Map
            ? _formatAddress(json['address'] as Map<String, dynamic>)
            : json['address']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        banner: json['banner']?.toString(),
        gravatar: json['gravatar']?.toString(),
        enabled: json['enabled'] != false,
        trusted: json['trusted'] == true,
        rating: double.tryParse(json['rating']?.toString() ?? '0') ?? 0,
        payment: json['payment'] is Map
            ? Map<String, dynamic>.from(json['payment'])
            : <String, dynamic>{},
      );

  static String _formatAddress(Map<String, dynamic> addr) {
    final parts = <String>[];
    if (addr['street_1']?.toString().isNotEmpty == true) {
      parts.add(addr['street_1']!);
    }
    if (addr['street_2']?.toString().isNotEmpty == true) {
      parts.add(addr['street_2']!);
    }
    final city = addr['city']?.toString() ?? '';
    final state = addr['state']?.toString() ?? '';
    final zip = addr['zip']?.toString() ?? '';
    final locality = [city, state, zip].where((s) => s.isNotEmpty).join(', ');
    if (locality.isNotEmpty) parts.add(locality);
    if (addr['country']?.toString().isNotEmpty == true) {
      parts.add(addr['country']!);
    }
    return parts.join(', ');
  }
}

// ── 2.4 Withdrawals ───────────────────────────────────────────────────────

class DokanWithdrawal {
  final int id;
  final int userId;
  final double amount;
  final String method; // bank | paypal | stripe | skrill
  final String status; // pending | approved | cancelled
  final String? note;
  final String? ip;
  final DateTime? dateCreated;

  const DokanWithdrawal({
    required this.id,
    this.userId = 0,
    this.amount = 0,
    this.method = '',
    this.status = 'pending',
    this.note,
    this.ip,
    this.dateCreated,
  });

  factory DokanWithdrawal.fromJson(Map<String, dynamic> json) =>
      DokanWithdrawal(
        id: (json['id'] as num).toInt(),
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
        method: json['method']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        note: json['note']?.toString(),
        ip: json['ip']?.toString(),
        dateCreated: json['date_created'] != null
            ? DateTime.tryParse(json['date_created'].toString())
            : null,
      );
}

// ── 2.5 Reviews ───────────────────────────────────────────────────────────

/// Product review from a Dokan vendor's store.
class DokanReview {
  final int id;
  final int productId;
  final int reviewerId;
  final String reviewerName;
  final String reviewerEmail;
  final String review;
  final int rating; // 1-5
  final bool verified;
  final String status; // hold | approved | spam | trash
  final DateTime? dateCreated;

  const DokanReview({
    required this.id,
    this.productId = 0,
    this.reviewerId = 0,
    this.reviewerName = '',
    this.reviewerEmail = '',
    this.review = '',
    this.rating = 0,
    this.verified = false,
    this.status = 'hold',
    this.dateCreated,
  });

  factory DokanReview.fromJson(Map<String, dynamic> json) => DokanReview(
        id: (json['id'] as num).toInt(),
        productId: (json['product_id'] as num?)?.toInt() ?? 0,
        reviewerId: (json['reviewer_id'] as num?)?.toInt() ?? 0,
        reviewerName: json['reviewer_name']?.toString() ?? '',
        reviewerEmail: json['reviewer_email']?.toString() ?? '',
        review: json['review']?.toString() ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        verified: json['verified'] == true,
        status: json['status']?.toString() ?? 'hold',
        dateCreated: json['date_created'] != null
            ? DateTime.tryParse(json['date_created'].toString())
            : null,
      );
}

// ── 2.6 Coupons ────────────────────────────────────────────────────────────

class DokanCoupon {
  final int id;
  final String code;
  final String discountType; // percent | fixed_cart | fixed_product
  final double amount;
  final DateTime? dateExpires;
  final String? description;
  final int? usageLimit;
  final int usageCount;
  final bool individualUse;
  final List<int>? productIds;
  final List<int>? excludedProductIds;
  final double? minimumAmount;

  const DokanCoupon({
    required this.id,
    this.code = '',
    this.discountType = 'fixed_cart',
    this.amount = 0,
    this.dateExpires,
    this.description,
    this.usageLimit,
    this.usageCount = 0,
    this.individualUse = false,
    this.productIds,
    this.excludedProductIds,
    this.minimumAmount,
  });

  factory DokanCoupon.fromJson(Map<String, dynamic> json) => DokanCoupon(
        id: (json['id'] as num).toInt(),
        code: json['code']?.toString() ?? '',
        discountType: json['discount_type']?.toString() ?? 'fixed_cart',
        amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
        dateExpires: json['date_expires'] != null
            ? DateTime.tryParse(json['date_expires'].toString())
            : null,
        description: json['description']?.toString(),
        usageLimit: (json['usage_limit'] as num?)?.toInt(),
        usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
        individualUse: json['individual_use'] == true,
        productIds: (json['product_ids'] as List<dynamic>?)
            ?.map((id) => (id as num).toInt())
            .toList(),
        excludedProductIds: (json['excluded_product_ids'] as List<dynamic>?)
            ?.map((id) => (id as num).toInt())
            .toList(),
        minimumAmount:
            double.tryParse(json['minimum_amount']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'discount_type': discountType,
        'amount': amount.toString(),
        if (description != null) 'description': description,
        if (dateExpires != null) 'date_expires': dateExpires!.toIso8601String(),
        if (usageLimit != null) 'usage_limit': usageLimit,
        'individual_use': individualUse,
        if (productIds != null) 'product_ids': productIds,
        if (excludedProductIds != null) 'excluded_product_ids': excludedProductIds,
        if (minimumAmount != null) 'minimum_amount': minimumAmount,
      };
}

// ── 2.7 Reports ───────────────────────────────────────────────────────────

class DokanVendorReports {
  final String totalSales;
  final String totalEarnings;
  final int totalOrders;
  final int totalProducts;
  final int totalPageviews;
  final int pendingOrders;
  final int processingOrders;
  final int completedOrders;

  const DokanVendorReports({
    this.totalSales = '0',
    this.totalEarnings = '0',
    this.totalOrders = 0,
    this.totalProducts = 0,
    this.totalPageviews = 0,
    this.pendingOrders = 0,
    this.processingOrders = 0,
    this.completedOrders = 0,
  });

  factory DokanVendorReports.fromJson(Map<String, dynamic> json) =>
      DokanVendorReports(
        totalSales: json['total_sales']?.toString() ?? '0',
        totalEarnings: json['total_earnings']?.toString() ?? '0',
        totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
        totalProducts: (json['total_products'] as num?)?.toInt() ?? 0,
        totalPageviews: (json['total_pageviews'] as num?)?.toInt() ?? 0,
        pendingOrders: (json['pending_orders'] as num?)?.toInt() ?? 0,
        processingOrders: (json['processing_orders'] as num?)?.toInt() ?? 0,
        completedOrders: (json['completed_orders'] as num?)?.toInt() ?? 0,
      );
}

/// Per-day or per-month sales data point for charts.
class DokanSalesDataPoint {
  final DateTime date;
  final double sales;
  final int orders;

  const DokanSalesDataPoint({
    required this.date,
    this.sales = 0,
    this.orders = 0,
  });

  factory DokanSalesDataPoint.fromJson(Map<String, dynamic> json) =>
      DokanSalesDataPoint(
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        sales: double.tryParse(json['sales']?.toString() ?? '0') ?? 0,
        orders: (json['orders'] as num?)?.toInt() ?? 0,
      );
}

// ── 2.8 Balance ────────────────────────────────────────────────────────────

class DokanBalance {
  final double currentBalance;
  final double totalEarnings;
  final double totalWithdrawals;
  final String currency;

  const DokanBalance({
    this.currentBalance = 0,
    this.totalEarnings = 0,
    this.totalWithdrawals = 0,
    this.currency = 'GBP',
  });

  factory DokanBalance.fromJson(Map<String, dynamic> json) => DokanBalance(
        currentBalance:
            double.tryParse(json['current_balance']?.toString() ?? '0') ?? 0,
        totalEarnings:
            double.tryParse(json['total_earnings']?.toString() ?? '0') ?? 0,
        totalWithdrawals:
            double.tryParse(json['total_withdrawals']?.toString() ?? '0') ?? 0,
        currency: json['currency']?.toString() ?? 'GBP',
      );
}

// ── 2.9 Announcements ─────────────────────────────────────────────────────

class DokanAnnouncement {
  final int id;
  final String title;
  final String content;
  final String status;
  final int? senderId;
  final String? senderName;
  final DateTime? dateCreated;

  const DokanAnnouncement({
    required this.id,
    this.title = '',
    this.content = '',
    this.status = 'publish',
    this.senderId,
    this.senderName,
    this.dateCreated,
  });

  factory DokanAnnouncement.fromJson(Map<String, dynamic> json) =>
      DokanAnnouncement(
        id: (json['id'] as num).toInt(),
        title: json['title']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        status: json['status']?.toString() ?? 'publish',
        senderId: (json['sender_id'] as num?)?.toInt(),
        senderName: json['sender_name']?.toString(),
        dateCreated: json['date_created'] != null
            ? DateTime.tryParse(json['date_created'].toString())
            : null,
      );
}

// ── 2.10 Settings ─────────────────────────────────────────────────────────

/// Vendor store settings from Dokan.
class DokanVendorSettings {
  final String storeName;
  final String storeUrl;
  final String phone;
  final bool showEmail;
  final String address;
  final String location;
  final bool enabled;
  final bool trusted;
  final Map<String, dynamic> social;
  final Map<String, dynamic> payment;

  const DokanVendorSettings({
    this.storeName = '',
    this.storeUrl = '',
    this.phone = '',
    this.showEmail = false,
    this.address = '',
    this.location = '',
    this.enabled = true,
    this.trusted = false,
    this.social = const {},
    this.payment = const {},
  });

  factory DokanVendorSettings.fromJson(Map<String, dynamic> json) =>
      DokanVendorSettings(
        storeName: json['store_name']?.toString() ?? '',
        storeUrl: json['store_url']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        showEmail: json['show_email'] == true,
        address: json['address']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        enabled: json['enabled'] != false,
        trusted: json['trusted'] == true,
        social: json['social'] is Map
            ? Map<String, dynamic>.from(json['social'])
            : {},
        payment: json['payment'] is Map
            ? Map<String, dynamic>.from(json['payment'])
            : {},
      );

  Map<String, dynamic> toJson() => {
        'store_name': storeName,
        'store_url': storeUrl,
        'phone': phone,
        'show_email': showEmail,
        'address': address,
        'location': location,
        'social': social,
        'payment': payment,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3: API Client Class
// ═══════════════════════════════════════════════════════════════════════════

typedef HeaderProvider = Future<Map<String, String>> Function();
typedef AuthTokenProvider = Future<String?> Function();

/// Core Dokan v1 REST API client.
/// Provides typed, well-documented wrappers for all Dokan API endpoints.
class DokanApiClient {
  final String baseUrl;
  final http.Client _client;

  /// Optional callbacks for auth header injection.
  final HeaderProvider? getHeaders;
  final AuthTokenProvider? getAuthToken;

  DokanApiClient({
    this.baseUrl = ApiConstants.dokanV1Base,
    http.Client? httpClient,
    this.getHeaders,
    this.getAuthToken,
  }) : _client = httpClient ?? http.Client();

  /// Dispose of the underlying HTTP client.
  void dispose() => _client.close();

  // ── HTTP helpers ──────────────────────────────────────────────────────

  Map<String, String> _defaultHeaders({bool useBasicAuth = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (useBasicAuth) {
      final token = base64Encode(
        utf8.encode('${ApiConstants.consumerKey}:${ApiConstants.consumerSecret}'),
      );
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  Future<Map<String, String>> _buildHeaders({bool useBasicAuth = false}) async {
    if (getHeaders != null) return getHeaders!();
    final headers = _defaultHeaders(useBasicAuth: useBasicAuth);
    if (getAuthToken != null) {
      final token = await getAuthToken!();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// Parse response and throw typed exception on error.
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return <String, dynamic>{'data': decoded};
      }
      return Map<String, dynamic>.from(decoded);
    }

    switch (response.statusCode) {
      case 401:
        throw DokanUnauthorizedException();
      case 403:
        throw DokanForbiddenException();
      case 404:
        throw DokanNotFoundException();
      default:
        throw DokanApiException.fromResponse(response);
    }
  }

  /// Parse response as a list of maps.
  List<Map<String, dynamic>> _handleListResponse(http.Response response) {
    final handled = _handleResponse(response);
    final data = handled['data'];
    if (data is List) {
      return data.map((d) => Map<String, dynamic>.from(d)).toList();
    }
    return [];
  }

  Future<http.Response> _get(String endpoint, {bool useBasicAuth = false}) async {
    final url = Uri.parse('$baseUrl/$endpoint');
    final headers = await _buildHeaders(useBasicAuth: useBasicAuth);
    return _client.get(url, headers: headers);
  }

  Future<http.Response> _post(String endpoint, Map<String, dynamic> body,
      {bool useBasicAuth = false}) async {
    final url = Uri.parse('$baseUrl/$endpoint');
    final headers = await _buildHeaders(useBasicAuth: useBasicAuth);
    return _client.post(url, headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> _put(String endpoint, Map<String, dynamic> body,
      {bool useBasicAuth = false}) async {
    final url = Uri.parse('$baseUrl/$endpoint');
    final headers = await _buildHeaders(useBasicAuth: useBasicAuth);
    return _client.put(url, headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> _delete(String endpoint,
      {bool useBasicAuth = false}) async {
    final url = Uri.parse('$baseUrl/$endpoint');
    final headers = await _buildHeaders(useBasicAuth: useBasicAuth);
    return _client.delete(url, headers: headers);
  }

  // ── 3.1 Products API ──────────────────────────────────────────────────
  // Documentation: https://getdokan.github.io/dokan/#products

  /// List all vendor products. Requires vendor authentication.
  /// Query params: page, per_page, status, search, type
  Future<List<DokanProduct>> getProducts({
    int page = 1,
    int perPage = 10,
    String? status,
    String? search,
    String? type,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    if (status != null) params['status'] = status;
    if (search != null) params['search'] = search;
    if (type != null) params['type'] = type;
    final query = Uri(queryParameters: params).query;
    final response = await _get('products?$query');
    final list = _handleListResponse(response);
    return list.map((p) => DokanProduct.fromJson(p)).toList();
  }

  /// Get a single vendor product by ID.
  Future<DokanProduct> getProduct(int productId) async {
    final response = await _get('products/$productId');
    return DokanProduct.fromJson(_handleResponse(response));
  }

  /// Create a new product for the authenticated vendor.
  /// Required fields: name, type, categories.
  Future<DokanProduct> createProduct(Map<String, dynamic> data) async {
    final response = await _post('products', data);
    return DokanProduct.fromJson(_handleResponse(response));
  }

  /// Update an existing vendor product.
  Future<DokanProduct> updateProduct(int productId, Map<String, dynamic> data) async {
    final response = await _put('products/$productId', data);
    return DokanProduct.fromJson(_handleResponse(response));
  }

  /// Delete a vendor product.
  Future<bool> deleteProduct(int productId) async {
    final response = await _delete('products/$productId');
    return response.statusCode == 200;
  }

  /// Batch create/update/delete products.
  Future<Map<String, dynamic>> batchProducts({
    List<Map<String, dynamic>>? create,
    List<Map<String, dynamic>>? update,
    List<int>? delete,
  }) async {
    final body = <String, dynamic>{};
    if (create != null) body['create'] = create;
    if (update != null) body['update'] = update;
    if (delete != null) body['delete'] = delete;
    final response = await _post('products/batch', body);
    return _handleResponse(response);
  }

  // ── 3.2 Orders API ────────────────────────────────────────────────────
  // Documentation: https://getdokan.github.io/dokan/#orders

  /// List vendor orders with pagination and optional status filter.
  Future<List<DokanOrder>> getOrders({
    int page = 1,
    int perPage = 20,
    String? status,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    if (status != null) params['status'] = status;
    final query = Uri(queryParameters: params).query;
    final response = await _get('orders?$query');
    final list = _handleListResponse(response);
    return list.map((o) => DokanOrder.fromJson(o)).toList();
  }

  /// Get a single vendor order by ID.
  Future<DokanOrder> getOrder(int orderId) async {
    final response = await _get('orders/$orderId');
    return DokanOrder.fromJson(_handleResponse(response));
  }

  /// Update order status (e.g., mark as completed, processing).
  /// Allowed statuses: pending | processing | on-hold | completed | cancelled | refunded | failed
  Future<DokanOrder> updateOrder(int orderId, {required String status}) async {
    final response = await _put('orders/$orderId', {'status': status});
    return DokanOrder.fromJson(_handleResponse(response));
  }

  /// Get orders summary statistics for the vendor.
  Future<DokanOrdersSummary> getOrdersSummary() async {
    final response = await _get('orders/summary');
    return DokanOrdersSummary.fromJson(_handleResponse(response));
  }

  // ── 3.3 Stores API ────────────────────────────────────────────────────
  // Documentation: https://getdokan.github.io/dokan/#stores

  /// Get all stores (public, no auth needed).
  Future<List<DokanStore>> getStores({int page = 1, int perPage = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    final query = Uri(queryParameters: params).query;
    final response = await _get('stores?$query');
    final list = _handleListResponse(response);
    return list.map((s) => DokanStore.fromJson(s)).toList();
  }

  /// Get a single store's full info by store ID.
  Future<DokanStore?> getStore(int storeId) async {
    try {
      final response = await _get('stores/$storeId');
      return DokanStore.fromJson(_handleResponse(response));
    } on DokanNotFoundException {
      return null;
    }
  }

  // ── 3.4 Withdrawals API ───────────────────────────────────────────────
  // Documentation: https://getdokan.github.io/dokan/#withdraw

  /// List vendor withdrawal requests.
  Future<List<DokanWithdrawal>> getWithdrawals({int page = 1, int perPage = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    final query = Uri(queryParameters: params).query;
    final response = await _get('withdraw?$query');
    final list = _handleListResponse(response);
    return list.map((w) => DokanWithdrawal.fromJson(w)).toList();
  }

  /// Request a new withdrawal.
  Future<DokanWithdrawal> requestWithdrawal({
    required double amount,
    required String method, // bank | paypal | stripe | skrill
  }) async {
    final response = await _post('withdraw', {
      'amount': amount.toString(),
      'method': method,
    });
    return DokanWithdrawal.fromJson(_handleResponse(response));
  }

  /// Get current vendor balance.
  Future<DokanBalance> getBalance() async {
    final response = await _get('balance');
    return DokanBalance.fromJson(_handleResponse(response));
  }

  // ── 3.5 Reviews API ───────────────────────────────────────────────────

  /// List vendor product reviews.
  Future<List<DokanReview>> getReviews({int page = 1, int perPage = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    final query = Uri(queryParameters: params).query;
    final response = await _get('reviews?$query');
    final list = _handleListResponse(response);
    return list.map((r) => DokanReview.fromJson(r)).toList();
  }

  // ── 3.6 Coupons API ───────────────────────────────────────────────────

  /// List vendor coupons.
  Future<List<DokanCoupon>> getCoupons({int page = 1, int perPage = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    final query = Uri(queryParameters: params).query;
    final response = await _get('coupons?$query');
    final list = _handleListResponse(response);
    return list.map((c) => DokanCoupon.fromJson(c)).toList();
  }

  /// Create a vendor coupon.
  Future<DokanCoupon> createCoupon(DokanCoupon coupon) async {
    final response = await _post('coupons', coupon.toJson());
    return DokanCoupon.fromJson(_handleResponse(response));
  }

  /// Update a vendor coupon.
  Future<DokanCoupon> updateCoupon(int couponId, DokanCoupon coupon) async {
    final response = await _put('coupons/$couponId', coupon.toJson());
    return DokanCoupon.fromJson(_handleResponse(response));
  }

  /// Delete a vendor coupon.
  Future<bool> deleteCoupon(int couponId) async {
    final response = await _delete('coupons/$couponId');
    return response.statusCode == 200;
  }

  // ── 3.7 Reports API ───────────────────────────────────────────────────

  /// Get vendor reports/overview.
  Future<DokanVendorReports> getReports() async {
    final response = await _get('reports');
    return DokanVendorReports.fromJson(_handleResponse(response));
  }

  /// Get sales overview summary.
  Future<Map<String, dynamic>> getSalesOverview() async {
    final response = await _get('reports/summary');
    return _handleResponse(response);
  }

  // ── 3.8 Settings API ──────────────────────────────────────────────────

  /// Get vendor store settings.
  Future<DokanVendorSettings> getSettings() async {
    final response = await _get('settings');
    return DokanVendorSettings.fromJson(_handleResponse(response));
  }

  /// Update vendor store settings.
  Future<DokanVendorSettings> updateSettings(DokanVendorSettings settings) async {
    final response = await _put('settings', settings.toJson());
    return DokanVendorSettings.fromJson(_handleResponse(response));
  }

  // ── 3.9 Announcements API ─────────────────────────────────────────────

  /// List vendor announcements/notices.
  Future<List<DokanAnnouncement>> getAnnouncements({int page = 1, int perPage = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    final query = Uri(queryParameters: params).query;
    final response = await _get('announcement?$query');
    final list = _handleListResponse(response);
    return list.map((a) => DokanAnnouncement.fromJson(a)).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4: Utility / Convenience Helper Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Safely extract an integer from a JSON value that may be int, double, or String.
int? safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString());
}

/// Safely extract a double from a JSON value that may be int, double, or String.
double safeDouble(dynamic value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

/// Safely extract a DateTime from a JSON date string.
DateTime? safeDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Build a URL with query parameters from a Map.
String buildUrlWithParams(String baseUrl, Map<String, String?> params) {
  final filtered = <String, String>{};
  params.forEach((key, value) {
    if (value != null) filtered[key] = value;
  });
  if (filtered.isEmpty) return baseUrl;
  final query = Uri(queryParameters: filtered).query;
  return '$baseUrl?$query';
}

/// Parse an error response body into a human-readable message.
String parseErrorMessage(http.Response response) {
  try {
    final body = jsonDecode(response.body);
    if (body is Map) {
      final message = body['message']?.toString() ?? '';
      final code = body['code']?.toString() ?? '';
      return code.isNotEmpty ? '[$code] $message' : message;
    }
  } catch (_) {}
  return 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
}

/// Check if a Dokan API response indicates success.
bool isSuccess(http.Response response) =>
    response.statusCode >= 200 && response.statusCode < 300;

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 5: Typed Request DTOs (Data Transfer Objects)
// ═══════════════════════════════════════════════════════════════════════════

/// Request payload for creating/updating a product via Dokan API.
class CreateProductRequest {
  final String name;
  final String type; // simple | variable | grouped | external
  final String regularPrice;
  final String? salePrice;
  final String? description;
  final String? shortDescription;
  final String? sku;
  final List<int> categoryIds;
  final List<DokanProductImage>? images;
  final String status; // draft | pending | publish
  final bool manageStock;
  final int? stockQuantity;
  final String stockStatus;
  final List<DokanProductAttribute>? attributes;

  const CreateProductRequest({
    required this.name,
    this.type = 'simple',
    required this.regularPrice,
    this.salePrice,
    this.description,
    this.shortDescription,
    this.sku,
    this.categoryIds = const [],
    this.images,
    this.status = 'publish',
    this.manageStock = false,
    this.stockQuantity,
    this.stockStatus = 'instock',
    this.attributes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'regular_price': regularPrice,
        if (salePrice != null) 'sale_price': salePrice,
        if (description != null) 'description': description,
        if (shortDescription != null) 'short_description': shortDescription,
        if (sku != null) 'sku': sku,
        'categories': categoryIds.map((id) => {'id': id}).toList(),
        if (images != null) 'images': images!.map((i) => i.toJson()).toList(),
        'status': status,
        'manage_stock': manageStock,
        if (stockQuantity != null) 'stock_quantity': stockQuantity,
        'stock_status': stockStatus,
        if (attributes != null)
          'attributes': attributes!.map((a) => a.toJson()).toList(),
      };
}

/// Request payload for creating a withdrawal.
class CreateWithdrawalRequest {
  final double amount;
  final String method; // bank | paypal | stripe | skrill

  const CreateWithdrawalRequest({required this.amount, required this.method});

  Map<String, dynamic> toJson() => {
        'amount': amount.toString(),
        'method': method,
      };
}

/// Request payload for updating an order status.
class UpdateOrderStatusRequest {
  final String status;

  const UpdateOrderStatusRequest({required this.status});

  Map<String, dynamic> toJson() => {'status': status};
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 6: Paginated Response Wrapper
// ═══════════════════════════════════════════════════════════════════════════

/// Generic wrapper for paginated API responses.
/// Dokan API uses WordPress-standard `X-WP-Total` and `X-WP-TotalPages` headers.
class PaginatedResponse<T> {
  final List<T> data;
  final int totalItems;
  final int totalPages;
  final int currentPage;

  const PaginatedResponse({
    required this.data,
    required this.totalItems,
    required this.totalPages,
    required this.currentPage,
  });

  bool get hasMore => currentPage < totalPages;
  bool get isEmpty => data.isEmpty;

  @override
  String toString() =>
      'PaginatedResponse(page=$currentPage/$totalPages, items=${data.length}/$totalItems)';
}

/// Extract pagination metadata from an HTTP response.
PaginatedResponse<T> parsePaginatedResponse<T>(
    http.Response response, T Function(Map<String, dynamic>) fromJson) {
  final totalItems =
      int.tryParse(response.headers['x-wp-total'] ?? '0') ?? 0;
  final totalPages =
      int.tryParse(response.headers['x-wp-totalpages'] ?? '1') ?? 1;

  // Attempt to extract page from Link header or fallback
  int currentPage = 1;
  final linkHeader = response.headers['link'];
  if (linkHeader != null) {
    final match = RegExp(r'[?&]page=(\d+)').firstMatch(linkHeader);
    if (match != null) {
      currentPage = int.tryParse(match.group(1)!) ?? 1;
    }
  }

  final decoded = jsonDecode(response.body);
  final List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map && decoded['data'] is List) {
    items = decoded['data'];
  } else {
    items = [];
  }

  return PaginatedResponse<T>(
    data: items.map((i) => fromJson(Map<String, dynamic>.from(i))).toList(),
    totalItems: totalItems,
    totalPages: totalPages,
    currentPage: currentPage,
  );
}
