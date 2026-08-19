import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/currency_provider.dart';
import 'vendor_products_screen.dart';
import 'vendor_orders_screen.dart';
import 'vendor_coupons_screen.dart';
import 'vendor_reviews_screen.dart';
import 'vendor_withdrawals_screen.dart';
import 'vendor_store_settings_screen.dart';
import 'vendor_sales_report_screen.dart';
import 'vendor_quote_credit_screen.dart';
import 'vendor_livestream_screen.dart';
import 'vendor_shipping_screen.dart';
import 'vendor_refunds_screen.dart';
import 'vendor_verification_screen.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDashboard());
  }

  Future<void> _initDashboard() async {
    final auth = context.read<AuthProvider>();
    final vendor = context.read<VendorProvider>();

    // Inject WordPress user ID from JWT — critical for reliable
    // product/order filtering via the post_author WC API parameter.
    if (auth.user != null) {
      vendor.setWordPressUserId(auth.user!.id);
    }

    // ── STEP 1: Resolve vendor store info ──
    if (auth.user != null && auth.user!.id > 0) {
      int? resolvedStoreId = auth.user!.vendorStoreId;

      // If vendorStoreId not persisted from login, try to find it live
      if (resolvedStoreId == null || resolvedStoreId <= 0) {
        try {
          final store = await vendor.apiService.getVendorStoreByUserId(auth.user!.id);
          if (store != null && store['id'] != null) {
            resolvedStoreId = store['id'] is int
                ? store['id'] as int
                : int.tryParse(store['id']?.toString() ?? '');
          }
        } catch (_) {
          // Last resort: try loading store by user ID directly
          try {
            await vendor.loadStoreInfo(auth.user!.id);
            resolvedStoreId = vendor.vendorId;
          } catch (_) {}
        }
      }

      if (resolvedStoreId != null && resolvedStoreId > 0) {
        // 1) Restore cached dashboard instantly -- no network, no spinner
        final hadCached = vendor.restoreFromCache(vendorId: resolvedStoreId);
        if (hadCached) {
          debugPrint('Vendor dashboard restored from Hive cache for vendor $resolvedStoreId');
        }
        // 2) Then load fresh store info (network � updates cached data in background)
        await vendor.loadStoreInfo(resolvedStoreId);
      }
    }

    if (!mounted) return;

    // ── STEP 2: Load all vendor data in parallel ──
    if (vendor.storeInfo != null) {
      debugPrint('Using cached dashboard data while refreshing...');
    }
    final vid = vendor.vendorId;
    final futures = <Future<void>>[
      vendor.loadDashboard(),           // stats, balance, announcements
      vendor.loadOrders(),
      vendor.loadCoupons(),
      vendor.loadReviews(),
      vendor.loadWithdrawals(),
    ];
    // Only load products if we have a valid vendor ID
    if (vid != null && vid > 0) {
      futures.add(vendor.loadVendorProducts(vendorId: vid));
    }
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isVendor) {
      return Scaffold(
        backgroundColor: AppColors.creamColor,
        appBar: AppBar(
          backgroundColor: AppColors.indigoDeepColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.whiteColor),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Vendor Dashboard',
              style: TextStyle(
                  color: AppColors.whiteColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 64, color: AppColors.coralColor),
                const SizedBox(height: 16),
                const Text(
                  'Access Denied',
                  style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Fraunces',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You are not a vendor. Only vendor accounts should have access to the vendor dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Consumer<VendorProvider>(
      builder: (context, vendor, _) {
        return Scaffold(
          backgroundColor: AppColors.creamColor,
          appBar: AppBar(
            backgroundColor: AppColors.indigoDeepColor,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.goldColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store, color: AppColors.goldColor, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Vendor Dashboard',
                    style: TextStyle(
                        color: AppColors.whiteColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Fraunces')),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.whiteColor),
                onPressed: () {},
              ),
            ],
          ),
          body: vendor.isLoadingStats || vendor.isLoadingStore || vendor.isLoadingOrders || vendor.isLoadingProducts
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.goldColor))
              : vendor.dashboardError != null && !vendor.hasStoreInfo
                  ? _buildErrorView(vendor)
                  : RefreshIndicator(
                  color: AppColors.goldColor,
                  onRefresh: () => vendor.loadDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeBanner(vendor),
                        const SizedBox(height: 20),
                        _buildStatCards(vendor),
                        const SizedBox(height: 20),
                        _buildQuickActions(),
                        const SizedBox(height: 20),
                        _buildInventorySummary(vendor),
                        const SizedBox(height: 20),
                        _buildEngagementStats(vendor),
                        const SizedBox(height: 20),
                        _buildPerformanceReport(vendor),
                        const SizedBox(height: 20),
                        _buildAnnouncements(vendor),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildErrorView(VendorProvider vendor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.inkSoftColor),
            const SizedBox(height: 16),
            Text(
              vendor.dashboardError ?? 'Unable to load dashboard data.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initDashboard,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldColor,
                foregroundColor: AppColors.whiteColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner(VendorProvider vendor) {
    final storeName = vendor.storeInfo?['store_name']?.toString() ?? 'Your Store';
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.indigoColor, AppColors.indigoDeepColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back,',
                        style: TextStyle(
                            color: AppColors.whiteColor.withOpacity(0.8),
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(storeName,
                        style: const TextStyle(
                            color: AppColors.whiteColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Fraunces')),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.goldColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.goldColor.withOpacity(0.5), width: 2),
                ),
                child: const Icon(Icons.store_mall_directory,
                    color: AppColors.goldColor, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.goldColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.trending_up, color: AppColors.goldColor, size: 14),
                const SizedBox(width: 6),
                Text(
                    'Earnings: ${vendor.totalEarnings > 0 ? '$currency${vendor.totalEarnings.toStringAsFixed(2)}' : 'No data yet'}',
                    style: const TextStyle(
                        color: AppColors.goldColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(VendorProvider vendor) {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    final stats = [
      {
        'icon': Icons.shopping_cart_outlined,
        'label': 'Total Orders',
        'value': '${vendor.totalOrders}',
        'color': AppColors.indigoColor,
      },
      {
        'icon': Icons.monetization_on_outlined,
        'label': 'Total Sales',
        'value': '$currency${vendor.totalSales.toStringAsFixed(2)}',
        'color': AppColors.goldColor,
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Products',
        'value': '${vendor.totalProducts}',
        'color': const Color(0xFF10B981),
      },
      {
        'icon': Icons.pending_outlined,
        'label': 'Pending',
        'value': '${vendor.pendingOrders}',
        'color': AppColors.coralColor,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final s = stats[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (s['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(s['icon'] as IconData,
                    color: s['color'] as Color, size: 18),
              ),
              const Spacer(),
              Text(s['value'] as String,
                  style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Fraunces')),
              Text(s['label'] as String,
                  style: const TextStyle(
                      color: AppColors.inkSoftColor, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.inventory_2, 'label': 'Products', 'color': AppColors.indigoColor, 'route': 'products'},
      {'icon': Icons.receipt_long, 'label': 'Orders', 'color': const Color(0xFF10B981), 'route': 'orders'},
      {'icon': Icons.local_shipping, 'label': 'Shipping', 'color': const Color(0xFF06B6D4), 'route': 'shipping'},
      {'icon': Icons.discount, 'label': 'Coupons', 'color': AppColors.goldColor, 'route': 'coupons'},
      {'icon': Icons.reviews, 'label': 'Reviews', 'color': const Color(0xFF8B5CF6), 'route': 'reviews'},
      {'icon': Icons.request_quote, 'label': 'RFQ', 'color': AppColors.coralColor, 'route': 'quote'},
      {'icon': Icons.live_tv, 'label': 'Live', 'color': const Color(0xFFEF4444), 'route': 'livestream'},
      {'icon': Icons.assignment_return, 'label': 'Refunds', 'color': const Color(0xFFF97316), 'route': 'refunds'},
      {'icon': Icons.account_balance_wallet, 'label': 'Withdraw', 'color': AppColors.coralColor, 'route': 'withdrawals'},
      {'icon': Icons.settings, 'label': 'Settings', 'color': AppColors.inkSoftColor, 'route': 'settings'},
      {'icon': Icons.bar_chart, 'label': 'Reports', 'color': const Color(0xFF3B82F6), 'route': 'reports'},
      {'icon': Icons.verified_user, 'label': 'Verified', 'color': const Color(0xFF10B981), 'route': 'verification'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final a = actions[index];
            return GestureDetector(
              onTap: () => _onQuickAction(a['route'] as String),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (a['color'] as Color).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(a['icon'] as IconData,
                          color: a['color'] as Color, size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(a['label'] as String,
                        style: const TextStyle(
                            color: AppColors.inkColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _onQuickAction(String route) {
    Widget? screen;
    switch (route) {
      case 'products':
        screen = const VendorProductsScreen();
        break;
      case 'orders':
        screen = const VendorOrdersScreen();
        break;
      case 'coupons':
        screen = const VendorCouponsScreen();
        break;
      case 'reviews':
        screen = const VendorReviewsScreen();
        break;
      case 'withdrawals':
        screen = const VendorWithdrawalsScreen();
        break;
      case 'settings':
        screen = const VendorStoreSettingsScreen();
        break;
      case 'reports':
        screen = const VendorSalesReportScreen();
        break;
      case 'quote':
        screen = const VendorQuoteCreditScreen();
        break;
      case 'livestream':
        screen = const VendorLivestreamScreen();
        break;
      case 'shipping':
        screen = const VendorShippingScreen();
        break;
      case 'refunds':
        screen = const VendorRefundsScreen();
        break;
      case 'verification':
        screen = const VendorVerificationScreen();
        break;
      case 'announcements':
        // Announcements are shown inline on dashboard
        break;
    }
    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    }
  }

  Widget _buildInventorySummary(VendorProvider vendor) {
    final total = vendor.totalProducts;
    final inStock = vendor.inStockProducts;
    final oos = vendor.outOfStockProducts;
    final low = vendor.lowStockProducts;
    final currency = context.watch<CurrencyProvider>().currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Inventory Levels',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _inventoryPill(
                    'Total',
                    '$total',
                    color: AppColors.indigoColor,
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(width: 10),
                  _inventoryPill(
                    'In stock',
                    '$inStock',
                    color: const Color(0xFF10B981),
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _inventoryPill(
                    'Low stock',
                    '$low',
                    color: AppColors.goldColor,
                    icon: Icons.warning_amber_outlined,
                  ),
                  const SizedBox(width: 10),
                  _inventoryPill(
                    'Out of stock',
                    '$oos',
                    color: AppColors.coralColor,
                    icon: Icons.remove_circle_outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inventoryPill(String label, String value,
      {required Color color, required IconData icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 1),
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementStats(VendorProvider vendor) {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Customer Engagement',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.goldColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.star_rate_rounded,
                              color: AppColors.goldColor, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text('${vendor.averageRating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Fraunces')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Average rating',
                        style: TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.rate_review_outlined,
                              color: Color(0xFF8B5CF6), size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text('${vendor.reviewCount}',
                            style: const TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Fraunces')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Reviews',
                        style: TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.account_circle_outlined,
                              color: Color(0xFF06B6D4), size: 16),
                        ),
                        const SizedBox(width: 8),
                        Text('${vendor.completedOrders}',
                            style: const TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Fraunces')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Completed orders',
                        style: TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceReport(VendorProvider vendor) {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    final rate = vendor.completedOrderRate;
    final aov = vendor.averageOrderValue;
    final withdrawn = vendor.withdrawnTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance Report',
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
              _perfRow('Fulfillment rate', '${(rate * 100).toStringAsFixed(0)}%',
                  rate >= 0.9
                      ? const Color(0xFF10B981)
                      : rate >= 0.7
                          ? AppColors.goldColor
                          : AppColors.coralColor,
                  Icons.track_changes_outlined),
              const Divider(height: 22),
              _perfRow('Average order value',
                  '$currency${aov.toStringAsFixed(2)}', AppColors.indigoColor,
                  Icons.payments_outlined),
              const Divider(height: 22),
              _perfRow(
                  'Pending orders',
                  '${vendor.pendingOrders}',
                  vendor.pendingOrders > 0
                      ? AppColors.coralColor
                      : const Color(0xFF10B981),
                  Icons.pending_outlined),
              const Divider(height: 22),
              _perfRow('Total withdrawn',
                  '$currency${withdrawn.toStringAsFixed(2)}', AppColors.inkSoftColor,
                  Icons.account_balance_wallet_outlined),
            ],
          ),
        ),
      ],
    );
  }

  Widget _perfRow(String label, String value, Color accent, IconData icon) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 12),
        Text(label,
            style:
                const TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Fraunces')),
      ],
    );
  }

  Widget _buildAnnouncements(VendorProvider vendor) {
    final items = vendor.announcements;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Announcements',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 12),
        ...items.take(3).map((a) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.goldColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.goldColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: AppColors.goldColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['title']?.toString() ?? 'Announcement',
                            style: const TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (a['content'] != null) ...[
                          const SizedBox(height: 4),
                          Text(a['content'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.inkSoftColor,
                                  fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
