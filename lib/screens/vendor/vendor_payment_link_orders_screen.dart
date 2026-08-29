import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/payment_link.dart';
import '../../models/payment_link_order.dart';
import '../../providers/currency_provider.dart';
import '../../providers/vendor_provider.dart';

/// Dedicated screen listing every order minted from a single payment link.
///
/// Mirrors the "orders" view from the Dokan Payment Links plugin
/// (`DPL_Dashboard::render_orders()`).
class VendorPaymentLinkOrdersScreen extends StatefulWidget {
  const VendorPaymentLinkOrdersScreen({super.key, required this.link});

  final PaymentLink link;

  @override
  State<VendorPaymentLinkOrdersScreen> createState() =>
      _VendorPaymentLinkOrdersScreenState();
}

class _VendorPaymentLinkOrdersScreenState
    extends State<VendorPaymentLinkOrdersScreen> {
  List<PaymentLinkOrder> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = context.read<VendorProvider>().apiService;
      final orders = await api.getPaymentLinkOrders(widget.link.id);
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
        title: Text(
          'Orders for "${widget.link.label}"',
          style: const TextStyle(
              color: AppColors.inkColor,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.inkColor),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _load,
              child: _error != null && _orders.isEmpty
                  ? _buildErrorState()
                  : _orders.isEmpty
                      ? _buildEmptyState()
                      : _buildOrdersList(),
            ),
    );
  }

  Widget _buildOrdersList() {
    final symbol = context.watch<CurrencyProvider>().currencySymbol;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '${_orders.length} order${_orders.length == 1 ? '' : 's'}',
            style: const TextStyle(
                color: AppColors.inkSoftColor,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
        for (final order in _orders) _orderCard(order, symbol),
      ],
    );
  }

  Widget _orderCard(PaymentLinkOrder order, String symbol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _customerHeading(order),
                  style: const TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Fraunces'),
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(order.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _orderDetail(
                  'Order',
                  '#${order.id}',
                  valueColor: AppColors.inkColor,
                  valueWeight: FontWeight.w700,
                ),
              ),
              Expanded(child: _orderDetail('Date', order.date)),
              Expanded(
                child: _orderDetail(
                  'Total',
                  '$symbol${order.total.toStringAsFixed(2)}',
                  valueColor: AppColors.goldColor,
                  valueWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderDetail(
    String label,
    String value, {
    Color? valueColor,
    FontWeight valueWeight = FontWeight.w500,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
              color: valueColor ?? AppColors.inkSoftColor,
              fontSize: 12,
              fontWeight: valueWeight),
        ),
      ],
    );
  }

  String _customerHeading(PaymentLinkOrder order) {
    final designation = order.customerUsername.isEmpty ? 'Guest' : 'Customer';
    final name = _customerFullName(order);
    return name.isEmpty ? designation : '$designation: $name';
  }

  String _customerFullName(PaymentLinkOrder order) {
    if (order.customerName.isNotEmpty) return order.customerName;
    if (order.customer.isNotEmpty && order.customer.toLowerCase() != 'guest') {
      return order.customer;
    }
    if (order.customerEmail.isNotEmpty) return order.customerEmail;
    return '';
  }

  Widget _statusChip(String status) {
    final (label, color) = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  (String, Color) _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return ('COMPLETED', const Color(0xFF10B981));
      case 'processing':
        return ('PROCESSING', const Color(0xFF3B82F6));
      case 'on-hold':
        return ('ON HOLD', const Color(0xFFF59E0B));
      case 'pending':
        return ('PENDING', const Color(0xFFF59E0B));
      case 'refunded':
        return ('REFUNDED', AppColors.inkSoftColor);
      case 'cancelled':
        return ('CANCELLED', AppColors.coralColor);
      case 'failed':
        return ('FAILED', AppColors.coralColor);
      default:
        return (status.toUpperCase(), AppColors.inkSoftColor);
    }
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Icons.receipt_long_outlined,
            size: 64, color: AppColors.goldColor.withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text('No orders yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 8),
        const Text(
          'No orders have been placed through this payment link yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 64, color: AppColors.inkSoftColor),
        const SizedBox(height: 16),
        Text(
          _error ?? 'Unable to load orders.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
        ),
      ],
    );
  }
}
