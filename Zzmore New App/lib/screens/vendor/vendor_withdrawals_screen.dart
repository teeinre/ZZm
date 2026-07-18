import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

class VendorWithdrawalsScreen extends StatefulWidget {
  const VendorWithdrawalsScreen({super.key});

  @override
  State<VendorWithdrawalsScreen> createState() => _VendorWithdrawalsScreenState();
}

class _VendorWithdrawalsScreenState extends State<VendorWithdrawalsScreen> {
  final _amountCtrl = TextEditingController();
  String _withdrawMethod = 'bank';
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final v = context.read<VendorProvider>();
      v.loadBalance();
      v.loadWithdrawals();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestWithdrawal() async {
    final amt = double.tryParse(_amountCtrl.text);
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount'),
            backgroundColor: AppColors.coralColor));
      return;
    }
    setState(() => _isRequesting = true);
    final vendor = context.read<VendorProvider>();
    final ok = await vendor.requestWithdrawal(amt, _withdrawMethod);
    if (mounted) {
      setState(() => _isRequesting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Withdrawal request submitted' : 'Failed to submit request'),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
      if (ok) _amountCtrl.clear();
    }
  }

  void _showRequestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Consumer<VendorProvider>(
          builder: (context, vendor, _) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.sandColor,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Request Withdrawal',
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 6),
                  Text('Available balance: \u00A3${vendor.currentBalance.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (\u00A3)',
                      labelStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.creamColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Method',
                      style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['bank', 'paypal', 'skrill'].map((m) {
                      final isSelected = _withdrawMethod == m;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _withdrawMethod = m),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.goldColor.withOpacity(0.1)
                                  : AppColors.creamColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isSelected
                                      ? AppColors.goldColor
                                      : Colors.transparent),
                            ),
                            child: Text(m[0].toUpperCase() + m.substring(1),
                                style: TextStyle(
                                    color: isSelected
                                        ? AppColors.goldColor
                                        : AppColors.inkSoftColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isRequesting
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _requestWithdrawal();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldColor,
                        foregroundColor: AppColors.whiteColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isRequesting
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.whiteColor))
                          : const Text('Submit Request',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'pending':
        return AppColors.goldColor;
      case 'cancelled':
        return AppColors.coralColor;
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
        title: const Text('Withdrawals',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          TextButton.icon(
            onPressed: _showRequestSheet,
            icon: const Icon(Icons.add_circle_outline, color: AppColors.goldColor, size: 20),
            label: const Text('Request',
                style: TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          return Column(
            children: [
              // Balance card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
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
                  children: [
                    const Text('Current Balance',
                        style: TextStyle(
                            color: AppColors.whiteColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text('\u00A3${vendor.currentBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.goldColor,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Fraunces')),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _balanceInfo('Total Earned',
                            vendor.balance['total_earned']?.toString() ?? '0'),
                        Container(width: 1, height: 30,
                            color: AppColors.whiteColor.withOpacity(0.2)),
                        _balanceInfo('Withdrawn',
                            vendor.balance['total_withdrawn']?.toString() ?? '0'),
                      ],
                    ),
                  ],
                ),
              ),

              // History
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('Withdrawal History',
                        style: TextStyle(
                            color: AppColors.inkColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Fraunces')),
                    const Spacer(),
                    if (vendor.withdrawals.isNotEmpty)
                      Text('${vendor.withdrawals.length} requests',
                          style: const TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: vendor.isLoadingWithdrawals
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.goldColor))
                    : vendor.withdrawals.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.account_balance_wallet_outlined,
                                    size: 48,
                                    color: AppColors.goldColor.withOpacity(0.3)),
                                const SizedBox(height: 12),
                                const Text('No withdrawals yet',
                                    style: TextStyle(
                                        color: AppColors.inkSoftColor, fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: vendor.withdrawals.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final w = vendor.withdrawals[index];
                              final amt = w['amount']?.toString() ?? '0';
                              final status = w['status']?.toString() ?? 'pending';
                              final date = w['date']?.toString() ?? w['created_at']?.toString() ?? '';
                              final formattedDate =
                                  date.length >= 10 ? date.substring(0, 10) : date;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.whiteColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.payments_outlined,
                                          color: _statusColor(status), size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('\u00A3${double.tryParse(amt)?.toStringAsFixed(2) ?? amt}',
                                              style: const TextStyle(
                                                  color: AppColors.inkColor,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold)),
                                          Text(formattedDate,
                                              style: const TextStyle(
                                                  color: AppColors.inkSoftColor,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(status.toUpperCase(),
                                          style: TextStyle(
                                              color: _statusColor(status),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _balanceInfo(String label, String value) {
    return Column(
      children: [
        Text('\u00A3${double.tryParse(value)?.toStringAsFixed(2) ?? value}',
            style: const TextStyle(
                color: AppColors.whiteColor,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: AppColors.whiteColor.withOpacity(0.7), fontSize: 11)),
      ],
    );
  }
}
