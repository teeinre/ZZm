import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/currency_provider.dart';
import 'profile_screen.dart';

/// Order confirmation screen displayed after successful checkout.
///
/// Shows:
///   - Order ID for tracking
///   - Total amount paid
///   - For registered users: "View My Orders" → navigates to order history
///   - For guest users: email-based tracking notice + account creation prompt
///   - Continue Shopping button — pops to home
class OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  final String total;
  final bool isGuest;
  final String email;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.total,
    this.isGuest = false,
    this.email = '',
  });

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    final displayTotal = (double.tryParse(total) ?? 0);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.creamColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Success icon ──
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 52),
                  ),
                  const SizedBox(height: 24),

                  // ── Title ──
                  const Text(
                    'Order Confirmed!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkColor,
                      fontFamily: 'Fraunces',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your order has been placed successfully.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // ── Order details card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.whiteColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Order Number', '#$orderId'),
                        const Divider(height: 24),
                        _buildDetailRow('Total Amount',
                            '$currency${displayTotal == displayTotal.roundToDouble() ? displayTotal.toStringAsFixed(0) : displayTotal.toStringAsFixed(2)}',
                            isAmount: true),
                        if (email.isNotEmpty) ...[
                          const Divider(height: 24),
                          _buildDetailRow('Confirmation sent to', email),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Guest checkout notice ──
                  if (isGuest) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.indigoPaleColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.indigoColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, color: AppColors.indigoColor, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Guest Order',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.indigoColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your order was placed as a guest. '
                            'A confirmation email will be sent to $email. '
                            'Save your order number #$orderId for future reference.',
                            style: const TextStyle(fontSize: 12, color: AppColors.indigoColor, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          // Prompt to create account
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                                  );
                                }
                              },
                              icon: const Icon(Icons.person_add_outlined, size: 18),
                              label: const Text('Create an Account to Track Orders'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.indigoColor,
                                side: const BorderSide(color: AppColors.indigoColor),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── View orders (registered users only) ──
                  if (!isGuest) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Pop to home — users can view orders from their Profile > Your Orders
                          Navigator.of(context).popUntil((route) => route.isFirst);
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                              content: Text('View your orders anytime in Profile > Your Orders'),
                              backgroundColor: AppColors.indigoColor,
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long, size: 20),
                        label: const Text('View My Orders'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.goldColor,
                          side: const BorderSide(color: AppColors.goldColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Continue Shopping ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldColor,
                        foregroundColor: AppColors.whiteColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Continue Shopping',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAmount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppColors.inkSoftColor)),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isAmount ? AppColors.goldColor : AppColors.inkColor,
            )),
      ],
    );
  }
}
