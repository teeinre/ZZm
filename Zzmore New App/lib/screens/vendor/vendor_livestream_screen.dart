import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/api_service.dart';

/// Dokan Livestreaming - Live product sales streaming.
/// This integrates with the Dokan Livestreaming add-on.
class VendorLivestreamScreen extends StatefulWidget {
  const VendorLivestreamScreen({super.key});

  @override
  State<VendorLivestreamScreen> createState() => _VendorLivestreamScreenState();
}

class _VendorLivestreamScreenState extends State<VendorLivestreamScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _streams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    setState(() => _isLoading = true);
    try {
      final streams = await _api.getDokanLivestreams();
      if (mounted) {
        setState(() {
          _streams = streams;
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
        title: const Text('Livestreaming',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.goldColor),
            onPressed: _startNewStream,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadStreams,
              child: _streams.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _streams.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _buildStreamCard(_streams[index]),
                    ),
            ),
    );
  }

  Widget _buildStreamCard(Map<String, dynamic> stream) {
    final isLive = stream['status']?.toString() == 'live';
    final viewers = stream['viewer_count'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: isLive ? Border.all(color: const Color(0xFFEF4444), width: 1.5) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isLive ? const Color(0xFFEF4444).withOpacity(0.1) : AppColors.indigoPaleColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLive ? Icons.live_tv : Icons.videocam_outlined,
              color: isLive ? const Color(0xFFEF4444) : AppColors.inkSoftColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(stream['title']?.toString() ?? 'Livestream',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    if (isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 6),
                            SizedBox(width: 4),
                            Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(stream['description']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.remove_red_eye_outlined, color: AppColors.inkSoftColor, size: 14),
                    const SizedBox(width: 4),
                    Text('$viewers viewers', style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 10)),
                    const SizedBox(width: 12),
                    Text(stream['created_at']?.toString() ?? '',
                        style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          if (isLive)
            IconButton(
              icon: const Icon(Icons.play_circle_filled, color: const Color(0xFFEF4444), size: 36),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Joining stream...')),
                );
              },
            ),
        ],
      ),
    );
  }

  void _startNewStream() {
    showDialog(
      context: context,
      builder: (ctx) {
        final titleCtrl = TextEditingController();
        final descCtrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.whiteColor,
          title: const Text('Start New Stream'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Stream Title', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx);
                  try {
                    await _api.createDokanLivestream({
                      'title': titleCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                    });
                    await _loadStreams();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stream started! Share the link with your viewers.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.coralColor),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldColor),
              child: const Text('Go Live', style: TextStyle(color: AppColors.whiteColor)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.live_tv_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
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
        ],
      ),
    );
  }
}
