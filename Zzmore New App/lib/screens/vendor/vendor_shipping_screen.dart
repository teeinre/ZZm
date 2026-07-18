import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/api_service.dart';

/// Vendor Shipping Management - configure shipping methods, zones, and rates.
class VendorShippingScreen extends StatefulWidget {
  const VendorShippingScreen({super.key});

  @override
  State<VendorShippingScreen> createState() => _VendorShippingScreenState();
}

class _VendorShippingScreenState extends State<VendorShippingScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _zones = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShippingZones();
  }

  Future<void> _loadShippingZones() async {
    setState(() => _isLoading = true);
    try {
      final zones = await _api.getShippingZones();
      if (mounted) {
        setState(() {
          _zones = zones;
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
        title: const Text('Shipping Management',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadShippingZones,
              child: _zones.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _zones.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) => _buildZoneCard(_zones[idx]),
                    ),
            ),
    );
  }

  Widget _buildZoneCard(Map<String, dynamic> zone) {
    final name = zone['name']?.toString() ?? 'Unnamed Zone';
    final locations = zone['locations'] as List<dynamic>? ?? [];
    final locationSummary = locations.map((l) => l['code']?.toString() ?? '').join(', ');

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
              color: const Color(0xFF06B6D4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_shipping, color: Color(0xFF06B6D4), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(locationSummary.isNotEmpty ? locationSummary : 'No locations configured',
                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.goldColor, size: 20),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Manage "$name" shipping zone')),
              );
            },
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
          Icon(Icons.local_shipping_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No shipping zones yet',
              style: TextStyle(color: AppColors.inkColor, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Shipping zones are configured in WooCommerce',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        ],
      ),
    );
  }
}
