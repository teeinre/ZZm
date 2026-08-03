import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/product.dart';
import '../widgets/product_tile.dart';
import '../providers/products_provider.dart';
import 'product_detail_screen.dart';

class VendorProfileScreen extends StatefulWidget {
  final int vendorId;
  final String? vendorName;

  const VendorProfileScreen({
    super.key,
    required this.vendorId,
    this.vendorName,
  });

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ApiService _apiService = ApiService();

  // Vendor data
  Map<String, dynamic>? _vendorData;
  int? _vendorUserId;
  bool _isLoadingVendor = true;
  String? _vendorError;

  // Products
  List<Product> _products = [];
  bool _isLoadingProducts = true;

  // Follow state
  bool _isFollowing = false;
  final StorageService _storage = StorageService();

  // Review form
  final TextEditingController _reviewController = TextEditingController();
  final TextEditingController _reviewNameController = TextEditingController();
  final TextEditingController _reviewEmailController = TextEditingController();
  int _reviewRating = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // ── Guard: block access to excluded vendor profiles (e.g. vendor 126) ──
    if (ApiConstants.isVendorExcluded(
        id: widget.vendorId, name: widget.vendorName)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _isLoadingVendor = false;
          _vendorError = 'This store is no longer available.';
        });
      });
      return;
    }
    _loadFollowState();
    _loadVendorData();
  }

  Future<void> _loadFollowState() async {
    final saved = await _storage.isVendorSaved(widget.vendorId);
    if (mounted) setState(() => _isFollowing = saved);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reviewController.dispose();
    _reviewNameController.dispose();
    _reviewEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadVendorData() async {
    setState(() {
      _isLoadingVendor = true;
      _vendorError = null;
    });
    try {
      final data = await _apiService.getDokanStore(widget.vendorId);
      if (!mounted) return;
      if (data != null) {
        final uid = data['user_id'];
        setState(() {
          _vendorData = data;
          _vendorUserId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
          _isLoadingVendor = false;
        });
        _loadProducts();
      } else {
        setState(() {
          _vendorError = 'Vendor not found';
          _isLoadingVendor = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vendorError = 'Failed to load vendor';
        _isLoadingVendor = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      List<Product> products;

      // ── Step 1: vendor-scoped Dokan endpoint (preferred) ──
      products = await _apiService.getDokanStoreProducts(
        widget.vendorId,
        perPage: 50,
      );

      // ── Step 2: author-based WC API fallback ──
      if (products.isEmpty) {
        final uid = _vendorUserId ?? widget.vendorId;
        if (uid != null && uid > 0) {
          products = await _apiService.getVendorProducts(
            widget.vendorId,
            authorUserId: uid,
            perPage: 50,
          );
        }
      }

      // ── Step 3: vendor-api.php fallback ──
      if (products.isEmpty) {
        final raw = await _apiService.getVendorApiProducts(perPage: 50);
        products = raw.where((p) => p['id'] != null).map<Product>((p) => Product(
          id: int.tryParse(p['id']?.toString() ?? '') ?? 0,
          name: p['name']?.toString() ?? '',
          price: p['price']?.toString() ?? '0',
          regularPrice: p['regular_price']?.toString(),
          salePrice: p['sale_price']?.toString(),
          images: _parseImageUrls(p['images']),
          onSale: p['on_sale'] == true,
          inStock: p['stock_status']?.toString() != 'outofstock',
          stockQuantity: int.tryParse(p['stock_quantity']?.toString() ?? '') ?? 0,
          ratingCount: int.tryParse(p['rating_count']?.toString() ?? '') ?? 0,
          rating: double.tryParse(p['average_rating']?.toString() ?? ''),
          shortDescription: p['short_description']?.toString() ?? '',
          categories: const [],
        )).toList();
      }

      // ── Strict product scoping ──
      // Only keep products that actually belong to this vendor.
      // Prevents cross-leaked products from endpoint failures or caches.
      products = products.where((p) {
        // 1) If vendor ID is present on product — must match
        final vid = p.vendorId;
        if (vid != null && vid > 0) {
          return vid == widget.vendorId;
        }
        // 2) Else match by vendor name (fallback)
        if (p.vendorName != null &&
            p.vendorName!.isNotEmpty &&
            _storeName != 'Vendor Store') {
          return p.vendorName!.toLowerCase() == _storeName.toLowerCase() ||
              p.vendorName!.toLowerCase().contains(
                  _storeName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''));
        }
        // 3) No vendor metadata at all — keep only if we have strong
        //    endpoint guarantees (Dokan store-scoped endpoint already applied above)
        return true;
      }).toList();

      // Also ensure any excluded vendor's products never leak
      products = products.where((p) => !ApiConstants.isVendorExcluded(
          id: p.vendorId, name: p.vendorName)).toList();

      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProducts = false);
    }
  }

  List<String> _parseImageUrls(dynamic images) {
    if (images == null) return [];
    if (images is List) {
      return images.map((i) {
        if (i is Map) return i['src']?.toString() ?? '';
        return i.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  // ─── Helpers ───

  String get _storeName =>
      _vendorData?['store_name']?.toString() ??
      widget.vendorName ??
      'Vendor Store';

  String? get _bannerUrl => _vendorData?['banner']?.toString();
  String? get _gravatarUrl => _vendorData?['gravatar']?.toString();
  bool get _isTrusted => _vendorData?['trusted'] == true;

  String? get _address {
    final addr = _vendorData?['address'];
    if (addr is Map) {
      final parts = [
        addr['street_1']?.toString(),
        addr['street_2']?.toString(),
        addr['city']?.toString(),
        addr['state']?.toString(),
        addr['country']?.toString(),
      ].where((e) => e != null && e.isNotEmpty);
      return parts.isNotEmpty ? parts.join(', ') : null;
    }
    return null;
  }

  double get _rating {
    final r = _vendorData?['rating'];
    if (r is num) return r.toDouble();
    return double.tryParse(r?.toString() ?? '') ?? 0.0;
  }

  int get _ratingCount {
    final c = _vendorData?['rating_count'];
    if (c is int) return c;
    return int.tryParse(c?.toString() ?? '') ?? 0;
  }

  bool get _isOpen {
    final status = _vendorData?['store_open_close'];
    if (status is Map) {
      return status['open'] == true || status['is_open'] == true;
    }
    return true;
  }

  String get _openCloseText => _isOpen ? 'Open now' : 'Closed';

  Map<String, dynamic> get _social {
    final s = _vendorData?['social'];
    if (s is Map) return Map<String, dynamic>.from(s);
    return {};
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: _isLoadingVendor
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldColor),
            )
          : _vendorError != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.store_outlined,
              size: 64, color: AppColors.inkSoftColor),
          const SizedBox(height: 16),
          Text(_vendorError!,
              style:
                  const TextStyle(color: AppColors.inkSoftColor, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadVendorData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Gradients for banner overlay
    return Stack(
      children: [
        NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              backgroundColor:
                  innerBoxIsScrolled ? AppColors.creamColor : Colors.transparent,
              elevation: innerBoxIsScrolled ? 1 : 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back,
                    color: innerBoxIsScrolled
                        ? AppColors.inkColor
                        : AppColors.whiteColor),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                _storeName,
                style: TextStyle(
                  color: innerBoxIsScrolled
                      ? AppColors.inkColor
                      : AppColors.whiteColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces',
                ),
              ),
              centerTitle: false,
              actions: [
                IconButton(
                  icon: Icon(Icons.share_outlined,
                      color: innerBoxIsScrolled
                          ? AppColors.inkColor
                          : AppColors.whiteColor),
                  onPressed: () {},
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildBannerHeader(),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                tabBar: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.goldColor,
                  unselectedLabelColor: AppColors.inkSoftColor,
                  indicatorColor: AppColors.goldColor,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: const [
                    Tab(text: 'Products'),
                    Tab(text: 'About'),
                    Tab(text: 'Reviews'),
                    Tab(text: 'Contact'),
                    Tab(text: 'Live'),
                  ],
                ),
                color: AppColors.creamColor,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildProductsTab(),
              _buildAboutTab(),
              _buildReviewsTab(),
              _buildContactTab(),
              _buildLiveTab(),
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          right: 20,
          child: _buildFollowButton(),
        ),
      ],
    );
  }

  Widget _buildBannerHeader() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Banner image
        if (_bannerUrl != null)
          Image.network(
            _bannerUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.indigoColor, AppColors.indigoDeepColor],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.indigoColor, AppColors.indigoDeepColor],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        // Dark overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.2),
                Colors.black.withOpacity(0.6),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        // Vendor info overlay at bottom
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Logo / gravatar
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.whiteColor, width: 3),
                      image: _gravatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_gravatarUrl!),
                              fit: BoxFit.cover,
                              onError: (_, __) {},
                            )
                          : null,
                      color: AppColors.indigoPaleColor,
                    ),
                    child: _gravatarUrl == null
                        ? const Icon(Icons.store,
                            color: AppColors.indigoColor, size: 32)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _storeName,
                                style: const TextStyle(
                                  color: AppColors.whiteColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Fraunces',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_isTrusted) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified,
                                  color: AppColors.goldColor, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Location
                        if (_address != null)
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  color: AppColors.whiteColor,
                                  size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _address!,
                                  style: const TextStyle(
                                    color: AppColors.whiteColor,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        // Rating + open/close
                        Row(
                          children: [
                            _buildRatingStars(
                                _rating, size: 14, color: AppColors.goldColor),
                            const SizedBox(width: 6),
                            Text(
                              '${_rating.toStringAsFixed(1)} (${_ratingCount})',
                              style: const TextStyle(
                                color: AppColors.whiteColor,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isOpen
                                    ? AppColors.goldColor.withOpacity(0.85)
                                    : AppColors.coralColor.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _openCloseText,
                                style: const TextStyle(
                                  color: AppColors.whiteColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Products Tab ───

  Widget _buildProductsTab() {
    if (_isLoadingProducts) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.goldColor));
    }
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined,
                size: 64, color: AppColors.goldColor.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No products yet',
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.goldColor,
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return GestureDetector(
            onTap: () => _openProductDetail(product),
            child: ProductTile(product: product),
          );
        },
      ),
    );
  }

  void _openProductDetail(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.creamColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(product.name,
                style: const TextStyle(
                    color: AppColors.inkColor, fontWeight: FontWeight.w600)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.images.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      product.images.first,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 240,
                        color: AppColors.goldColor.withOpacity(0.15),
                        child: const Icon(Icons.image_outlined,
                            color: AppColors.inkSoftColor, size: 48),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(product.name,
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Fraunces')),
                if (product.vendorName != null) ...[
                  const SizedBox(height: 4),
                  Text('by ${product.vendorName}',
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 14)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '£${(double.tryParse(product.price) ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppColors.goldColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                    ),
                    if (product.onSale) ...[
                      const SizedBox(width: 8),
                      Text('£${product.regularPrice}',
                          style: const TextStyle(
                              color: AppColors.inkSoftColor,
                              fontSize: 16,
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ],
                ),
                if (product.rating != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildRatingStars(product.rating!, size: 16),
                      const SizedBox(width: 6),
                      Text('(${product.ratingCount})',
                          style: const TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 13)),
                    ],
                  ),
                ],
                if (product.description != null &&
                    product.description!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Description',
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    product.description!,
                    style: const TextStyle(
                        color: AppColors.inkColor, fontSize: 14, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── About Tab ───

  Widget _buildAboutTab() {
    final toc = _vendorData?['store_toc']?.toString();
    final social = _social;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store Description / Terms
          if (toc != null && toc.isNotEmpty) ...[
            const Text('About the Store',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                toc,
                style: const TextStyle(
                    color: AppColors.inkColor, fontSize: 14, height: 1.6),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Social Links
          if (social.isNotEmpty) ...[
            const Text('Connect',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (social['fb'] != null && social['fb'].toString().isNotEmpty)
                  _buildSocialChip(Icons.facebook, 'Facebook',
                      social['fb'].toString()),
                if (social['twitter'] != null &&
                    social['twitter'].toString().isNotEmpty)
                  _buildSocialChip(Icons.alternate_email, 'Twitter',
                      social['twitter'].toString()),
                if (social['instagram'] != null &&
                    social['instagram'].toString().isNotEmpty)
                  _buildSocialChip(Icons.camera_alt_outlined, 'Instagram',
                      social['instagram'].toString()),
                if (social['youtube'] != null &&
                    social['youtube'].toString().isNotEmpty)
                  _buildSocialChip(Icons.play_circle_outline, 'YouTube',
                      social['youtube'].toString()),
                if (social['tiktok'] != null &&
                    social['tiktok'].toString().isNotEmpty)
                  _buildSocialChip(
                      Icons.music_note_outlined, 'TikTok',
                      social['tiktok'].toString()),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Address with map placeholder
          if (_address != null) ...[
            const Text('Location',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.indigoPaleColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map_outlined,
                      color: AppColors.indigoColor, size: 40),
                  const SizedBox(height: 8),
                  const Text('Map View',
                      style: TextStyle(
                          color: AppColors.indigoColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _address!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSocialChip(IconData icon, String label, String url) {
    return GestureDetector(
      onTap: () {
        // Launch URL would go here with url_launcher package
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.sandColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.indigoColor, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.indigoColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ─── Reviews Tab ───

  Widget _buildReviewsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rating summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  _rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppColors.indigoColor,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Fraunces',
                  ),
                ),
                const SizedBox(height: 4),
                _buildRatingStars(_rating, size: 22),
                const SizedBox(height: 8),
                Text(
                  '$_ratingCount review${_ratingCount != 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: AppColors.inkSoftColor, fontSize: 14),
                ),
                const SizedBox(height: 12),
                // Rating bars
                _buildRatingBar(5, 0.6),
                _buildRatingBar(4, 0.25),
                _buildRatingBar(3, 0.1),
                _buildRatingBar(2, 0.03),
                _buildRatingBar(1, 0.02),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Reviews placeholder
          const Text('Customer Reviews',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.rate_review_outlined,
                    size: 48, color: AppColors.goldColor.withOpacity(0.5)),
                const SizedBox(height: 12),
                const Text('Reviews will appear here',
                    style: TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 14)),
                const SizedBox(height: 4),
                const Text(
                    'Customer feedback and ratings for this vendor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Leave a review
          const Text('Leave a Review',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Star selector
                Row(
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () => setState(() => _reviewRating = i + 1),
                      child: Icon(
                        i < _reviewRating
                            ? Icons.star
                            : Icons.star_border,
                        color: AppColors.goldColor,
                        size: 28,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reviewNameController,
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reviewEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Your email',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reviewController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Write your review...',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Review submitted. Thank you!'),
                          backgroundColor: AppColors.goldColor,
                        ),
                      );
                      _reviewController.clear();
                      _reviewNameController.clear();
                      _reviewEmailController.clear();
                      setState(() => _reviewRating = 5);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Submit Review',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRatingBar(int stars, double fraction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$stars',
              style: const TextStyle(
                  color: AppColors.inkSoftColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          const Icon(Icons.star, color: AppColors.goldColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: AppColors.indigoPaleColor,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.goldColor),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Contact Tab ───

  Widget _buildContactTab() {
    final phone = _vendorData?['phone']?.toString();
    final email = _vendorData?['email']?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Get in Touch',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text(
            'Have a question about a product? Send this vendor a message.',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Contact info cards
          if (phone != null && phone.isNotEmpty) ...[
            _buildContactCard(Icons.phone_outlined, 'Phone', phone),
            const SizedBox(height: 10),
          ],
          if (email != null && email.isNotEmpty) ...[
            _buildContactCard(Icons.email_outlined, 'Email', email),
            const SizedBox(height: 10),
          ],
          if (_address != null) ...[
            _buildContactCard(Icons.location_on_outlined, 'Address', _address!),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 14),

          // Contact form
          const Text('Send a Message',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Your email',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Your message...',
                    hintStyle: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.creamColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Message sent! The vendor will get back to you.'),
                          backgroundColor: AppColors.goldColor,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Send Message',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildContactCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.indigoPaleColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.indigoColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Live Tab ───

  Widget _buildLiveTab() {
    // Live stream state from vendor API/meta
    final bool isLive = _vendorData?['is_live'] == true;
    final String streamTitle =
        _vendorData?['live_title']?.toString() ?? '$_storeName Live';
    final int viewerCount =
        int.tryParse(_vendorData?['live_viewers']?.toString() ?? '0') ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text('Live Stream',
                  style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Fraunces')),
              const Spacer(),
              if (isLive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.coralColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (isLive) ...[
            // Video Player Area
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: AppColors.indigoDeepColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Video placeholder
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.goldColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: AppColors.goldColor, size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text('Streaming live...',
                            style: TextStyle(
                                color: AppColors.whiteColor, fontSize: 14)),
                      ],
                    ),
                  ),
                  // Viewer count badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_outlined,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text('$viewerCount watching',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  // Live badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.coralColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.white, size: 8),
                          SizedBox(width: 4),
                          Text('LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Stream info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(streamTitle,
                      style: const TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 4),
                  Text('Hosted by $_storeName',
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Live Chat Section
            const Text('Live Chat',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Sample chat messages
                  Expanded(
                    child: Center(
                      child: Text(
                        'No messages yet. Be the first to chat!',
                        style: TextStyle(
                          color: AppColors.inkSoftColor,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  // Chat input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Send a message...',
                            hintStyle: const TextStyle(
                                color: AppColors.inkSoftColor, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.creamColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.goldColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send,
                            color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tagged Products
            const Text('Products in this Stream',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _products.take(5).length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Featured / pinned product highlight
                    return Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: AppColors.goldColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.goldColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.push_pin,
                              color: AppColors.goldColor, size: 24),
                          const SizedBox(height: 8),
                          const Text('Pinned',
                              style: TextStyle(
                                  color: AppColors.goldColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const Text('Product',
                              style: TextStyle(
                                  color: AppColors.inkSoftColor,
                                  fontSize: 11)),
                        ],
                      ),
                    );
                  }
                  final product = _products[index - 1];
                  return GestureDetector(
                    onTap: () => _openProductDetail(product),
                    child: Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: AppColors.whiteColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                            child: product.images.isNotEmpty
                                ? Image.network(
                                    product.images.first,
                                    height: 80,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 80,
                                      color: AppColors.indigoPaleColor,
                                      child: const Icon(Icons.image_outlined,
                                          color: AppColors.inkSoftColor,
                                          size: 24),
                                    ),
                                  )
                                : Container(
                                    height: 80,
                                    color: AppColors.indigoPaleColor,
                                    child: const Icon(Icons.image_outlined,
                                        color: AppColors.inkSoftColor,
                                        size: 24),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.inkColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    '£${(double.tryParse(product.price) ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppColors.goldColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            // No active stream
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.indigoPaleColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.videocam_off_outlined,
                        size: 36,
                        color: AppColors.indigoColor.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 16),
                  const Text('No active stream',
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 8),
                  const Text(
                    'This vendor is not currently streaming.\nCheck back later or browse their products.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(0),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                    label: const Text('Browse Products'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldColor,
                      side: const BorderSide(color: AppColors.goldColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String user, String message, {bool isHost = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isHost ? AppColors.goldColor : AppColors.indigoPaleColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHost ? Icons.store : Icons.person,
              color: isHost ? Colors.white : AppColors.indigoColor,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user,
                        style: TextStyle(
                            color: isHost
                                ? AppColors.goldColor
                                : AppColors.inkColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.goldColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Host',
                            style: TextStyle(
                                color: AppColors.goldColor, fontSize: 9)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(message,
                    style: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Follow Button ───

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: () async {
        final newState = !_isFollowing;
        setState(() => _isFollowing = newState);
        if (newState) {
          await _storage.saveVendorFollow(widget.vendorId);
        } else {
          await _storage.removeVendorFollow(widget.vendorId);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFollowing
                ? 'You are now following $_storeName'
                : 'Unfollowed $_storeName'),
            backgroundColor: AppColors.goldColor,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _isFollowing ? AppColors.coralColor : AppColors.goldColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.goldColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          _isFollowing ? Icons.favorite : Icons.favorite_border,
          color: AppColors.whiteColor,
          size: 26,
        ),
      ),
    );
  }

  // ─── Rating Stars Helper ───

  Widget _buildRatingStars(double rating,
      {double size = 16, Color? color}) {
    final starColor = color ?? AppColors.goldColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (rating >= i + 1) {
          return Icon(Icons.star, color: starColor, size: size);
        } else if (rating > i && rating < i + 1) {
          return Icon(Icons.star_half, color: starColor, size: size);
        } else {
          return Icon(Icons.star_border, color: starColor, size: size);
        }
      }),
    );
  }
}

// ─── SliverPersistentHeader for TabBar ───

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color color;

  _TabBarDelegate({required this.tabBar, required this.color});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || color != oldDelegate.color;
}
