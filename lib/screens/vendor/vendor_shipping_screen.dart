import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

/// Vendor Shipping Management - configure shipping methods, zones, and rates.
class VendorShippingScreen extends StatefulWidget {
  const VendorShippingScreen({super.key});

  @override
  State<VendorShippingScreen> createState() => _VendorShippingScreenState();
}

class _VendorShippingScreenState extends State<VendorShippingScreen> {
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
      final api = context.read<VendorProvider>().apiService;
      final zones = await api.getShippingZones();
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
    final zoneId = zone['id'];
    final locations = zone['locations'] as List<dynamic>? ?? [];
    final locationSummary = locations.map((l) => l['code']?.toString() ?? '').join(', ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: zoneId != null
            ? () => _showZoneMethods(zoneId is int ? zoneId : int.tryParse(zoneId.toString()) ?? 0, name)
            : null,
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
              onPressed: zoneId != null
                  ? () => _showZoneMethods(zoneId is int ? zoneId : int.tryParse(zoneId.toString()) ?? 0, name)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Zone Methods Management ──

  Future<void> _showZoneMethods(int zoneId, String zoneName) async {
    final api = context.read<VendorProvider>().apiService;
    List<Map<String, dynamic>> methods;
    try {
      methods = await api.getShippingZoneMethods(zoneId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load shipping methods'), backgroundColor: AppColors.coralColor),
      );
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: AppColors.creamColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inkSoftColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$zoneName - Methods',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
                          Text('${methods.length} method${methods.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.inkSoftColor),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: methods.isEmpty
                      ? const Center(
                          child: Text('No shipping methods in this zone',
                              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          itemCount: methods.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildMethodTile(methods[i], zoneId, setModalState),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMethodTile(Map<String, dynamic> method, int zoneId, StateSetter setModalState) {
    final methodId = method['instance_id'] ?? method['id'];
    final title = method['title']?.toString() ?? method['method_id']?.toString() ?? 'Unknown';
    final enabled = method['enabled'] == true;
    final cost = _extractCost(method);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled ? const Color(0xFF10B981).withOpacity(0.3) : AppColors.sandColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFF10B981).withOpacity(0.1) : AppColors.inkSoftColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              enabled ? Icons.check_circle : Icons.remove_circle_outline,
              color: enabled ? const Color(0xFF10B981) : AppColors.inkSoftColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inkColor)),
                const SizedBox(height: 2),
                Text(cost, style: const TextStyle(color: AppColors.goldColor, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: AppColors.goldColor,
            onChanged: (v) async {
              setModalState(() {});
              final api = context.read<VendorProvider>().apiService;
              final instanceId = methodId is int ? methodId : int.tryParse(methodId.toString());
              if (instanceId != null) {
                try {
                  await api.updateShippingZoneMethod(zoneId, instanceId, {'enabled': v});
                  if (mounted) {
                    method['enabled'] = v;
                    setModalState(() {});
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to update method'), backgroundColor: AppColors.coralColor),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  String _extractCost(Map<String, dynamic> method) {
    final settings = method['settings'];
    if (settings is Map) {
      final cost = settings['cost'];
      if (cost is Map) {
        final val = cost['value']?.toString();
        if (val != null && val.isNotEmpty) return '\u00A3$val';
      }
      if (cost != null && cost.toString().isNotEmpty) return '\u00A3$cost';
    }
    final directCost = method['cost']?.toString();
    if (directCost != null && directCost.isNotEmpty) return '\u00A3$directCost';
    return 'Free';
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
