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
  final bool manageStock;
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

  // WooCommerce Bookings plugin fields
  final int? bookingDuration; // raw duration value (e.g. minutes)
  final String? bookingDurationUnit; // minute, hour, day, month
  final String? bookingCost;
  final String? bookingBlockCost;
  final String? bookingDisplayCost;
  final bool hasResources;
  final String? resourcesAssignment; // customer, automatic
  final String? bookingLocation;
  final String? bookingLocationType;
  final bool bookingHasPersons;
  final bool bookingHasResources;
  final int? bookingMinPersons;
  final int? bookingMaxPersons;

  // Dokan form booking window/meta (from bookingproductcreation.php form):
  final int? bookingMinDateVal;        // _wc_booking_min_date (number, e.g. 0)
  final String? bookingMinDateUnit;    // _wc_booking_min_date_unit
  final int? bookingMaxDateVal;        // _wc_booking_max_date (number, default 12)
  final String? bookingMaxDateUnit;    // _wc_booking_max_date_unit
  final String? bookingDefaultDateAvailability; // _wc_booking_default_date_availability available|nonavailable
  final String? bookingFirstBlockTime; // _wc_booking_first_block_time HH:MM
  final List<int>? bookingRestrictedDays; // _wc_booking_restricted_days 0=Sun..6=Sat
  final bool bookingHasRestrictedDays; // _wc_booking_has_restricted_days flag
  final bool bookingRequiresConfirmation; // _wc_booking_requires_confirmation
  final bool bookingUserCanCancel;    // _wc_booking_user_can_cancel
  final int? bookingQtyMaxBookingsPerBlock; // _wc_booking_qty
  final bool metaIsBookable;          // _bookable=yes meta flag (Woo sometimes doesn't set type='booking')

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
    this.manageStock = false,
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
    this.bookingDuration,
    this.bookingDurationUnit,
    this.bookingCost,
    this.bookingBlockCost,
    this.bookingDisplayCost,
    this.hasResources = false,
    this.resourcesAssignment,
    this.bookingLocation,
    this.bookingLocationType,
    this.bookingHasPersons = false,
    this.bookingHasResources = false,
    this.bookingMinPersons,
    this.bookingMaxPersons,
    this.bookingMinDateVal,
    this.bookingMinDateUnit,
    this.bookingMaxDateVal,
    this.bookingMaxDateUnit,
    this.bookingDefaultDateAvailability,
    this.bookingFirstBlockTime,
    this.bookingRestrictedDays,
    this.bookingHasRestrictedDays = false,
    this.bookingRequiresConfirmation = false,
    this.bookingUserCanCancel = false,
    this.bookingQtyMaxBookingsPerBlock,
    this.metaIsBookable = false,
  });

  bool get isVariable => type == 'variable';
  bool get isBookable =>
      type == 'booking' ||
      metaIsBookable ||
      bookingDuration != null ||
      bookingFirstBlockTime != null;
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

  static int _parseStockQuantity(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
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

    // WooCommerce Bookings fields (exposed top-level by the plugin's REST API,
    // with meta_data fallbacks for sites that only expose raw meta).
    final bookingDurationRaw = json['booking_duration'] ??
        meta['_wc_booking_duration'] ??
        meta['_wc_booking_duration_type'];
    final bookingDuration = bookingDurationRaw is int
        ? bookingDurationRaw
        : int.tryParse(bookingDurationRaw?.toString() ?? '');
    final bookingDurationUnit = (json['booking_duration_unit'] ??
            meta['_wc_booking_duration_unit'])
        ?.toString();
    final bookingCost =
        (json['booking_cost'] ?? meta['_wc_booking_cost'])?.toString();
    final bookingBlockCost =
        (json['booking_block_cost'] ?? meta['_wc_booking_block_cost'])?.toString();
    final bookingDisplayCost =
        (json['display_cost'] ?? meta['_wc_display_cost'])?.toString();
    final bookingLocation =
        (json['booking_location'] ?? meta['_wc_booking_location'])?.toString();
    final bookingLocationType =
        (json['booking_location_type'] ?? meta['_wc_booking_location_type'])
            ?.toString();
    final resourcesAssignment =
        (json['resources_assignment'] ?? meta['_wc_booking_resources_assignment'])
            ?.toString();
    final bookingResources = json['booking_resources'];
    final hasResources = (json['has_resources'] as bool? ??
            (meta['_wc_booking_has_resources'] is bool
                ? meta['_wc_booking_has_resources'] as bool
                : null) ??
            '${meta['_wc_booking_has_resources']}'.toLowerCase() == 'yes' ||
            (bookingResources is List && bookingResources.isNotEmpty));
    final bookingHasResourcesBool = hasResources;
    final bookingHasPersons = (json['booking_has_persons'] as bool? ??
        '${meta['_wc_booking_has_persons']}'.toLowerCase() == 'yes');

    // Dokan form booking window meta (from bookingproductcreation.php form fields)
    final bookingMinDateVal = json['booking_min_date_val'] is int
        ? json['booking_min_date_val'] as int
        : int.tryParse('${meta['_wc_booking_min_date'] ?? ''}');
    final bookingMinDateUnit =
        (json['booking_min_date_unit'] ?? meta['_wc_booking_min_date_unit'])
            ?.toString();
    final bookingMaxDateVal = json['booking_max_date_val'] is int
        ? json['booking_max_date_val'] as int
        : int.tryParse('${meta['_wc_booking_max_date'] ?? ''}');
    final bookingMaxDateUnit =
        (json['booking_max_date_unit'] ?? meta['_wc_booking_max_date_unit'])
            ?.toString();
    final bookingDefaultDateAvailability =
        (json['booking_default_date_availability'] ??
                meta['_wc_booking_default_date_availability'])
            ?.toString();
    final bookingFirstBlockTime =
        (json['booking_first_block_time'] ?? meta['_wc_booking_first_block_time'])
            ?.toString();

    // _wc_booking_restricted_days is serialized as a list of ints (0=Sun..6=Sat)
    // in meta_data. Sometimes it's a comma-separated string.
    final List<int>? bookingRestrictedDays;
    final dynRestricted = meta['_wc_booking_restricted_days'];
    if (dynRestricted is List) {
      bookingRestrictedDays = dynRestricted
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((e) => e >= 0 && e <= 6)
          .toList();
    } else if (dynRestricted is String && dynRestricted.isNotEmpty) {
      bookingRestrictedDays = dynRestricted
          .split(RegExp(r'[,\s]+'))
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .where((e) => e >= 0 && e <= 6)
          .toList();
    } else {
      bookingRestrictedDays = null;
    }
    final bookingHasRestrictedDays =
        (json['booking_has_restricted_days'] as bool? ??
            '${meta['_wc_booking_has_restricted_days']}'.toLowerCase() == 'yes');
    final bookingRequiresConfirmation =
        (json['booking_requires_confirmation'] as bool? ??
            '${meta['_wc_booking_requires_confirmation']}'.toLowerCase() == 'yes' ||
            '${meta['_wc_booking_requires_confirmation']}' == '1');
    final bookingUserCanCancel =
        (json['booking_user_can_cancel'] as bool? ??
            '${meta['_wc_booking_user_can_cancel']}'.toLowerCase() == 'yes' ||
            '${meta['_wc_booking_user_can_cancel']}' == '1');
    final bookingQtyMaxBookingsPerBlock =
        json['booking_qty'] is int
            ? json['booking_qty'] as int
            : int.tryParse('${meta['_wc_booking_qty'] ?? ''}');
    final bookingMinPersons =
        json['booking_min_persons'] is int
            ? json['booking_min_persons'] as int
            : int.tryParse('${meta['_wc_booking_min_persons_group'] ?? meta['_wc_booking_min_persons'] ?? ''}');
    final bookingMaxPersons =
        json['booking_max_persons'] is int
            ? json['booking_max_persons'] as int
            : int.tryParse('${meta['_wc_booking_max_persons_group'] ?? meta['_wc_booking_max_persons'] ?? ''}');
    final metaIsBookableFlag =
        (json['bookable'] as bool? ??
            '${meta['_bookable']}'.toLowerCase() == 'yes' ||
            '${meta['_bookable']}' == '1');

    return Product(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      type: typeStr,
      description: json['description']?.toString(),
      shortDescription: json['short_description']?.toString(),
      sku: json['sku']?.toString(),
      price: json['price']?.toString() ?? '0',
      regularPrice: json['regular_price']?.toString(),
      salePrice: json['sale_price']?.toString(),
      onSale: json['on_sale'] as bool? ?? false,
      inStock: json['stock_status']?.toString() == 'instock' ||
          (json['in_stock'] as bool? ?? true),
      stockQuantity: _parseStockQuantity(json['stock_quantity']),
      manageStock: json['manage_stock'] == true,
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
      bookingDuration: bookingDuration,
      bookingDurationUnit: bookingDurationUnit?.isNotEmpty == true
          ? bookingDurationUnit
          : null,
      bookingCost: bookingCost?.isNotEmpty == true ? bookingCost : null,
      bookingBlockCost: bookingBlockCost?.isNotEmpty == true ? bookingBlockCost : null,
      bookingDisplayCost: bookingDisplayCost?.isNotEmpty == true ? bookingDisplayCost : null,
      hasResources: bookingHasResourcesBool,
      resourcesAssignment: resourcesAssignment?.isNotEmpty == true
          ? resourcesAssignment
          : null,
      bookingLocation: bookingLocation?.isNotEmpty == true
          ? bookingLocation
          : null,
      bookingLocationType: bookingLocationType?.isNotEmpty == true
          ? bookingLocationType
          : null,
      bookingHasPersons: bookingHasPersons,
      bookingHasResources: bookingHasResourcesBool,
      bookingMinPersons: bookingMinPersons,
      bookingMaxPersons: bookingMaxPersons,
      bookingMinDateVal: bookingMinDateVal,
      bookingMinDateUnit: bookingMinDateUnit?.isNotEmpty == true ? bookingMinDateUnit : null,
      bookingMaxDateVal: bookingMaxDateVal,
      bookingMaxDateUnit: bookingMaxDateUnit?.isNotEmpty == true ? bookingMaxDateUnit : null,
      bookingDefaultDateAvailability: bookingDefaultDateAvailability?.isNotEmpty == true ? bookingDefaultDateAvailability : null,
      bookingFirstBlockTime: bookingFirstBlockTime?.isNotEmpty == true ? bookingFirstBlockTime : null,
      bookingRestrictedDays: bookingRestrictedDays,
      bookingHasRestrictedDays: bookingHasRestrictedDays,
      bookingRequiresConfirmation: bookingRequiresConfirmation,
      bookingUserCanCancel: bookingUserCanCancel,
      bookingQtyMaxBookingsPerBlock: bookingQtyMaxBookingsPerBlock,
      metaIsBookable: metaIsBookableFlag,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'description': description,
      'short_description': shortDescription,
      'sku': sku,
      'price': price,
      'regular_price': regularPrice,
      'sale_price': salePrice,
      'on_sale': onSale,
      'in_stock': inStock,
      'stock_quantity': stockQuantity,
      'manage_stock': manageStock,
      'images': images,
      'categories': categories.map((c) => c.toJson()).toList(),
      'vendor_name': vendorName,
      'vendor_id': vendorId,
      'rating': rating,
      'rating_count': ratingCount,
      'icon': icon,
      'color': color,
      'is_subscription': isSubscription,
      'subscription_period': subscriptionPeriod,
      'subscription_period_interval': subscriptionPeriodInterval,
      'subscription_sign_up_fee': subscriptionSignUpFee,
      'subscription_trial_length': subscriptionTrialLength,
      'subscription_trial_period': subscriptionTrialPeriod,
      'booking_duration': bookingDuration,
      'booking_duration_unit': bookingDurationUnit,
      'booking_cost': bookingCost,
      'booking_block_cost': bookingBlockCost,
      'booking_display_cost': bookingDisplayCost,
      'has_resources': hasResources,
      'booking_resources_assignment': resourcesAssignment,
      'booking_location': bookingLocation,
      'booking_location_type': bookingLocationType,
      'booking_has_persons': bookingHasPersons,
      'booking_has_resources': bookingHasResources,
      'booking_min_persons': bookingMinPersons,
      'booking_max_persons': bookingMaxPersons,
      'booking_min_date_val': bookingMinDateVal,
      'booking_min_date_unit': bookingMinDateUnit,
      'booking_max_date_val': bookingMaxDateVal,
      'booking_max_date_unit': bookingMaxDateUnit,
      'booking_default_date_availability': bookingDefaultDateAvailability,
      'booking_first_block_time': bookingFirstBlockTime,
      'booking_restricted_days': bookingRestrictedDays,
      'booking_has_restricted_days': bookingHasRestrictedDays,
      'booking_requires_confirmation': bookingRequiresConfirmation,
      'booking_user_can_cancel': bookingUserCanCancel,
      'booking_qty': bookingQtyMaxBookingsPerBlock,
      'meta_is_bookable': metaIsBookable,
    };
  }

  Product copyWith({
    int? id,
    String? name,
    String? type,
    String? description,
    String? shortDescription,
    String? sku,
    String? price,
    String? regularPrice,
    String? salePrice,
    bool? onSale,
    bool? inStock,
    int? stockQuantity,
    bool? manageStock,
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
    int? bookingDuration,
    String? bookingDurationUnit,
    String? bookingCost,
    String? bookingBlockCost,
    String? bookingDisplayCost,
    bool? hasResources,
    String? resourcesAssignment,
    String? bookingLocation,
    String? bookingLocationType,
    bool? bookingHasPersons,
    bool? bookingHasResources,
    int? bookingMinPersons,
    int? bookingMaxPersons,
    int? bookingMinDateVal,
    String? bookingMinDateUnit,
    int? bookingMaxDateVal,
    String? bookingMaxDateUnit,
    String? bookingDefaultDateAvailability,
    String? bookingFirstBlockTime,
    List<int>? bookingRestrictedDays,
    bool? bookingHasRestrictedDays,
    bool? bookingRequiresConfirmation,
    bool? bookingUserCanCancel,
    int? bookingQtyMaxBookingsPerBlock,
    bool? metaIsBookable,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      shortDescription: shortDescription ?? this.shortDescription,
      sku: sku ?? this.sku,
      price: price ?? this.price,
      regularPrice: regularPrice ?? this.regularPrice,
      salePrice: salePrice ?? this.salePrice,
      onSale: onSale ?? this.onSale,
      inStock: inStock ?? this.inStock,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      manageStock: manageStock ?? this.manageStock,
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
      bookingDuration: bookingDuration ?? this.bookingDuration,
      bookingDurationUnit: bookingDurationUnit ?? this.bookingDurationUnit,
      bookingCost: bookingCost ?? this.bookingCost,
      bookingBlockCost: bookingBlockCost ?? this.bookingBlockCost,
      bookingDisplayCost: bookingDisplayCost ?? this.bookingDisplayCost,
      hasResources: hasResources ?? this.hasResources,
      resourcesAssignment: resourcesAssignment ?? this.resourcesAssignment,
      bookingLocation: bookingLocation ?? this.bookingLocation,
      bookingLocationType: bookingLocationType ?? this.bookingLocationType,
      bookingHasPersons: bookingHasPersons ?? this.bookingHasPersons,
      bookingHasResources: bookingHasResources ?? this.bookingHasResources,
      bookingMinPersons: bookingMinPersons ?? this.bookingMinPersons,
      bookingMaxPersons: bookingMaxPersons ?? this.bookingMaxPersons,
      bookingMinDateVal: bookingMinDateVal ?? this.bookingMinDateVal,
      bookingMinDateUnit: bookingMinDateUnit ?? this.bookingMinDateUnit,
      bookingMaxDateVal: bookingMaxDateVal ?? this.bookingMaxDateVal,
      bookingMaxDateUnit: bookingMaxDateUnit ?? this.bookingMaxDateUnit,
      bookingDefaultDateAvailability: bookingDefaultDateAvailability ?? this.bookingDefaultDateAvailability,
      bookingFirstBlockTime: bookingFirstBlockTime ?? this.bookingFirstBlockTime,
      bookingRestrictedDays: bookingRestrictedDays ?? this.bookingRestrictedDays,
      bookingHasRestrictedDays: bookingHasRestrictedDays ?? this.bookingHasRestrictedDays,
      bookingRequiresConfirmation: bookingRequiresConfirmation ?? this.bookingRequiresConfirmation,
      bookingUserCanCancel: bookingUserCanCancel ?? this.bookingUserCanCancel,
      bookingQtyMaxBookingsPerBlock: bookingQtyMaxBookingsPerBlock ?? this.bookingQtyMaxBookingsPerBlock,
      metaIsBookable: metaIsBookable ?? this.metaIsBookable,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        description,
        shortDescription,
        sku,
        price,
        regularPrice,
        salePrice,
        onSale,
        inStock,
        stockQuantity,
        manageStock,
        images,
        categories,
        vendorName,
        vendorId,
        rating,
        ratingCount,
        icon,
        color,
        isSubscription,
        subscriptionPeriod,
        subscriptionPeriodInterval,
        subscriptionSignUpFee,
        subscriptionTrialLength,
        subscriptionTrialPeriod,
        bookingDuration,
        bookingDurationUnit,
        bookingCost,
        bookingBlockCost,
        bookingDisplayCost,
        hasResources,
        resourcesAssignment,
        bookingLocation,
        bookingLocationType,
        bookingHasPersons,
        bookingHasResources,
        bookingMinPersons,
        bookingMaxPersons,
        bookingMinDateVal,
        bookingMinDateUnit,
        bookingMaxDateVal,
        bookingMaxDateUnit,
        bookingDefaultDateAvailability,
        bookingFirstBlockTime,
        bookingRestrictedDays,
        bookingHasRestrictedDays,
        bookingRequiresConfirmation,
        bookingUserCanCancel,
        bookingQtyMaxBookingsPerBlock,
        metaIsBookable,
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
