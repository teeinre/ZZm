import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

/// Dokan Returns &amp; Refunds (RMA) management.
class VendorRefundsScreen extends StatefulWidget {
  const VendorRefundsScreen({super.key});

  @override
  State<VendorRefundsScreen> createState() => _VendorRefundsScreenState();
}

class _VendorRefundsScreenState extends State<VendorRefundsScreen> {
  List<Map<String, dynamic>> _refunds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    setState(() => _isLoading = true);
    try {
      final api = context.read<VendorProvider>().apiService;
      final refunds = await api.getDokanRefunds();
      if (mounted) {
        setState(() {
          _refunds = refunds;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
        title: const Text('Returns & Refunds',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadRefunds,
              child: _refunds.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _refunds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) => _buildRefundCard(_refunds[idx]),
                    ),
            ),
    );
  }

  Widget _buildRefundCard(Map<String, dynamic> refund) {
    final status = refund['status']?.toString() ?? 'pending';
    final amount = refund['amount']?.toString() ?? '0.00';
    final reason = refund['reason']?.toString() ?? 'No reason provided';

    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = const Color(0xFF10B981);
        break;
      case 'rejected':
        statusColor = AppColors.coralColor;
        break;
      case 'processing':
        statusColor = const Color(0xFF3B82F6);
        break;
      default:
        statusColor = AppColors.goldColor;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #${refund['order_id'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(reason, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('\u00A3${double.tryParse(amount)?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text(refund['date_created']?.toString() ?? '',
                  style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_return_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No refund requests',
              style: TextStyle(color: AppColors.inkColor, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Customer refund and return requests will appear here',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        ],
      ),
    );
  }
}
