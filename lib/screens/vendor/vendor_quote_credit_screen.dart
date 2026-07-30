import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

/// Dokan Quote Credit - Request for Quote (RFQ) management.
/// This integrates with the Dokan Quote Credit add-on.
class VendorQuoteCreditScreen extends StatefulWidget {
  const VendorQuoteCreditScreen({super.key});

  @override
  State<VendorQuoteCreditScreen> createState() => _VendorQuoteCreditScreenState();
}

class _VendorQuoteCreditScreenState extends State<VendorQuoteCreditScreen> {
  List<Map<String, dynamic>> _quotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() => _isLoading = true);
    try {
      final api = context.read<VendorProvider>().apiService;
      final quotes = await api.getDokanQuotes();
      if (mounted) {
        setState(() {
          _quotes = quotes;
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
        title: const Text('Request for Quotes',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadQuotes,
              child: _quotes.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _quotes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _buildQuoteCard(_quotes[index]),
                    ),
            ),
    );
  }

  Widget _buildQuoteCard(Map<String, dynamic> quote) {
    final status = quote['status']?.toString() ?? 'pending';
    Color statusColor;
    switch (status) {
      case 'accepted':
        statusColor = const Color(0xFF10B981);
        break;
      case 'rejected':
        statusColor = AppColors.coralColor;
        break;
      default:
        statusColor = AppColors.goldColor;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quote['customer_name']?.toString() ?? 'Customer',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          Text(quote['message']?.toString() ?? 'No message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Qty: ${quote['quantity'] ?? '-'}',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
              ),
              const Spacer(),
              Text(
                quote['created_at']?.toString() ?? '',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 10),
              ),
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
          Icon(Icons.request_quote_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No quote requests yet',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Customer quote requests will appear here',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        ],
      ),
    );
  }
}
