import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../constants/app_colors.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/api_service.dart';
import 'livestream_viewer_screen.dart';

/// Displays all available livestreams in a scrollable grid.
/// Reachable via the "See All" button on the home screen livestream section.
class AllLivestreamsScreen extends StatefulWidget {
  const AllLivestreamsScreen({super.key});

  @override
  State<AllLivestreamsScreen> createState() => _AllLivestreamsScreenState();
}

class _AllLivestreamsScreenState extends State<AllLivestreamsScreen> {
  List<Map<String, dynamic>> _streams = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllStreams();
  }

  Future<void> _loadAllStreams() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = ApiService();
      final streams = await api.getPublicLivestreams();
      if (mounted) {
        setState(() {
          _streams = streams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _streams = [];
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _openStreamViewer(int index) {
    try {
      final active = _streams.where((s) {
        final rawStatus = s['status'];
        final status = rawStatus?.toString().toLowerCase() ?? '';
        return status == 'live' || status.isEmpty;
      }).toList();
      final idx = active.indexWhere((s) => s['id'] == _streams[index]['id']);
      if (idx >= 0) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => LivestreamViewerScreen(
            streams: active.cast<Map<String, dynamic>>(),
            initialIndex: idx,
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open stream: ${e.toString()}'),
            backgroundColor: AppColors.coralColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _addStreamProductToCart(Map<String, dynamic> stream) {
    final productName = stream['product_name']?.toString();
    final productPrice = stream['product_price']?.toString() ?? '0';
    final productIdRaw = stream['product_id'];
    if (productName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product info unavailable.'), backgroundColor: AppColors.inkSoftColor),
      );
      return;
    }

    final productId = productIdRaw is int
        ? productIdRaw
        : int.tryParse(productIdRaw?.toString() ?? '0') ?? 0;

    final productImage = stream['product_image']?.toString() ?? '';

    final product = Product(
      id: productId,
      name: productName,
      price: productPrice,
      onSale: false,
      inStock: true,
      stockQuantity: 0,
      images: productImage.isNotEmpty ? [productImage] : [],
      categories: const [],
      ratingCount: 0,
      vendorName: stream['vendor_name']?.toString(),
      vendorId: 0,
    );

    try {
      context.read<CartProvider>().addToCart(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$productName added to cart!'),
          backgroundColor: AppColors.goldColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.coralColor, behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Live Streams',
              style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.goldColor),
            onPressed: _loadAllStreams,
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingGrid()
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadAllStreams,
              child: _streams.isEmpty
                  ? _buildEmptyState()
                  : CustomScrollView(
                      slivers: [
                        if (_errorMessage != null)
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.goldColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 16, color: AppColors.goldColor),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text('Showing demo streams. Connect to backend for live data.',
                                      style: TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.55,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _buildStreamCard(_streams[i], i),
                              childCount: _streams.length,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.blackPaleColor,
        highlightColor: AppColors.creamColor,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv, size: 64, color: AppColors.inkSoftColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text('No live streams right now',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
            const SizedBox(height: 8),
            const Text('Check back later for live streams from our vendors.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoftColor)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadAllStreams,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.goldColor,
                side: const BorderSide(color: AppColors.goldColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamCard(Map<String, dynamic> stream, int index) {
    final title = stream['title']?.toString() ?? 'Live Stream';
    final vendorName = stream['vendor_name']?.toString() ?? stream['store_name']?.toString() ?? 'Vendor';
    final thumbnail = stream['thumbnail']?.toString() ?? '';
    final viewerCount = stream['viewers']?.toString() ?? '0';
    final rawPlatform = stream['platform'];
    final platform = rawPlatform?.toString().toLowerCase() ?? '';
    final productName = stream['product_name']?.toString();
    final productPrice = stream['product_price']?.toString();

    IconData platformIcon;
    switch (platform) {
      case 'youtube': platformIcon = Icons.play_circle_outline; break;
      case 'facebook': platformIcon = Icons.facebook; break;
      case 'tiktok': platformIcon = Icons.music_note; break;
      case 'instagram': platformIcon = Icons.camera_alt_outlined; break;
      default: platformIcon = Icons.live_tv;
    }

    return GestureDetector(
      onTap: () => _openStreamViewer(index),
      onLongPress: () => _loadAllStreams(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.inkColor.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail area
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.indigoColor, AppColors.indigoColor.withOpacity(0.7), AppColors.coralColor.withOpacity(0.5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: thumbnail.isNotEmpty
                        ? Image.network(
                            thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(platformIcon, color: Colors.white.withOpacity(0.3), size: 40),
                            ),
                          )
                        : Center(
                            child: Icon(platformIcon, color: Colors.white.withOpacity(0.3), size: 40),
                          ),
                  ),
                ),
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulsingDot(),
                        SizedBox(width: 4),
                        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility, color: Colors.white, size: 10),
                        const SizedBox(width: 3),
                        Text(viewerCount, style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
                    const SizedBox(height: 4),
                    Text(vendorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
                    if (productName != null && productPrice != null) ...[
                      const Spacer(),
                      // Product name tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.goldColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shopping_bag_outlined, size: 10, color: AppColors.goldColor),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.goldColor)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Price + Add to Cart
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('\u00A3$productPrice',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
                          GestureDetector(
                            onTap: () => _addStreamProductToCart(stream),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.goldColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_shopping_cart, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated pulsing red dot used on LIVE badges.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => Opacity(
        opacity: _animation.value,
        child: child,
      ),
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    );
  }
}
