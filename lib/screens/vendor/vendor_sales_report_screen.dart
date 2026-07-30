import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

class VendorSalesReportScreen extends StatefulWidget {
  const VendorSalesReportScreen({super.key});

  @override
  State<VendorSalesReportScreen> createState() => _VendorSalesReportScreenState();
}

class _VendorSalesReportScreenState extends State<VendorSalesReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String _period = '7days';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadDashboardStats();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
        title: const Text('Sales Reports',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          return Column(
            children: [
              // Period selector
              Container(
                color: AppColors.whiteColor,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: ['today', '7days', '30days', 'year'].map((p) {
                    final isActive = _period == p;
                    String label;
                    switch (p) {
                      case 'today':
                        label = 'Today';
                        break;
                      case '7days':
                        label = '7 Days';
                        break;
                      case '30days':
                        label = '30 Days';
                        break;
                      default:
                        label = 'Year';
                    }
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _period = p),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.goldColor
                                : AppColors.creamColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  color: isActive
                                      ? AppColors.whiteColor
                                      : AppColors.inkSoftColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Tabs
              Container(
                color: AppColors.whiteColor,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: AppColors.goldColor,
                  unselectedLabelColor: AppColors.inkSoftColor,
                  indicatorColor: AppColors.goldColor,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Orders'),
                    Tab(text: 'Products'),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildOverviewTab(vendor),
                    _buildOrdersTab(vendor),
                    _buildProductsTab(vendor),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverviewTab(VendorProvider vendor) {
    final stats = vendor.dashboardStats;
    final items = [
      {'label': 'Total Sales', 'value': '\u00A3${vendor.totalSales.toStringAsFixed(2)}', 'icon': Icons.monetization_on, 'color': AppColors.goldColor},
      {'label': 'Total Earnings', 'value': '\u00A3${vendor.totalEarnings.toStringAsFixed(2)}', 'icon': Icons.savings, 'color': const Color(0xFF10B981)},
      {'label': 'Total Orders', 'value': '${vendor.totalOrders}', 'icon': Icons.receipt_long, 'color': AppColors.indigoColor},
      {'label': 'Pending Orders', 'value': '${vendor.pendingOrders}', 'icon': Icons.pending_outlined, 'color': AppColors.coralColor},
      {'label': 'Completed', 'value': '${vendor.completedOrders}', 'icon': Icons.check_circle_outline, 'color': const Color(0xFF10B981)},
      {'label': 'Page Views', 'value': stats['total_pageviews']?.toString() ?? '-', 'icon': Icons.visibility_outlined, 'color': const Color(0xFF8B5CF6)},
      {'label': 'Products', 'value': stats['total_products']?.toString() ?? '-', 'icon': Icons.inventory_2, 'color': const Color(0xFF3B82F6)},
      {'label': 'Withdrawals', 'value': '\u00A3${(vendor.balance['total_withdrawn'] ?? 0).toString()}', 'icon': Icons.account_balance_wallet, 'color': const Color(0xFFF59E0B)},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Sales trend chart
          Container(
            width: double.infinity,
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sales Trend',
                    style: TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Expanded(
                  child: CustomPaint(
                    painter: _SalesChartPainter(),
                    size: Size.infinite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stats grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item['icon'] as IconData,
                          color: item['color'] as Color, size: 16),
                    ),
                    const Spacer(),
                    Text(item['value'] as String,
                        style: const TextStyle(
                            color: AppColors.inkColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Fraunces')),
                    Text(item['label'] as String,
                        style: const TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 10)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(VendorProvider vendor) {
    final orders = vendor.orders;
    if (orders.isEmpty) {
      return const Center(
        child: Text('No order data available',
            style: TextStyle(color: AppColors.inkSoftColor)));
    }

    // Aggregate by status
    final Map<String, int> statusCounts = {};
    double totalRevenue = 0;
    for (final o in orders) {
      final status = o['status']?.toString() ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      totalRevenue += double.tryParse(o['total']?.toString() ?? '0') ?? 0;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('Revenue',
                    style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                const SizedBox(height: 4),
                Text('\u00A3${totalRevenue.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Fraunces')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Orders by Status',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 12),
          ...statusCounts.entries.map((e) {
            final percent = orders.isEmpty ? 0.0 : e.value / orders.length;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key[0].toUpperCase() + e.key.substring(1),
                          style: const TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text('${e.value} (${(percent * 100).toStringAsFixed(1)}%)',
                          style: const TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: AppColors.indigoPaleColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.goldColor),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProductsTab(VendorProvider vendor) {
    final products = vendor.vendorProducts;
    if (products.isEmpty) {
      return const Center(
        child: Text('No product data available',
            style: TextStyle(color: AppColors.inkSoftColor)));
    }

    final inStock = products.where((p) =>
        p['stock_status']?.toString() == 'instock').length;
    final outOfStock = products.where((p) =>
        p['stock_status']?.toString() == 'outofstock').length;
    final published = products.where((p) =>
        p['status']?.toString() == 'publish').length;
    final drafts = products.length - published;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product stats cards
          Row(
            children: [
              _productStatCard('Total', '${products.length}', AppColors.indigoColor),
              const SizedBox(width: 10),
              _productStatCard('Published', '$published', const Color(0xFF10B981)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _productStatCard('In Stock', '$inStock', const Color(0xFF3B82F6)),
              const SizedBox(width: 10),
              _productStatCard('Out of Stock', '$outOfStock', AppColors.coralColor),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Stock Overview',
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
                _buildProgressIndicator(
                    'In Stock', inStock, products.length,
                    const Color(0xFF3B82F6)),
                const SizedBox(height: 12),
                _buildProgressIndicator(
                    'Out of Stock', outOfStock, products.length,
                    AppColors.coralColor),
                const SizedBox(height: 12),
                _buildProgressIndicator(
                    'Draft', drafts, products.length,
                    AppColors.inkSoftColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppColors.inkSoftColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(String label, int count, int total, Color color) {
    final percent = total == 0 ? 0.0 : count / total;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            Text('$count (${(percent * 100).toStringAsFixed(1)}%)',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: AppColors.indigoPaleColor,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _SalesChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.goldColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.goldColor.withOpacity(0.3),
          AppColors.goldColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final points = [0.4, 0.3, 0.6, 0.5, 0.45, 0.7, 0.55, 0.6, 0.8, 0.5, 0.65, 0.4];
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = points[i] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()
      ..color = AppColors.goldColor
      ..style = PaintingStyle.fill;
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = points[i] * size.height;
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
