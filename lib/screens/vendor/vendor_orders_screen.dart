import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

class VendorOrdersScreen extends StatefulWidget {
  const VendorOrdersScreen({super.key});

  @override
  State<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends State<VendorOrdersScreen> {
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadOrders();
    });
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF10B981);
      case 'processing':
        return AppColors.goldColor;
      case 'cancelled':
      case 'failed':
        return AppColors.coralColor;
      case 'pending':
        return AppColors.indigoLightColor;
      case 'on-hold':
        return const Color(0xFFF59E0B);
      case 'refunded':
        return AppColors.inkSoftColor;
      default:
        return AppColors.inkSoftColor;
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
        title: const Text('Orders',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          var orders = List<Map<String, dynamic>>.from(vendor.orders);

          if (_statusFilter != 'all') {
            orders = orders
                .where((o) => o['status']?.toString().toLowerCase() == _statusFilter)
                .toList();
          }

          return Column(
            children: [
              _buildStatusTabs(),
              Expanded(
                child: vendor.isLoadingOrders
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.goldColor))
                    : orders.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppColors.goldColor,
                            onRefresh: () => vendor.loadOrders(status: _statusFilter == 'all' ? null : _statusFilter),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: orders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildOrderCard(orders[index], vendor),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusTabs() {
    final statuses = ['all', 'pending', 'processing', 'completed', 'cancelled'];
    return Container(
      height: 44,
      color: AppColors.whiteColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: statuses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final s = statuses[index];
          final isActive = _statusFilter == s;
          return GestureDetector(
            onTap: () {
              setState(() => _statusFilter = s);
              context.read<VendorProvider>().loadOrders(
                  status: s == 'all' ? null : s);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? AppColors.goldColor : AppColors.creamColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(s[0].toUpperCase() + s.substring(1),
                  style: TextStyle(
                      color: isActive ? AppColors.whiteColor : AppColors.inkSoftColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, VendorProvider vendor) {
    final status = order['status']?.toString() ?? 'pending';
    final number = order['number']?.toString() ?? '#${order['id']}';
    final date = order['date_created']?.toString() ?? '';
    final formattedDate = date.length >= 10 ? date.substring(0, 10) : date;
    final total = order['total']?.toString() ?? '0';
    final billing = order['billing'] as Map<String, dynamic>? ?? {};
    final customerName = [
      billing['first_name']?.toString(),
      billing['last_name']?.toString(),
    ].where((e) => e != null && e.isNotEmpty).join(' ');
    final lineItems = order['line_items'] as List<dynamic>? ?? [];

    return GestureDetector(
      onTap: () => _openOrderDetail(order, vendor),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order $number',
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Fraunces')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: AppColors.inkSoftColor, size: 13),
                const SizedBox(width: 4),
                Text(formattedDate,
                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.person_outline,
                    color: AppColors.inkSoftColor, size: 13),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(customerName.isNotEmpty ? customerName : 'Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${lineItems.length} item${lineItems.length != 1 ? 's' : ''}  \u2022  Total: \u00A3${double.tryParse(total)?.toStringAsFixed(2) ?? total}',
                style: const TextStyle(
                    color: AppColors.goldColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No orders found',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Orders from your store will appear here',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        ],
      ),
    );
  }

  void _openOrderDetail(Map<String, dynamic> order, VendorProvider vendor) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => VendorOrderDetailScreen(order: order, vendor: vendor),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ORDER DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class VendorOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final VendorProvider vendor;

  const VendorOrderDetailScreen({
    super.key,
    required this.order,
    required this.vendor,
  });

  @override
  State<VendorOrderDetailScreen> createState() => _VendorOrderDetailScreenState();
}

class _VendorOrderDetailScreenState extends State<VendorOrderDetailScreen> {
  final _trackingCtrl = TextEditingController();
  bool _isUpdating = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.order['status']?.toString() ?? 'pending';
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return const Color(0xFF10B981);
      case 'processing': return AppColors.goldColor;
      case 'cancelled': case 'failed': return AppColors.coralColor;
      case 'pending': return AppColors.indigoLightColor;
      case 'on-hold': return const Color(0xFFF59E0B);
      default: return AppColors.inkSoftColor;
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    final orderId = widget.order['id'] as int;
    final ok = await widget.vendor.updateOrderStatus(orderId, newStatus);
    if (mounted) {
      setState(() {
        _isUpdating = false;
        if (ok) _currentStatus = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Status updated to $newStatus' : 'Failed to update status'),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
    }
  }

  Future<void> _addTracking() async {
    if (_trackingCtrl.text.trim().isEmpty) return;
    final orderId = widget.order['id'] as int;
    final api = widget.vendor.apiService;
    final ok = await api.addOrderNote(orderId,
        'Tracking number: ${_trackingCtrl.text.trim()}', customerNote: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Tracking added' : 'Failed to add tracking'),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
      if (ok) _trackingCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final number = order['number']?.toString() ?? '#${order['id']}';
    final date = order['date_created']?.toString() ?? '';
    final formattedDate = date.length >= 10 ? date.substring(0, 10) : date;
    final total = order['total']?.toString() ?? '0';
    final billing = order['billing'] as Map<String, dynamic>? ?? {};
    final shipping = order['shipping'] as Map<String, dynamic>? ?? {};
    final lineItems = order['line_items'] as List<dynamic>? ?? [];
    final paymentMethod = order['payment_method_title']?.toString() ?? '-';
    final shippingMethod = order['shipping_lines'] is List &&
            (order['shipping_lines'] as List).isNotEmpty
        ? (order['shipping_lines'] as List)[0]['method_title']?.toString() ?? '-'
        : '-';

    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Order $number',
            style: const TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor(_currentStatus).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _statusColor(_currentStatus).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _statusColor(_currentStatus).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.receipt_long,
                        color: _statusColor(_currentStatus), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order $number',
                            style: const TextStyle(
                                color: AppColors.inkColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Fraunces')),
                        Text(formattedDate,
                            style: const TextStyle(
                                color: AppColors.inkSoftColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor(_currentStatus),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_currentStatus.toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.whiteColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Update Status
            const Text('Update Status',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['pending', 'processing', 'completed', 'cancelled', 'on-hold', 'refunded'].map((s) {
                final isCurrent = _currentStatus == s;
                return GestureDetector(
                  onTap: isCurrent || _isUpdating
                      ? null
                      : () => _confirmStatusChange(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? _statusColor(s)
                          : _statusColor(s).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: isCurrent
                          ? null
                          : Border.all(color: _statusColor(s).withOpacity(0.3)),
                    ),
                    child: Text(s[0].toUpperCase() + s.substring(1),
                        style: TextStyle(
                            color: isCurrent ? AppColors.whiteColor : _statusColor(s),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Items
            const Text('Order Items',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 10),
            ...lineItems.map((item) {
              final name = item['name']?.toString() ?? 'Product';
              final qty = item['quantity']?.toString() ?? '1';
              final price = item['total']?.toString() ?? '0';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.indigoPaleColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shopping_bag_outlined,
                          color: AppColors.indigoColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.inkColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text('Qty: $qty',
                              style: const TextStyle(
                                  color: AppColors.inkSoftColor, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('\u00A3${double.tryParse(price)?.toStringAsFixed(2) ?? price}',
                        style: const TextStyle(
                            color: AppColors.goldColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // Customer
            const Text('Customer',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow('Name', _joinNames(billing)),
                  _infoRow('Email', billing['email']?.toString() ?? '-'),
                  _infoRow('Phone', billing['phone']?.toString() ?? '-'),
                  if (shipping['address_1'] != null)
                    _infoRow('Shipping', [
                      shipping['address_1'],
                      shipping['city'],
                      shipping['postcode'],
                    ].where((e) => e != null && e.toString().isNotEmpty).join(', ')),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Payment & Shipping
            const Text('Payment & Shipping',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow('Payment', paymentMethod),
                  _infoRow('Shipping', shippingMethod),
                  _infoRow('Total', '\u00A3${double.tryParse(total)?.toStringAsFixed(2) ?? total}'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tracking
            const Text('Add Tracking',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackingCtrl,
                    decoration: InputDecoration(
                      hintText: 'Tracking number',
                      hintStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.whiteColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _addTracking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.inkSoftColor, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _joinNames(Map<String, dynamic> billing) {
    final parts = [
      billing['first_name']?.toString(),
      billing['last_name']?.toString(),
    ].whereType<String>().where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  void _confirmStatusChange(String newStatus) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w600)),
        content: Text('Change order status to "$newStatus"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(newStatus);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
