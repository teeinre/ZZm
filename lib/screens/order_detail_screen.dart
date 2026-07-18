import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _order;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  void _loadOrder() async {
    try {
      final order = await _api.getOrder(widget.orderId);
      if (mounted) {
        setState(() {
          _order = order;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTrackingInfo() {
    final meta = _order?['meta_data'] as List<dynamic>? ?? [];
    String? trackingNumber;
    String? trackingUrl;
    for (final m in meta) {
      if (m is Map) {
        final key = m['key']?.toString() ?? '';
        if (key.contains('tracking')) {
          trackingNumber = m['value']?.toString();
        }
      }
    }
    if (trackingNumber == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.goldColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping, color: AppColors.goldColor, size: 16),
          const SizedBox(width: 8),
          Text('Tracking #: $trackingNumber',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'processing':
        return AppColors.goldColor;
      case 'cancelled':
        return AppColors.coralColor;
      case 'pending':
        return AppColors.indigoLightColor;
      default:
        return AppColors.inkSoftColor;
    }
  }

  List<Map<String, dynamic>> _getTimelineSteps(String status) {
    final steps = <Map<String, dynamic>>[
      {'label': 'Pending', 'icon': Icons.hourglass_empty, 'done': false, 'active': false, 'date': ''},
      {'label': 'Processing', 'icon': Icons.settings, 'done': false, 'active': false, 'date': ''},
      {'label': 'Shipped', 'icon': Icons.local_shipping, 'done': false, 'active': false, 'date': ''},
      {'label': 'Delivered', 'icon': Icons.check_circle, 'done': false, 'active': false, 'date': ''},
    ];

    final statusIndex = {
      'pending': 0,
      'processing': 1,
      'on-hold': 1,
      'completed': 2,
      'shipped': 2,
      'delivered': 3,
      'refunded': -1,
      'cancelled': -1,
      'failed': -1,
    };

    final idx = statusIndex[status.toLowerCase()] ?? 0;

    for (int i = 0; i < steps.length; i++) {
      if (i < idx) {
        steps[i]['done'] = true;
      } else if (i == idx) {
        steps[i]['active'] = true;
      }
    }

    // If cancelled/failed, mark pending as cancelled
    if (idx < 0) {
      steps[0]['label'] = status == 'cancelled' ? 'Cancelled' : 'Failed';
      steps[0]['active'] = true;
      steps[0]['icon'] = Icons.cancel;
      for (int i = 1; i < steps.length; i++) {
        steps[i]['active'] = false;
        steps[i]['done'] = false;
      }
    }

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Order Details',
          style: TextStyle(
            color: AppColors.inkColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldColor),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48,
                          color: AppColors.goldColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.inkSoftColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOrderHeader(),
                      const SizedBox(height: 16),
                      _buildOrderTimeline(),
                      const SizedBox(height: 16),
                      _buildItemsSection(),
                      const SizedBox(height: 16),
                      _buildShippingSection(),
                      const SizedBox(height: 16),
                      _buildBillingSection(),
                      const SizedBox(height: 16),
                      _buildPaymentSection(),
                      const SizedBox(height: 16),
                      _buildTotalsSection(),
                      if (_order?['payment_method'] == 'bacs') ...[
                        const SizedBox(height: 16),
                        _buildBankDetailsBox(),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  // ─── Order Header ───
  Widget _buildOrderHeader() {
    final orderNumber =
        _order?['number']?.toString() ?? '#${_order?['id'] ?? '—'}';
    final status = _order?['status']?.toString() ?? 'unknown';
    final dateCreated = _order?['date_created']?.toString() ?? '';
    final formattedDate = dateCreated.length >= 10
        ? dateCreated.substring(0, 10)
        : dateCreated;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order $orderNumber',
                style: const TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces',
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Placed on $formattedDate',
            style: const TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Order Timeline ───
  Widget _buildOrderTimeline() {
    final status = _order?['status']?.toString() ?? 'pending';
    final steps = _getTimelineSteps(status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Timeline',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isLast = index == steps.length - 1;
            final isDone = step['done'] == true;
            final isActive = step['active'] == true;
            final isCancelled = status == 'cancelled' || status == 'failed';

            Color dotColor;
            if (isCancelled && isActive) {
              dotColor = AppColors.coralColor;
            } else if (isDone || isActive) {
              dotColor = AppColors.goldColor;
            } else {
              dotColor = AppColors.indigoPaleColor;
            }

            return SizedBox(
              height: isLast ? 32 : 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dot + connecting line column
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Container(
                          width: isActive ? 16 : 12,
                          height: isActive ? 16 : 12,
                          decoration: BoxDecoration(
                            color: isDone || isActive
                                ? AppColors.goldColor
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: dotColor,
                              width: 2,
                            ),
                          ),
                          child: isDone
                              ? const Icon(Icons.check,
                                  size: 8,
                                  color: AppColors.whiteColor)
                              : null,
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: isDone
                                  ? AppColors.goldColor
                                  : AppColors.indigoPaleColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Label
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            step['label'] as String,
                            style: TextStyle(
                              color: isActive || isDone
                                  ? AppColors.inkColor
                                  : AppColors.inkSoftColor,
                              fontSize: 14,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(height: 2),
                            Text(
                              isCancelled ? 'Order cancelled' : 'In progress',
                              style: const TextStyle(
                                color: AppColors.inkSoftColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
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

  // ─── Items Section ───
  Widget _buildItemsSection() {
    final items = _order?['line_items'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Items',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Text(
              'No items in this order.',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
            )
          else
            ...items.map((item) {
              if (item is! Map<String, dynamic>) return const SizedBox.shrink();
              final name = item['name']?.toString() ?? 'Product';
              final quantity = item['quantity']?.toString() ?? '1';
              final price = item['price']?.toString() ?? '0.00';
              final total = item['total']?.toString() ?? '0.00';
              final imageUrl = item['image'] != null &&
                      item['image'] is Map &&
                      item['image']['src'] != null
                  ? item['image']['src'].toString()
                  : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: AppColors.creamColor,
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.inkSoftColor,
                                  size: 24,
                                ),
                              )
                            : const Icon(
                                Icons.image_outlined,
                                color: AppColors.inkSoftColor,
                                size: 24,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Qty: $quantity  ×  £${double.tryParse(price)?.toStringAsFixed(2) ?? price}',
                            style: const TextStyle(
                              color: AppColors.inkSoftColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '£${double.tryParse(total)?.toStringAsFixed(2) ?? total}',
                      style: const TextStyle(
                        color: AppColors.goldColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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

  // ─── Shipping Section ───
  Widget _buildShippingSection() {
    final shippingLines =
        _order?['shipping_lines'] as List<dynamic>? ?? [];
    final shippingAddress = _order?['shipping'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shipping',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 16),
          if (shippingLines.isNotEmpty)
            ...shippingLines.map((line) {
              if (line is! Map<String, dynamic>) return const SizedBox.shrink();
              final method =
                  line['method_title']?.toString() ?? 'Standard Shipping';
              final cost = line['total']?.toString() ?? '0.00';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined,
                        color: AppColors.goldColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        method,
                        style: const TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '£${double.tryParse(cost)?.toStringAsFixed(2) ?? cost}',
                      style: const TextStyle(
                        color: AppColors.goldColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (shippingLines.isEmpty)
            const Text(
              'No shipping information available.',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
            ),
          if (shippingAddress != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.indigoPaleColor),
            const SizedBox(height: 12),
            const Text(
              'Shipping Address',
              style: TextStyle(
                color: AppColors.inkSoftColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatAddress(shippingAddress),
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          // Tracking info
          if (_order?['meta_data'] != null)
            _buildTrackingInfo(),
        ],
      ),
    );
  }

  // ─── Billing Section ───
  Widget _buildBillingSection() {
    final billing = _order?['billing'] as Map<String, dynamic>?;
    if (billing == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Billing Address',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _formatAddress(billing),
            style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          if (billing['email']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.email_outlined,
                    color: AppColors.inkSoftColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  billing['email']!,
                  style: const TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          if (billing['phone']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    color: AppColors.inkSoftColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  billing['phone']!,
                  style: const TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Payment Section ───
  Widget _buildPaymentSection() {
    final method =
        _order?['payment_method_title']?.toString() ?? 'N/A';
    final transactionId =
        _order?['transaction_id']?.toString() ?? '';
    final datePaid = _order?['date_paid']?.toString() ?? '';
    final formattedPaidDate = datePaid.length >= 10
        ? datePaid.substring(0, 10)
        : datePaid;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 16),
          _buildPaymentInfoRow(
              Icons.payment_outlined, 'Method', method),
          if (transactionId.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPaymentInfoRow(
                Icons.receipt_long_outlined, 'Transaction ID', transactionId),
          ],
          if (formattedPaidDate.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPaymentInfoRow(
                Icons.calendar_today_outlined, 'Payment Date', formattedPaidDate),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.goldColor, size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Totals Section ───
  Widget _buildTotalsSection() {
    final subtotal = _order?['subtotal']?.toString() ?? '0.00';
    final shippingTotal =
        _order?['shipping_total']?.toString() ?? '0.00';
    final taxTotal = _order?['total_tax']?.toString() ?? '0.00';
    final discountTotal =
        _order?['discount_total']?.toString() ?? '0.00';
    final total = _order?['total']?.toString() ?? '0.00';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Total',
            style: TextStyle(
              color: AppColors.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 16),
          _buildTotalRow('Subtotal',
              '£${double.tryParse(subtotal)?.toStringAsFixed(2) ?? subtotal}'),
          const SizedBox(height: 8),
          _buildTotalRow('Shipping',
              '£${double.tryParse(shippingTotal)?.toStringAsFixed(2) ?? shippingTotal}'),
          const SizedBox(height: 8),
          _buildTotalRow('Tax',
              '£${double.tryParse(taxTotal)?.toStringAsFixed(2) ?? taxTotal}'),
          if ((double.tryParse(discountTotal) ?? 0) > 0) ...[
            const SizedBox(height: 8),
            _buildTotalRow('Discount',
                '-£${double.tryParse(discountTotal)?.toStringAsFixed(2) ?? discountTotal}',
                isDiscount: true),
          ],
          const SizedBox(height: 12),
          const Divider(color: AppColors.indigoPaleColor),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Fraunces',
                ),
              ),
              Text(
                '£${double.tryParse(total)?.toStringAsFixed(2) ?? total}',
                style: const TextStyle(
                  color: AppColors.goldColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Fraunces',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value,
      {bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.inkSoftColor,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isDiscount ? Colors.green : AppColors.inkColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─── Bank Details Box (BACS) ───
  Widget _buildBankDetailsBox() {
    return FutureBuilder<Map<String, String>>(
      future: _fetchBankDetails(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.values.every((v) => v.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.goldColor.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance,
                      color: AppColors.goldColor, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Bank Transfer Details',
                    style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Fraunces',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (data['bank_name']?.isNotEmpty == true)
                _buildBankRow('Bank', data['bank_name']!),
              if (data['account_name']?.isNotEmpty == true)
                _buildBankRow('Account Name', data['account_name']!),
              if (data['sort_code']?.isNotEmpty == true)
                _buildBankRow('Sort Code', data['sort_code']!),
              if (data['account_number']?.isNotEmpty == true)
                _buildBankRow('Account Number', data['account_number']!),
              if (data['iban']?.isNotEmpty == true)
                _buildBankRow('IBAN', data['iban']!),
              if (data['bic']?.isNotEmpty == true)
                _buildBankRow('BIC/SWIFT', data['bic']!),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.goldColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.goldColor, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please use your order number as the payment reference.',
                        style: TextStyle(
                          color: AppColors.inkSoftColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, String>> _fetchBankDetails() async {
    try {
      final api = ApiService();
      // Try vendor bank details first from line items
      final items = _order?['line_items'] as List<dynamic>?;
      if (items != null && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          // Check meta for dokan_vendor_id
          final meta = item['meta_data'] as List<dynamic>?;
          if (meta != null) {
            for (final m in meta) {
              if (m is Map && m['key'] == 'dokan_vendor_id') {
                final vendorId = int.tryParse(m['value']?.toString() ?? '');
                if (vendorId != null) {
                  final vendorBank = await api.getVendorBankDetails(vendorId);
                  if (vendorBank != null) return vendorBank;
                }
              }
            }
          }
          // Also try to look up the product to find its vendor
          final productId = item['product_id'] as int?;
          if (productId != null) {
            try {
              final product = await api.getProduct(productId);
              if (product != null && product.vendorId != null && product.vendorId! > 0) {
                final vendorBank = await api.getVendorBankDetails(product.vendorId!);
                if (vendorBank != null) return vendorBank;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    // Fall back to site BACS bank details
    return await ApiService().getSiteBankDetails();
  }

  Widget _buildBankRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.inkSoftColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───
  String _formatAddress(Map<String, dynamic> address) {
    final parts = <String>[];
    // Full name
    final first = address['first_name']?.toString() ?? '';
    final last = address['last_name']?.toString() ?? '';
    final name = '$first $last'.trim();
    if (name.isNotEmpty) parts.add(name);
    if (address['company']?.toString().isNotEmpty == true) {
      parts.add(address['company']!);
    }
    if (address['address_1']?.toString().isNotEmpty == true) {
      parts.add(address['address_1']!);
    }
    if (address['address_2']?.toString().isNotEmpty == true) {
      parts.add(address['address_2']!);
    }
    final city = address['city']?.toString() ?? '';
    final postcode = address['postcode']?.toString() ?? '';
    final country = address['country']?.toString() ?? '';
    final cityLine = [city, postcode, country]
        .where((s) => s.isNotEmpty)
        .join(', ');
    if (cityLine.isNotEmpty) parts.add(cityLine);
    return parts.join('\n');
  }
}
