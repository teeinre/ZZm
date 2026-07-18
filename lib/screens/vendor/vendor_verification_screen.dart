import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Vendor Verification status - shows vendor verification badge and details.
class VendorVerificationScreen extends StatelessWidget {
  const VendorVerificationScreen({super.key});

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
        title: const Text('Verification',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Verification status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.goldColor, AppColors.goldDeepColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.whiteColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user, color: AppColors.whiteColor, size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text('Verified Vendor',
                      style: TextStyle(color: AppColors.whiteColor, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Fraunces')),
                  const SizedBox(height: 6),
                  Text('Your store has been verified',
                      style: TextStyle(color: AppColors.whiteColor.withOpacity(0.85), fontSize: 13)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Verification badges
            _buildBadgeCard(
              Icons.badge,
              'Identity Verified',
              'Your government-issued ID has been verified.',
              true,
            ),
            const SizedBox(height: 10),
            _buildBadgeCard(
              Icons.location_on,
              'Address Verified',
              'Your business address has been confirmed.',
              true,
            ),
            const SizedBox(height: 10),
            _buildBadgeCard(
              Icons.phone_android,
              'Phone Verified',
              'Your phone number has been verified.',
              true,
            ),
            const SizedBox(height: 10),
            _buildBadgeCard(
              Icons.email,
              'Email Verified',
              'Your email address is confirmed.',
              true,
            ),

            const SizedBox(height: 20),
            const Text('Trust & Safety',
                style: TextStyle(color: AppColors.inkColor, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.whiteColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verified vendors on ZZmore Store enjoy:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  SizedBox(height: 10),
                  _TrustItem(icon: Icons.visibility, text: 'Increased store visibility in search results'),
                  _TrustItem(icon: Icons.thumb_up, text: 'Higher buyer trust and conversion rates'),
                  _TrustItem(icon: Icons.verified, text: 'Verified badge displayed on all your products'),
                  _TrustItem(icon: Icons.support, text: 'Priority customer support'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCard(IconData icon, String title, String subtitle, bool verified) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: verified ? const Color(0xFF10B981).withOpacity(0.1) : AppColors.goldColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: verified ? const Color(0xFF10B981) : AppColors.goldColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
              ],
            ),
          ),
          Icon(
            verified ? Icons.check_circle : Icons.pending,
            color: verified ? const Color(0xFF10B981) : AppColors.goldColor,
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TrustItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.goldColor, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12))),
        ],
      ),
    );
  }
}
