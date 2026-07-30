import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

class VendorReviewsScreen extends StatefulWidget {
  const VendorReviewsScreen({super.key});

  @override
  State<VendorReviewsScreen> createState() => _VendorReviewsScreenState();
}

class _VendorReviewsScreenState extends State<VendorReviewsScreen> {
  final _replyCtrl = TextEditingController();
  int? _replyingTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadReviews();
    });
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReply(int reviewId, int productId) async {
    if (_replyCtrl.text.trim().isEmpty) return;
    final api = context.read<VendorProvider>().apiService;
    final ok = await api.replyToReview(
        reviewId, productId, _replyCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Reply posted' : 'Failed to post reply'),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
      if (ok) {
        _replyCtrl.clear();
        setState(() => _replyingTo = null);
      }
    }
  }

  Widget _buildStarRating(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star : Icons.star_border,
          color: AppColors.goldColor,
          size: 16,
        );
      }),
    );
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
        title: const Text('Reviews',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          final reviews = vendor.reviews;
          if (vendor.isLoadingReviews) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.goldColor));
          }
          if (reviews.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.reviews_outlined,
                      size: 64, color: AppColors.goldColor.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  const Text('No reviews yet',
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 8),
                  const Text('Customer reviews will appear here',
                      style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                ],
              ),
            );
          }

          final avgRating = reviews.fold<double>(
              0, (sum, r) => sum + (int.tryParse(r['rating']?.toString() ?? '0') ?? 0)) /
              reviews.length;

          return Column(
            children: [
              // Summary card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(avgRating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.indigoColor,
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Fraunces')),
                    const SizedBox(height: 4),
                    _buildStarRating(avgRating.round()),
                    const SizedBox(height: 6),
                    Text('${reviews.length} review${reviews.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: AppColors.inkSoftColor, fontSize: 13)),
                  ],
                ),
              ),

              // Reviews list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: reviews.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final r = reviews[index];
                    final reviewer = r['reviewer']?.toString() ??
                        r['name']?.toString() ?? 'Customer';
                    final reviewText = r['review']?.toString() ??
                        r['content']?.toString() ?? '';
                    final rating = int.tryParse(r['rating']?.toString() ?? '0') ?? 0;
                    final date = r['date_created']?.toString() ?? '';
                    final formattedDate =
                        date.length >= 10 ? date.substring(0, 10) : date;
                    final productName = r['product_name']?.toString() ?? '';
                    final reviewId = r['id'] is int ? r['id'] as int : 0;
                    final productId = r['product_id'] is int ? r['product_id'] as int : 0;

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
                              Container(
                                width: 36, height: 36,
                                decoration: const BoxDecoration(
                                  color: AppColors.indigoPaleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.person,
                                    color: AppColors.indigoColor, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(reviewer,
                                        style: const TextStyle(
                                            color: AppColors.inkColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    Text(formattedDate,
                                        style: const TextStyle(
                                            color: AppColors.inkSoftColor,
                                            fontSize: 10)),
                                  ],
                                ),
                              ),
                              _buildStarRating(rating),
                            ],
                          ),
                          if (productName.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.indigoPaleColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(productName,
                                  style: const TextStyle(
                                      color: AppColors.indigoColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ],
                          if (reviewText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(reviewText,
                                style: const TextStyle(
                                    color: AppColors.inkColor,
                                    fontSize: 13,
                                    height: 1.4)),
                          ],
                          const SizedBox(height: 10),
                          if (_replyingTo == reviewId) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _replyCtrl,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Write a reply...',
                                      hintStyle: const TextStyle(
                                          color: AppColors.inkSoftColor,
                                          fontSize: 12),
                                      filled: true,
                                      fillColor: AppColors.creamColor,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _submitReply(reviewId, productId),
                                  child: Container(
                                    width: 36, height: 36,
                                    decoration: const BoxDecoration(
                                      color: AppColors.goldColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.send,
                                        color: AppColors.whiteColor, size: 16),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _replyingTo = null),
                                  child: const Icon(Icons.close,
                                      color: AppColors.inkSoftColor, size: 20),
                                ),
                              ],
                            ),
                          ] else
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => setState(() {
                                  _replyingTo = reviewId;
                                  _replyCtrl.clear();
                                }),
                                icon: const Icon(Icons.reply_outlined,
                                    color: AppColors.goldColor, size: 16),
                                label: const Text('Reply',
                                    style: TextStyle(
                                        color: AppColors.goldColor, fontSize: 12)),
                              ),
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
}
