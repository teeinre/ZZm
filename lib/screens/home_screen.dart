import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../providers/products_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/cart_provider.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/product_tile.dart';
import '../widgets/brand_logo.dart';
import 'main_screen.dart';
import 'product_detail_screen.dart';
import 'vendor_profile_screen.dart';
import 'livestream_viewer_screen.dart';
import 'all_livestreams_screen.dart';

typedef TabCallback = void Function(int index);

class HomeScreen extends StatefulWidget {
  final TabCallback? onTabSwitch;
  const HomeScreen({super.key, this.onTabSwitch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _activeCategoryId;
  String _activeCategoryName = 'All';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  int _unreadNotifications = 0;
  final ScrollController _scrollController = ScrollController();
  bool _hasLoaded = false;

  // Live streams state
  List<Map<String, dynamic>> _liveStreams = [];
  bool _isLoadingStreams = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialData();
      });
    }
  }

  void _loadInitialData() {
    try {
      final provider = context.read<ProductsProvider>();
      provider.loadCategories();
      if (!provider.initialized || provider.products.isEmpty) {
        provider.loadProducts(refresh: true);
      }
      _loadLiveStreams();
      _hasLoaded = true;
    } catch (_) {
      _hasLoaded = true;
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<ProductsProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.goldColor,
          onRefresh: () async {
            final provider = context.read<ProductsProvider>();
            await provider.loadProducts(refresh: true);
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      _buildLiveStreamSection(),
                      const SizedBox(height: 20),
                      _buildHeroBanner(),
                      const SizedBox(height: 16),
                      _buildEventsBanner(),
                      const SizedBox(height: 20),
                      _buildCategories(),
                      const SizedBox(height: 24),
                      _buildVendorSpotlight(),
                      const SizedBox(height: 24),
                      _buildTrendingSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final displayName = auth.isAuthenticated && auth.user != null
            ? (auth.user!.username ?? (auth.user!.fullName.isNotEmpty ? auth.user!.fullName : 'Guest'))
            : 'Guest';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const BrandLogo(height: 32),
                GestureDetector(
                  onTap: () => _showNotificationsPanel(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.indigoPaleColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_outlined, color: AppColors.indigoColor, size: 20),
                      ),
                      if (_unreadNotifications > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(color: AppColors.coralColor, shape: BoxShape.circle),
                            child: Center(
                              child: Text('$_unreadNotifications',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // _buildLocationPicker(), // Location picker commented out for now
            const SizedBox(height: 8),
            Text(
              auth.isAuthenticated ? 'Welcome back, $displayName' : 'Welcome to ZZmore.store',
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationPicker() {
    return Consumer<LocationProvider>(
      builder: (context, locationProvider, child) {
        return GestureDetector(
          onTap: () => _showLocationPicker(locationProvider),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.sandColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, color: AppColors.goldColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  locationProvider.displayLocation,
                  style: const TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: AppColors.inkSoftColor, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLocationPicker(LocationProvider locationProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Location',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
              const SizedBox(height: 16),
              ...locationProvider.availableLocations.map((loc) {
                final isSelected = loc['city'] == locationProvider.city &&
                    loc['country'] == locationProvider.country;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.location_on : Icons.location_on_outlined,
                    color: isSelected ? AppColors.goldColor : AppColors.inkSoftColor,
                  ),
                  title: Text(
                    '${loc['city']}, ${loc['country']}',
                    style: TextStyle(
                      color: isSelected ? AppColors.goldColor : AppColors.inkColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    locationProvider.setLocation(loc['city']!, loc['country']!);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () {
        MainScreen.innerNavigatorOf(context, 0)?.push(
          MaterialPageRoute(
            builder: (_) => SearchResultsPage(query: _searchController.text.trim()),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.inkSoftColor),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                enabled: false,
                onChanged: (value) {
                  setState(() => _isSearching = value.isNotEmpty);
                },
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    context.read<ProductsProvider>().setSearchQuery(value.trim());
                    MainScreen.innerNavigatorOf(context, 0)?.push(
                      MaterialPageRoute(
                        builder: (_) => SearchResultsPage(query: value.trim()),
                      ),
                    );
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Search vendors, beauty, fashion...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                ),
                style: const TextStyle(color: AppColors.inkColor, fontSize: 13),
              ),
            ),
            if (_isSearching)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _isSearching = false);
                  context.read<ProductsProvider>().setSearchQuery(null);
                },
                child: const Icon(Icons.close, color: AppColors.inkSoftColor, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.indigoColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.stars_outlined, color: AppColors.goldColor, size: 16),
              SizedBox(width: 6),
              Flexible(
                child: Text('CURATED WITH PRIDE',
                    style: TextStyle(color: AppColors.goldColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Get Authentic African Products, Events & Services',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, fontFamily: 'Fraunces'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => widget.onTabSwitch?.call(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Discover vendors', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Events Banner ───
  Widget _buildEventsBanner() {
    return GestureDetector(
      onTap: () {
        // Launch events page in external browser
        _launchUrl('https://zzmore.store/zzmore-events/');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.goldColor, Color(0xFFE67E14), AppColors.coralColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.goldColor.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon decoration
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.event, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('EVENTS & EXPERIENCES',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                  ),
                  const SizedBox(height: 8),
                  const Text('Discover & Book Events',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: Colors.white, fontFamily: 'Fraunces',
                    )),
                  const SizedBox(height: 3),
                  const Text('Cultural shows, workshops, meetups & more',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            // Arrow CTA
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_forward_rounded, color: AppColors.coralColor, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Fallback silently if url_launcher not available or fails
    }
  }

  // ─── Live Stream Section ───
  Future<void> _loadLiveStreams() async {
    if (_isLoadingStreams) return;
    setState(() => _isLoadingStreams = true);
    try {
      final api = ApiService();
      final streams = await api.getPublicLivestreams();
      if (mounted) {
        setState(() {
          _liveStreams = streams;
          _isLoadingStreams = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liveStreams = [];
          _isLoadingStreams = false;
        });
      }
    }
  }

  Widget _buildLiveStreamSection() {
    if (_isLoadingStreams) {
      return _buildStreamsLoadingShimmer();
    }

    if (_liveStreams.isEmpty && !_isLoadingStreams) {
      return _buildComingSoonCard();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveSectionHeader(),
        const SizedBox(height: 10),
        SizedBox(
          height: 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 20),
            itemCount: _liveStreams.length + 1, // +1 for "Go Live" CTA
            itemBuilder: (context, index) {
              if (index < _liveStreams.length) {
                return _buildLiveStreamCard(_liveStreams[index], index);
              }
              return _buildGoLiveCTA();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStreamsLoadingShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveSectionHeader(),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 20),
            itemCount: 3,
            itemBuilder: (context, index) => Shimmer.fromColors(
              baseColor: AppColors.blackPaleColor,
              highlightColor: AppColors.creamColor,
              child: Container(
                width: 170,
                margin: EdgeInsets.only(right: 12, left: index == 0 ? 0 : 0),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity, height: 100,
                      decoration: const BoxDecoration(
                        color: AppColors.whiteColor,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 120, height: 14, color: AppColors.whiteColor),
                          const SizedBox(height: 6),
                          Container(width: 80, height: 10, color: AppColors.whiteColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComingSoonCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.coralColor.withOpacity(0.12), AppColors.goldColor.withOpacity(0.12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coralColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.coralColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.live_tv, color: AppColors.coralColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('LIVE SHOPPING',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.coralColor, letterSpacing: 1.5)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.coralColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('COMIING SOON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Watch vendors showcase their products in real-time.',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => widget.onTabSwitch?.call(3), // Navigate to profile
            icon: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.goldColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, color: AppColors.goldColor, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('LIVE NOW',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.inkColor, letterSpacing: 1.2)),
          ],
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AllLivestreamsScreen(),
            ));
          },
          child: const Text('See all', style: TextStyle(color: AppColors.goldColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildLiveStreamCard(Map<String, dynamic> stream, int index) {
    final title = stream['title']?.toString() ?? 'Live Stream';
    final vendorName = stream['vendor_name']?.toString() ?? stream['store_name']?.toString() ?? 'Vendor';
    final vendorAvatar = stream['vendor_avatar']?.toString() ?? stream['store_avatar']?.toString() ?? '';
    final thumbnail = stream['thumbnail']?.toString() ?? '';
    final viewerCount = stream['viewers']?.toString() ?? '0';
    final platform = stream['platform']?.toString()?.toLowerCase() ?? '';

    IconData platformIcon;
    switch (platform) {
      case 'youtube': platformIcon = Icons.play_circle_outline; break;
      case 'facebook': platformIcon = Icons.facebook; break;
      case 'tiktok': platformIcon = Icons.music_note; break;
      case 'instagram': platformIcon = Icons.camera_alt_outlined; break;
      default: platformIcon = Icons.live_tv;
    }

    return GestureDetector(
      onTap: () {
        // Include ALL streams (not just live) so recorded/past videos still play.
        final activeStreams = List<Map<String, dynamic>>.from(_liveStreams);
        final idx = activeStreams.indexWhere((s) => s['id'] == stream['id']);
        if (idx >= 0) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => LivestreamViewerScreen(
              streams: activeStreams,
              initialIndex: idx,
            ),
          ));
        }
      },
      child: Container(
      width: 170,
      margin: EdgeInsets.only(right: 12, left: index == 0 ? 0 : 0),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail area
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  width: double.infinity,
                  height: 100,
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
                          loadingBuilder: (_, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.indigoColor, AppColors.indigoColor.withOpacity(0.7), AppColors.coralColor.withOpacity(0.5)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldColor),
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(platformIcon, color: Colors.white.withOpacity(0.3), size: 40),
                        ),
                ),
              ),
              // LIVE badge
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 8, spreadRadius: -2),
                    ],
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
              // Viewer count
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
          // Stream info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.indigoColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          vendorName.isNotEmpty ? vendorName[0].toUpperCase() : 'V',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.indigoColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(vendorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
                    ),
                  ],
                ),
                // Product info section
                Builder(
                  builder: (ctx) {
                    final productName = stream['product_name']?.toString();
                    final productPrice = stream['product_price']?.toString();
                    final productId = stream['product_id'];
                    if (productName == null || productPrice == null) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('\u00A3$productPrice',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
                              GestureDetector(
                                onTap: () => _addLivestreamProductToCart(ctx, stream),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.goldColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.add_shopping_cart, color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.whiteColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildGoLiveCTA() {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.goldColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.goldColor.withOpacity(0.3), width: 1.5),
      ),
      child: InkWell(
        onTap: () => widget.onTabSwitch?.call(3),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.goldColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.live_tv, color: AppColors.goldColor, size: 24),
            ),
            const SizedBox(height: 10),
            const Text('Go Live',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
            const SizedBox(height: 4),
            const Text('Stream your products',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoftColor),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Consumer<ProductsProvider>(
      builder: (context, provider, child) {
        final categories = provider.categories;
        if (categories.isEmpty) {
          return const SizedBox(height: 72);
        }
        return SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            padding: EdgeInsets.zero,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isActive = category.id.toString() == _activeCategoryId;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _activeCategoryId = category.id.toString();
                    _activeCategoryName = category.name!;
                  });
                  provider.setCategory(category.id.toString());
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.indigoColor : AppColors.whiteColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Icon(
                            isActive ? Icons.shopping_bag : Icons.shopping_bag_outlined,
                            color: isActive ? AppColors.goldColor : AppColors.indigoLightColor,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        category.name ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isActive ? AppColors.inkColor : AppColors.inkSoftColor,
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVendorSpotlight() {
    return Consumer<ProductsProvider>(
      builder: (context, provider, child) {
        final products = provider.products;
        if (products.isEmpty) return const SizedBox.shrink();

        final seenVendors = <int>{};
        final spotlightProducts = products.where((p) {
          final vendorName = (p.vendorName ?? '').trim().toLowerCase();
          if (vendorName == 'zzmore open market') return false;
          if (p.isBookable) return false; // services/bookings are not spotlight products
          if (p.vendorId != null && !seenVendors.contains(p.vendorId)) {
            seenVendors.add(p.vendorId!);
            return true;
          }
          return false;
        }).take(3).toList();

        if (spotlightProducts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Vendor spotlight',
                    style: TextStyle(color: AppColors.inkColor, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
                GestureDetector(
                  onTap: () => widget.onTabSwitch?.call(1),
                  child: const Text('View all', style: TextStyle(color: AppColors.indigoLightColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...spotlightProducts.map((product) => _buildVendorCard(product)),
          ],
        );
      },
    );
  }

  Widget _buildVendorCard(Product product) {
    final vendorName = product.vendorName ?? 'Unknown Vendor';
    final firstImage = product.images.isNotEmpty ? product.images.first : null;
    return GestureDetector(
      onTap: () => _showProductDetail(product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: firstImage != null
                    ? Image.network(firstImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(
                        color: AppColors.goldColor.withOpacity(0.15),
                        child: const Icon(Icons.store, color: AppColors.goldColor, size: 28),
                      ))
                    : Container(
                        color: AppColors.goldColor.withOpacity(0.15),
                        child: const Icon(Icons.store, color: AppColors.goldColor, size: 28),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(vendorName,
                            style: const TextStyle(color: AppColors.inkColor, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_user, color: AppColors.indigoColor, size: 14),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(product.name,
                      style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.indigoPaleColor, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: AppColors.goldColor, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    (product.rating ?? 0).toStringAsFixed(1),
                    style: const TextStyle(color: AppColors.indigoColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _addSpotlightToCart(product),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.goldColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSpotlightToCart(Product product) async {
    final cart = context.read<CartProvider>();
    try {
      await cart.addToCart(product);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} added to cart'),
          backgroundColor: AppColors.goldColor,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add: $e'),
          backgroundColor: AppColors.coralColor,
        ),
      );
    }
  }

  /// Add the featured product from a livestream card to the cart.
  void _addLivestreamProductToCart(BuildContext cardContext, Map<String, dynamic> stream) async {
    final vendorName = stream['vendor_name']?.toString() ?? stream['store_name']?.toString() ?? '';
    if (ApiConstants.isVendorExcluded(name: vendorName)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This product is not available.')),
        );
      }
      return;
    }

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
      vendorName: vendorName,
      vendorId: 0,
    );

    final cart = context.read<CartProvider>();
    try {
      await cart.addToCart(product);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$productName added to cart'),
          backgroundColor: AppColors.goldColor,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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

  void _retryLoadProducts(ProductsProvider provider) {
    try {
      provider.loadProducts(refresh: true);
    } catch (_) {}
  }

  Widget _buildTrendingSection() {
    return Consumer<ProductsProvider>(
      builder: (context, provider, child) {
        final products = provider.products;
        final isLoading = provider.isLoading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trending in $_activeCategoryName',
                style: const TextStyle(color: AppColors.inkColor, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            if (isLoading && products.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.goldColor),
                ),
              )
            else if (products.isEmpty && _hasLoaded) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('No products found', style: TextStyle(color: AppColors.inkSoftColor)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => _retryLoadProducts(provider),
                  child: const Text('Tap to retry', style: TextStyle(color: AppColors.goldColor, fontSize: 12)),
                ),
              ),
            ] else
              Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      return ProductTile(product: products[index]);
                    },
                  ),
                  if (provider.isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(color: AppColors.goldColor, strokeWidth: 2)),
                    )
                  else if (provider.hasMore && products.length >= 8)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: OutlinedButton(
                          onPressed: () => provider.loadMore(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.goldColor),
                            foregroundColor: AppColors.goldColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Load more products'),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  void _showProductDetail(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.inkSoftColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (product.images.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(product.images.first, height: 220, width: double.infinity, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 16),
                Text(product.name,
                    style: const TextStyle(color: AppColors.inkColor, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Fraunces')),
                if (product.vendorName != null) ...[
                  const SizedBox(height: 4),
                  Text('by ${product.vendorName}', style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('£${(double.tryParse(product.price) ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(color: AppColors.goldColor, fontSize: 24, fontWeight: FontWeight.bold)),
                    if (product.onSale) ...[
                      const SizedBox(width: 8),
                      Text('£${product.regularPrice}', style: const TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 16,
                        decoration: TextDecoration.lineThrough,
                      )),
                    ],
                  ],
                ),
                if (product.description != null && product.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(product.description!, style: const TextStyle(color: AppColors.inkColor, fontSize: 14)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _addToCart(ctx, product);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Add to Basket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _addToCart(BuildContext ctx, Product product) {
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to basket'),
        backgroundColor: AppColors.goldColor,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => widget.onTabSwitch?.call(2),
        ),
      ),
    );
  }

  void _showNotificationsPanel() {
    final authProvider = context.read<AuthProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
              const SizedBox(height: 16),
              if (authProvider.isAuthenticated && authProvider.user != null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: Future.delayed(const Duration(milliseconds: 500), () => _getDynamicNotifications(authProvider)),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: AppColors.goldColor, strokeWidth: 2),
                      ));
                    }
                    final notifications = snapshot.data ?? [];
                    if (notifications.isEmpty) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No notifications yet', style: TextStyle(color: AppColors.inkSoftColor)),
                      ));
                    }
                    return Column(
                      children: notifications.map((n) =>
                        _buildNotificationItem(
                          n['message'] ?? '',
                          n['time'] ?? '',
                          n['isUnread'] == true,
                        ),
                      ).toList(),
                    );
                  },
                )
              else
                Column(
                  children: [
                    _buildNotificationItem('No notifications yet.', 'Just now', false),
                  ],
                ),
              const SizedBox(height: 16),
              if (_unreadNotifications > 0)
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _unreadNotifications = 0);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Mark all as read', style: TextStyle(color: AppColors.goldColor)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getDynamicNotifications(AuthProvider auth) async {
    final notifs = <Map<String, dynamic>>[];
    try {
      // Fetch recent orders to generate notifications
      if (auth.user != null) {
        final orders = await context.read<ProductsProvider>().apiService.getUserOrders(auth.user!.id);
        for (final order in orders) {
          final status = order['status']?.toString() ?? 'placed';
          final date = order['date_created']?.toString() ?? '';
          final orderNum = order['number']?.toString() ?? order['id']?.toString() ?? '';
          notifs.add({
            'message': 'Your order #$orderNum has been $status',
            'time': _formatDate(date),
            'isUnread': true,
          });
        }
      }
    } catch (_) {}

    // Always include some fresh dynamic content
    if (notifs.isEmpty) {
      notifs.addAll([
        {'message': 'Welcome to ZZmore.store!', 'time': 'Just now', 'isUnread': true},
      ]);
    }

    return notifs;
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildNotificationItem(String message, String time, bool isUnread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnread ? AppColors.goldColor.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: BoxDecoration(
              color: isUnread ? AppColors.goldColor : AppColors.inkSoftColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(fontSize: 13, color: AppColors.inkColor, fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal)),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pulsing Dot (LIVE indicator) ───
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class SearchResultsPage extends StatefulWidget {
  final String query;
  const SearchResultsPage({super.key, required this.query});

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _api = ApiService();
  List<Product> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.query;
    if (widget.query.isNotEmpty) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      final results = await _api.getProducts(search: query, perPage: 50);
      // Filter out excluded vendor products from search results
      final filtered = results.where((p) =>
          !ApiConstants.isVendorExcluded(id: p.vendorId, name: p.vendorName)).toList();
      if (mounted) {
        setState(() {
          _results = filtered;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorMessage = 'Search failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.creamColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onSubmitted: (_) => _performSearch(),
          decoration: const InputDecoration(
            hintText: 'Search vendors, beauty, fashion...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: AppColors.inkSoftColor, fontSize: 16),
          ),
          style: const TextStyle(color: AppColors.inkColor, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.goldColor),
            onPressed: _performSearch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.goldColor),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: AppColors.inkSoftColor)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.coralColor, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.inkSoftColor)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return const Center(
        child: Text(
          'Type to search for products',
          style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, color: AppColors.inkSoftColor, size: 48),
              const SizedBox(height: 16),
              const Text(
                'No results found',
                style: TextStyle(color: AppColors.inkColor, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Fraunces'),
              ),
              const SizedBox(height: 8),
              Text(
                'No products match "${_searchController.text.trim()}"',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Try different keywords or browse categories.',
                style: TextStyle(color: AppColors.inkSoftColor.withOpacity(0.7), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            '${_results.length} result${_results.length == 1 ? '' : 's'} for "${_searchController.text.trim()}"',
            style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              return ProductTile(product: _results[index]);
            },
          ),
        ),
      ],
    );
  }
}
