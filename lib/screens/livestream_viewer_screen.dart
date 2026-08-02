import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';

/// Full-screen livestream viewer with in-app playback and vendor switching.
///
/// For YouTube and Twitch, streams are embedded via WebView. For Facebook,
/// Instagram, and TikTok streams (which restrict embedding), the app opens
/// the platform's native app or browser.
class LivestreamViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> streams;
  final int initialIndex;

  const LivestreamViewerScreen({
    super.key,
    required this.streams,
    this.initialIndex = 0,
  });

  @override
  State<LivestreamViewerScreen> createState() => _LivestreamViewerScreenState();
}

class _LivestreamViewerScreenState extends State<LivestreamViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  // Cached controllers per page index to avoid rebuilding on every frame.
  final Map<int, WebViewController> _controllerCache = {};
  final Map<int, bool> _pageLoaded = {};
  final Map<int, bool> _pageErrored = {};
  final Map<int, String> _pageStreamType = {}; // tracks 'youtube', 'twitch', etc per page

  bool _isStreamLoading = true;
  bool _hasStreamError = false;
  int _viewerCount = 0;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.streams.length - 1);
    _pageController = PageController(initialPage: _currentIndex);

    // Simulate viewer heartbeat every 30 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          _viewerCount += 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // Chrome UA for Android — YouTube checks this and blocks generic WebView agents.
  static const String _chromeUA = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  WebViewController _getOrCreateController(int index, String url) {
    if (_controllerCache.containsKey(index)) {
      return _controllerCache[index]!;
    }
    final embedUrl = _buildEmbedUrl(url);
    final type = _classifyUrl(url);

    // Build headers required by YouTube to avoid error 153 (playback restricted).
    final Map<String, String> headers = {};
    if (type == 'youtube') {
      headers['Referer'] = 'https://www.youtube.com/';
      headers['Origin'] = 'https://www.youtube.com';
    }

    // YouTube also needs the embed URL to include origin param
    final String finalUrl = type == 'youtube'
        ? '$embedUrl&origin=https://www.youtube.com'
        : embedUrl;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.inkColor)
      ..setUserAgent(_chromeUA)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() {
              _pageLoaded[index] = false;
              _isStreamLoading = true;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() {
              _pageLoaded[index] = true;
              _isStreamLoading = false;
            });
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _pageErrored[index] = true;
                _pageLoaded[index] = true;
                _isStreamLoading = false;
                _hasStreamError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(finalUrl), headers: headers);
    _controllerCache[index] = controller;
    _pageLoaded[index] = false;
    _pageErrored[index] = false;
    _pageStreamType[index] = type;
    return controller;
  }

  /// Returns the stream protocol category for a given URL.
  /// Recognises: youtube, twitch, facebook, hls (m3u8), rtmp, and generic web.
  static String _classifyUrl(String? url) {
    if (url == null || url.isEmpty) return 'custom';
    final u = url.toLowerCase().trim();

    // Known platforms
    if (u.contains('youtube.com') || u.contains('youtu.be')) return 'youtube';
    if (u.contains('twitch.tv')) return 'twitch';
    if (u.contains('facebook.com') || u.contains('fb.watch')) return 'facebook';
    if (u.contains('instagram.com')) return 'instagram';
    if (u.contains('tiktok.com')) return 'tiktok';

    // Streaming protocols
    if (u.startsWith('rtmp://') || u.startsWith('rtmps://')) return 'rtmp';
    if (u.endsWith('.m3u8') || u.contains('.m3u8?')) return 'hls';
    if (u.endsWith('.mpd') || u.contains('.mpd?')) return 'dash';

    // Generic web URL — try embedding
    if (u.startsWith('http://') || u.startsWith('https://')) return 'web';
    return 'custom';
  }

  /// Whether this stream type can be embedded inside a WebView.
  static bool _isEmbeddable(String type) {
    return type == 'youtube' || type == 'twitch' || type == 'facebook' ||
           type == 'hls' || type == 'dash' || type == 'web';
  }

  /// Build the URL that should be loaded in the WebView.
  String _buildEmbedUrl(String rawUrl) {
    final type = _classifyUrl(rawUrl);

    if (type == 'youtube') {
      var id = '';
      final uri = Uri.tryParse(rawUrl);
      if (uri != null) {
        id = uri.queryParameters['v'] ?? uri.pathSegments.where((s) => s.isNotEmpty).last;
      }
      if (id.isEmpty) return rawUrl;
      // Priority 1: regular youtube.com/embed (less restrictive than nocookie for some videos)
      // nocookie is used as backup only — some live streams are blocked on nocookie with error 152
      return 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&enablejsapi=1&rel=0&modestbranding=1&iv_load_policy=3';
    }
    if (type == 'twitch') {
      var channel = '';
      final uri = Uri.tryParse(rawUrl);
      if (uri != null) {
        channel = uri.pathSegments.where((s) => s.isNotEmpty).last;
      }
      return 'https://player.twitch.tv/?channel=$channel&parent=zzmore.store&autoplay=true';
    }
    if (type == 'facebook') {
      return 'https://www.facebook.com/plugins/video.php?href=${Uri.encodeComponent(rawUrl)}&show_text=false&autoplay=true&mute=1&width=560';
    }
    if (type == 'hls') {
      // Load HLS stream via a minimal HTML5 video page in the WebView
      return 'data:text/html,${Uri.encodeComponent(
        '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>*{margin:0;padding:0;background:#000}video{width:100vw;height:100vh;object-fit:contain}</style>'
        '</head><body><video autoplay muted playsinline controls src="$rawUrl"></video></body></html>'
      )}';
    }
    if (type == 'dash') {
      // Load DASH stream via HTML5 video (if browser supports it) or pass through
      return 'data:text/html,${Uri.encodeComponent(
        '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>*{margin:0;padding:0;background:#000}video{width:100vw;height:100vh;object-fit:contain}</style>'
        '</head><body><video autoplay muted playsinline controls src="$rawUrl"></video></body></html>'
      )}';
    }
    if (type == 'web') {
      // Generic web URL — load directly in WebView (many streaming platforms use this)
      return rawUrl;
    }
    return rawUrl;
  }

  Widget _buildStreamPage(Map<String, dynamic> stream, int index) {
    final url = stream['url']?.toString() ?? '';
    final type = _classifyUrl(url);
    final title = stream['title']?.toString() ?? 'Live Stream';
    final vendorName = stream['vendor_name']?.toString() ?? stream['store_name']?.toString() ?? 'Vendor';
    final viewers = stream['viewers']?.toString() ?? '0';
    final embeddable = _isEmbeddable(type);

    if (!embeddable) {
      // Non-embeddable stream (RTMP, Instagram, TikTok, unknown) — show launch card
      String platformLabel = type == 'rtmp' ? 'RTMP' : type;
      IconData launchIcon = Icons.open_in_new;
      if (type == 'rtmp') { launchIcon = Icons.videocam; }
      if (type == 'instagram') { launchIcon = Icons.camera_alt_outlined; platformLabel = 'Instagram'; }
      if (type == 'tiktok') { launchIcon = Icons.music_note; platformLabel = 'TikTok'; }
      return Container(
        color: AppColors.inkColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type == 'facebook' ? Icons.facebook : launchIcon,
                  size: 64,
                  color: AppColors.goldColor,
                ),
                const SizedBox(height: 20),
                Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  type == 'rtmp' ? 'This stream uses RTMP protocol and requires an external player.' :
                  'Streaming on ${platformLabel[0].toUpperCase()}${platformLabel.substring(1)}',
                  style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                    onPressed: () {
                      if (url.isNotEmpty) {
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in External Player'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _buildProductCard(stream),
                  ),
                ],
            ),
          ),
        ),
      );
    }

    // Cached controller for stable playback
    final controller = _getOrCreateController(index, url);
    final isLoading = !(_pageLoaded[index] ?? false);
    final hasError = _pageErrored[index] ?? false;

    // Facebook is embeddable but may be blocked — try embed, fall back to external
    if (type == 'facebook') {
      return Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  color: AppColors.inkColor,
                  child: Stack(
                    children: [
                      WebViewWidget(controller: controller),
                      if (isLoading)
                        _buildLoadingOverlay(),
                    ],
                  ),
                ),
              ),
              _buildStreamInfoBar(title, vendorName, viewers),
              _buildProductCard(stream),
            ],
          ),
          if (hasError)
            Container(
              color: AppColors.indigoColor.withValues(alpha: 0.95),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.facebook, color: AppColors.goldColor, size: 40),
                      const SizedBox(height: 12),
                      const Text('Facebook does not support in-app embedding',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('Tap below to watch the stream on Facebook.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('Watch on Facebook'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1877F2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // YouTube / Twitch — embeddable with loading & error overlay
    return Column(
      children: [
        Expanded(
          child: Container(
            color: AppColors.inkColor,
            child: Stack(
              children: [
                WebViewWidget(controller: controller),
                if (isLoading)
                  _buildLoadingOverlay(),
                if (hasError)
                  _buildErrorOverlay(index, () {
                    setState(() {
                      _controllerCache.remove(index);
                      _pageLoaded.remove(index);
                      _pageErrored.remove(index);
                      _pageStreamType.remove(index);
                    });
                    setState(() {});
                  }, url),
              ],
            ),
          ),
        ),
        _buildStreamInfoBar(title, vendorName, viewers),
        _buildProductCard(stream),

        // Stream switcher (horizontal list)
        Container(
          height: 100,
          color: AppColors.inkColor,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: widget.streams.length,
            itemBuilder: (_, i) {
              final s = widget.streams[i];
              final isActive = i == _currentIndex;
              return GestureDetector(
                onTap: () {
                  _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                },
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isActive ? AppColors.goldColor : Colors.white24, width: isActive ? 2 : 1),
                    gradient: LinearGradient(
                      colors: isActive
                          ? [AppColors.indigoColor, AppColors.coralColor.withOpacity(0.5)]
                          : [AppColors.blackSoftColor, AppColors.inkColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        s['vendor_name']?.toString() ?? s['store_name']?.toString() ?? 'Vendor',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppColors.inkColor,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(color: AppColors.goldColor, strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('Connecting to stream...',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(int index, VoidCallback onRetry, String originalUrl) {
    final streamType = _pageStreamType[index] ?? '';
    final bool isYoutube = streamType == 'youtube';

    final IconData errorIcon = isYoutube ? Icons.play_circle_outline : Icons.error_outline;
    final Color errorColor = isYoutube ? const Color(0xFFFF0000) : AppColors.coralColor;
    final String title = isYoutube
        ? 'This video cannot be embedded'
        : 'Stream unavailable';
    final String subtitle = isYoutube
        ? 'The video owner has disabled embedding. Watch directly on YouTube instead.'
        : 'The stream could not be loaded. This may happen if the stream has ended or is private.';
    final String externalLabel = isYoutube ? 'Watch on YouTube' : 'Open in Browser';

    return Container(
      color: AppColors.inkColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(errorIcon, color: errorColor, size: 48),
              const SizedBox(height: 16),
              Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldColor,
                      side: const BorderSide(color: AppColors.goldColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(originalUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: Text(externalLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isYoutube ? const Color(0xFFFF0000) : AppColors.goldColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the stream info bar showing LIVE badge, title, vendor name, viewers.
  Widget _buildStreamInfoBar(String title, String vendorName, String viewers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.inkColor.withValues(alpha: 0.95),
      child: Row(
        children: [
          Container(
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
                Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                Text('$vendorName  ·  $viewers watching',
                  style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the product card overlay for a livestream with a featured product.
  Widget _buildProductCard(Map<String, dynamic> stream) {
    final productName = stream['product_name']?.toString();
    final productPrice = stream['product_price']?.toString();
    if (productName == null || productPrice == null) return const SizedBox.shrink();

    final productImage = stream['product_image']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.goldColor.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Product thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: AppColors.goldColor.withOpacity(0.1),
              child: productImage.isNotEmpty
                  ? Image.network(productImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag, color: AppColors.goldColor, size: 22))
                  : const Icon(Icons.shopping_bag, color: AppColors.goldColor, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
                const SizedBox(height: 2),
                Text('\u00A3$productPrice',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.goldColor)),
              ],
            ),
          ),
          // Add to cart button
          GestureDetector(
            onTap: () => _addStreamProductToCart(stream),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.goldColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_shopping_cart, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Add to Cart',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Add the featured product from a livestream stream to the cart.
  void _addStreamProductToCart(Map<String, dynamic> stream) {
    final productName = stream['product_name']?.toString();
    final productPrice = stream['product_price']?.toString() ?? '0';
    final productIdRaw = stream['product_id'];
    if (productName == null) return;

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
        SnackBar(
          content: Text('Could not add to cart. Try again.'),
          backgroundColor: AppColors.coralColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inkColor,
      body: SafeArea(
        child: Stack(
          children: [
            // PageView for swipeable streams
            PageView.builder(
              controller: _pageController,
              itemCount: widget.streams.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => _buildStreamPage(widget.streams[i], i),
            ),

            // Close button
            Positioned(
              top: 8, left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
              ),
            ),

            // Page indicator
            if (widget.streams.length > 1)
              Positioned(
                top: 16, right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.streams.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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
