import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../cache/hive_service.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

/// Livestream configuration screen for vendors.
/// Streams are persisted locally via Hive since the Dokan backend
/// does not yet provide a livestream REST API.
class VendorLivestreamScreen extends StatefulWidget {
  const VendorLivestreamScreen({super.key});

  @override
  State<VendorLivestreamScreen> createState() => _VendorLivestreamScreenState();
}

class _VendorLivestreamScreenState extends State<VendorLivestreamScreen> {
  static const String _hiveKey = 'vendor_livestreams';

  final HiveService _hive = HiveService();
  List<Map<String, dynamic>> _streams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  // ── Data ──

  Future<void> _loadStreams() async {
    setState(() => _isLoading = true);
    try {
      // Try backend first, fall back to local cache
      final api = context.read<VendorProvider>().apiService;
      final remote = await api.getDokanLivestreams();
      if (remote.isNotEmpty) {
        _streams = remote;
        await _persist();
      } else {
        _streams = _readLocal();
      }
    } catch (_) {
      _streams = _readLocal();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> _readLocal() {
    final raw = _hive.getString(_hiveKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist() async {
    await _hive.saveString(_hiveKey, jsonEncode(_streams));
  }

  // ── Build ──

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
        title: const Text('Livestreaming',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.goldColor),
            onPressed: () => _showCreateStreamForm(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadStreams,
              child: _streams.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _streams.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildStreamCard(_streams[index], index),
                    ),
            ),
    );
  }

  // ── Stream Card ──

  Widget _buildStreamCard(Map<String, dynamic> stream, int index) {
    final status = stream['status']?.toString() ?? 'scheduled';
    final isLive = status == 'live';
    final isEnded = status == 'ended';
    // Auto-detect platform from stream URL — no stored platform field
    final streamUrl = stream['stream_url']?.toString() ?? '';
    final detectedPlatform = _detectPlatform(streamUrl);
    final platformLabel = _platformLabel(detectedPlatform);
    final platformIcon = _platformIcon(detectedPlatform);
    final productIds = (stream['product_ids'] as List<dynamic>?) ?? [];
    final scheduledAt = stream['scheduled_at']?.toString() ?? '';
    final formattedDate = scheduledAt.isNotEmpty
        ? _formatDateTime(scheduledAt)
        : 'No schedule';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: isLive
            ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Platform icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLive
                      ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                      : AppColors.indigoPaleColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(platformIcon,
                    color: isLive ? const Color(0xFFEF4444) : AppColors.inkSoftColor,
                    size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              stream['title']?.toString() ?? 'Livestream',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        _statusChip(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stream['description']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Meta row
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _metaItem(Icons.tv, platformLabel),
              _metaItem(Icons.schedule, formattedDate),
              _metaItem(Icons.shopping_bag_outlined,
                  '${productIds.length} product${productIds.length == 1 ? '' : 's'}'),
            ],
          ),
          const SizedBox(height: 10),
          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isLive || status == 'scheduled')
                TextButton.icon(
                  onPressed: () => _editStream(index),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.inkSoftColor),
                ),
              const SizedBox(width: 4),
              if (!isEnded)
                TextButton.icon(
                  onPressed: () => _toggleLive(index),
                  icon: Icon(
                      isLive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                      size: 16),
                  label: Text(isLive ? 'End' : 'Go Live',
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        isLive ? AppColors.coralColor : const Color(0xFF10B981),
                  ),
                ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _deleteStream(index),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.coralColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'live':
        bg = const Color(0xFFEF4444);
        fg = Colors.white;
        label = 'LIVE';
        break;
      case 'ended':
        bg = AppColors.inkSoftColor;
        fg = Colors.white;
        label = 'ENDED';
        break;
      default:
        bg = AppColors.goldColor.withValues(alpha: 0.15);
        fg = AppColors.goldColor;
        label = 'SCHEDULED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.inkSoftColor),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                color: AppColors.inkSoftColor, fontSize: 11)),
      ],
    );
  }

  // ── Create / Edit Form ──

  void _showCreateStreamForm({int? editIndex}) async {
    final isEdit = editIndex != null;
    final existing = isEdit ? Map<String, dynamic>.from(_streams[editIndex]) : null;

    final titleCtrl =
        TextEditingController(text: existing?['title']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    final urlCtrl =
        TextEditingController(text: existing?['stream_url']?.toString() ?? '');
    DateTime scheduledDate =
        _tryParseDate(existing?['scheduled_at']?.toString()) ?? DateTime.now().add(const Duration(hours: 1));
    TimeOfDay scheduledTime = TimeOfDay.fromDateTime(scheduledDate);

    final vendor = context.read<VendorProvider>();

    // Load products if not yet loaded (they may not have been fetched on dashboard init)
    List<Map<String, dynamic>> products = List<Map<String, dynamic>>.from(vendor.vendorProducts);
    if (products.isEmpty && vendor.vendorId != null && vendor.vendorId! > 0) {
      // Show loading indicator while fetching
      final loadingCtx = context;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const Center(
          child: SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(color: AppColors.goldColor, strokeWidth: 3),
          ),
        ),
      );
      await vendor.loadVendorProducts(vendorId: vendor.vendorId!);
      if (loadingCtx.mounted) {
        Navigator.pop(loadingCtx);
      }
      if (mounted && context.mounted) {
        products = List<Map<String, dynamic>>.from(vendor.vendorProducts);
      }
    }
    Set<int> selectedProductIds = {};
    if (existing?['product_ids'] is List) {
      selectedProductIds = (existing!['product_ids'] as List)
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((id) => id > 0)
          .toSet();
    }

    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: AppColors.creamColor,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.inkSoftColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEdit ? 'Edit Stream' : 'Create New Stream',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Fraunces',
                              color: AppColors.inkColor),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.inkSoftColor),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  // Form body
                  Expanded(
                    child: Form(
                      key: formKey,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        children: [
                          // ── Title ──
                          _sectionLabel('Stream Title *'),
                          TextFormField(
                            controller: titleCtrl,
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Title is required' : null,
                            decoration: _inputDecoration(
                                'e.g. New Arrivals Live Sale'),
                          ),
                          const SizedBox(height: 16),

                          // ── Stream URL ──
                          _sectionLabel('Stream URL / Key *'),
                          TextFormField(
                            controller: urlCtrl,
                            keyboardType: TextInputType.url,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Stream URL is required';
                              }
                              final uri = Uri.tryParse(v.trim());
                              if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                                return 'Enter a valid URL (e.g. https://youtube.com/live/…)';
                              }
                              return null;
                            },
                            decoration: _inputDecoration(
                                'https://youtube.com/live/…'),
                          ),
                          const SizedBox(height: 16),

                          // ── Description ──
                          _sectionLabel('Description *'),
                          TextFormField(
                            controller: descCtrl,
                            maxLines: 3,
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Description is required' : null,
                            decoration: _inputDecoration(
                                'Tell viewers what you\'ll be showcasing…'),
                          ),
                          const SizedBox(height: 16),

                          // ── Date & Time ──
                          _sectionLabel('Scheduled Start'),
                          Row(
                            children: [
                              Expanded(
                                child: _dateTimeButton(
                                  icon: Icons.calendar_today,
                                  label: _dateOnly(scheduledDate),
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: scheduledDate,
                                      firstDate: DateTime.now(),
                                      lastDate:
                                          DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        scheduledDate = DateTime(
                                          picked.year,
                                          picked.month,
                                          picked.day,
                                          scheduledTime.hour,
                                          scheduledTime.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _dateTimeButton(
                                  icon: Icons.access_time,
                                  label: scheduledTime.format(context),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: scheduledTime,
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        scheduledTime = picked;
                                        scheduledDate = DateTime(
                                          scheduledDate.year,
                                          scheduledDate.month,
                                          scheduledDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Product Selection ──
                          _sectionLabel(
                              'Featured Products (${selectedProductIds.length} selected)'),
                          if (products.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.whiteColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'No products available. Add products to your store first.',
                                style: TextStyle(
                                    color: AppColors.inkSoftColor, fontSize: 13),
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.whiteColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.blackPaleColor),
                              ),
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(8),
                                itemCount: products.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final p = products[i];
                                  final pid = p['id'] is int
                                      ? p['id'] as int
                                      : int.tryParse(p['id']?.toString() ?? '') ??
                                          0;
                                  final selected = selectedProductIds.contains(pid);
                                  return CheckboxListTile(
                                    dense: true,
                                    value: selected,
                                    activeColor: AppColors.goldColor,
                                    title: Text(
                                      p['name']?.toString() ?? 'Product #$pid',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    subtitle: p['price'] != null
                                        ? Text(
                                            '${p['price']}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.goldColor),
                                          )
                                        : null,
                                    onChanged: (checked) {
                                      setModalState(() {
                                        if (checked == true) {
                                          selectedProductIds.add(pid);
                                        } else {
                                          selectedProductIds.remove(pid);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 24),

                          // ── Actions ──
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.inkSoftColor,
                                    side: const BorderSide(
                                        color: AppColors.blackPaleColor),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (!formKey.currentState!.validate()) return;

                                    final data = <String, dynamic>{
                                      'title': titleCtrl.text.trim(),
                                      'stream_url': urlCtrl.text.trim(),
                                      'description': descCtrl.text.trim(),
                                      'scheduled_at':
                                          scheduledDate.toIso8601String(),
                                      'product_ids':
                                          selectedProductIds.toList(),
                                      'status': existing?['status'] ?? 'scheduled',
                                    };

                                    final idx = editIndex;
                                    final vendorProvider = context.read<VendorProvider>();
                                    Navigator.pop(ctx);

                                    if (idx != null) {
                                      _streams[idx] = data;
                                    } else {
                                      _streams.insert(0, data);
                                    }
                                    await _persist();

                                    // Also attempt backend sync (non-blocking)
                                    try {
                                      await vendorProvider.apiService.createDokanLivestream(data);
                                    } catch (_) {
                                      // Backend unavailable; locally persisted
                                    }

                                    setState(() {});
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(isEdit
                                              ? 'Stream updated'
                                              : 'Stream scheduled!'),
                                          backgroundColor: AppColors.goldColor,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.live_tv, size: 18),
                                  label: Text(isEdit ? 'Save Changes' : 'Schedule Stream'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.goldColor,
                                    foregroundColor: AppColors.whiteColor,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Bottom safe area padding for keyboard
                          SizedBox(
                              height: MediaQuery.of(context).padding.bottom + 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Actions ──

  void _editStream(int index) {
    _showCreateStreamForm(editIndex: index);
  }

  Future<void> _toggleLive(int index) async {
    final isLive = _streams[index]['status']?.toString() == 'live';
    setState(() {
      _streams[index]['status'] = isLive ? 'ended' : 'live';
    });
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLive ? 'Stream ended' : 'Stream is now live!'),
          backgroundColor: AppColors.goldColor,
        ),
      );
    }
  }

  Future<void> _deleteStream(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        title: const Text('Delete Stream?'),
        content: Text(
            'Remove "${_streams[index]['title'] ?? 'this stream'}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coralColor),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.whiteColor)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _streams.removeAt(index));
      await _persist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stream deleted')),
        );
      }
    }
  }

  // ── Helpers ──

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inkColor)),
    );
  }

  InputDecoration _inputDecoration(String hint, {TextStyle? hintStyle}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: hintStyle ?? const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
      filled: true,
      fillColor: AppColors.whiteColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.blackPaleColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.blackPaleColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.goldColor),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.coralColor),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      isDense: true,
    );
  }

  Widget _dateTimeButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.blackPaleColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.goldColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: AppColors.inkColor)),
            ),
          ],
        ),
      ),
    );
  }

  /// Auto-detect streaming platform from the URL domain.
  String _detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com') || u.contains('youtu.be')) return 'youtube';
    if (u.contains('facebook.com') || u.contains('fb.watch')) return 'facebook';
    if (u.contains('twitch.tv')) return 'twitch';
    if (u.contains('instagram.com') || u.contains('instagr.am')) return 'instagram';
    if (u.contains('tiktok.com')) return 'tiktok';
    return 'custom';
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'youtube':
        return 'YouTube';
      case 'facebook':
        return 'Facebook';
      case 'twitch':
        return 'Twitch';
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      default:
        return 'Custom';
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'youtube':
        return Icons.play_circle_filled;
      case 'facebook':
        return Icons.facebook;
      case 'twitch':
        return Icons.videogame_asset;
      case 'instagram':
        return Icons.camera_alt;
      case 'tiktok':
        return Icons.music_note;
      default:
        return Icons.live_tv;
    }
  }

  String _dateOnly(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
  }

  DateTime? _tryParseDate(String? iso) {
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  // ── Empty State ──

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.live_tv_outlined,
              size: 64, color: AppColors.goldColor.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('No livestreams yet',
              style: TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces')),
          const SizedBox(height: 8),
          const Text('Start streaming to sell products live',
              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateStreamForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Stream'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldColor,
              foregroundColor: AppColors.whiteColor,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }
}
