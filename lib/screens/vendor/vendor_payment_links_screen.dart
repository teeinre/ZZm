import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/payment_link.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/currency_provider.dart';

/// Dokan Payment Links management — create, share (via QR), and cancel
/// shareable payment links from the vendor dashboard.
class VendorPaymentLinksScreen extends StatefulWidget {
  const VendorPaymentLinksScreen({super.key});

  @override
  State<VendorPaymentLinksScreen> createState() => _VendorPaymentLinksScreenState();
}

class _VendorPaymentLinksScreenState extends State<VendorPaymentLinksScreen> {
  List<PaymentLink> _links = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = context.read<VendorProvider>().apiService;
      final links = await api.getPaymentLinks();
      if (mounted) {
        setState(() {
          _links = links;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreatePaymentLinkSheet(),
    );
    if (created == true && mounted) {
      await _loadLinks();
    }
  }

  Future<void> _cancelLink(PaymentLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        title: const Text('Cancel payment link?'),
        content: Text(
          'This will cancel the unpaid link "${link.label}". This cannot be undone.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.coralColor),
            child: const Text('Cancel link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<VendorProvider>().apiService;
      await api.cancelPaymentLink(link.id);
      await _loadLinks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment link cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }

  void _showQr(PaymentLink link) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrShareSheet(link: link),
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
        title: const Text('Payment Links',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.inkColor),
            onPressed: _loadLinks,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _openCreateSheet,
        backgroundColor: AppColors.goldColor,
        foregroundColor: AppColors.whiteColor,
        icon: const Icon(Icons.add),
        label: const Text('New link'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : RefreshIndicator(
              color: AppColors.goldColor,
              onRefresh: _loadLinks,
              child: _error != null && _links.isEmpty
                  ? _buildErrorState()
                  : _links.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          itemCount: _links.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) => _buildLinkCard(_links[idx]),
                        ),
            ),
    );
  }

  Widget _buildLinkCard(PaymentLink link) {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  link.label,
                  style: const TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _statusChip(link),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$currency${link.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                color: AppColors.goldColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: 'Fraunces'),
          ),
          if (link.needsShipping) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: 14, color: AppColors.inkSoftColor),
                SizedBox(width: 6),
                Text('Requires shipping address',
                    style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
              ],
            ),
          ],
          if (link.expires.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Expires: ${link.expires}',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showQr(link),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('QR code'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.indigoDeepColor,
                    side: BorderSide(color: AppColors.indigoDeepColor.withOpacity(0.4)),
                  ),
                ),
              ),
              if (link.isCancellable) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _cancelLink(link),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.coralColor,
                    side: BorderSide(color: AppColors.coralColor.withOpacity(0.4)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(PaymentLink link) {
    Color color;
    String text;
    if (link.isPaid) {
      color = const Color(0xFF10B981);
      text = 'PAID';
    } else if (link.isExpired) {
      color = AppColors.inkSoftColor;
      text = 'EXPIRED';
    } else if (link.status == 'cancelled') {
      color = AppColors.coralColor;
      text = 'CANCELLED';
    } else {
      color = AppColors.goldColor;
      text = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Icons.qr_code_2, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text('No payment links yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 8),
        const Text(
          'Create a shareable payment link to collect payments without adding a product.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 64, color: AppColors.inkSoftColor),
        const SizedBox(height: 16),
        Text(
          _error ?? 'Unable to load payment links.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
        ),
      ],
    );
  }
}

class _CreatePaymentLinkSheet extends StatefulWidget {
  const _CreatePaymentLinkSheet();

  @override
  State<_CreatePaymentLinkSheet> createState() => _CreatePaymentLinkSheetState();
}

class _CreatePaymentLinkSheetState extends State<_CreatePaymentLinkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _labelController = TextEditingController();
  final _deliveryNoteController = TextEditingController();
  final _emailController = TextEditingController();
  bool _needsShipping = false;
  String _expiry = 'none';
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _labelController.dispose();
    _deliveryNoteController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final api = context.read<VendorProvider>().apiService;
      final result = await api.createPaymentLink(
        amount: double.parse(_amountController.text.trim()),
        label: _labelController.text.trim(),
        needsShipping: _needsShipping,
        deliveryNote: _deliveryNoteController.text.trim(),
        customerEmail: _emailController.text.trim(),
        expiry: _expiry,
      );
      if (mounted) {
        Navigator.pop(context, result != null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create link: $e')),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.inkSoftColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('New payment link',
                      style: TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Fraunces')),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _labelController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description (what is this payment for?)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a description'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Requires shipping address',
                        style: TextStyle(fontSize: 14)),
                    value: _needsShipping,
                    activeColor: AppColors.goldColor,
                    onChanged: (v) => setState(() => _needsShipping = v),
                  ),
                  if (_needsShipping) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _deliveryNoteController,
                      decoration: const InputDecoration(
                        labelText: 'Delivery note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Customer email (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _expiry,
                    decoration: const InputDecoration(
                      labelText: 'Expiry',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Never expires')),
                      DropdownMenuItem(value: '24h', child: Text('24 hours')),
                      DropdownMenuItem(value: '3d', child: Text('3 days')),
                      DropdownMenuItem(value: '7d', child: Text('7 days')),
                    ],
                    onChanged: (v) => setState(() => _expiry = v ?? 'none'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldColor,
                        foregroundColor: AppColors.whiteColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.whiteColor),
                            )
                          : const Text('Create link'),
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
}

class _QrShareSheet extends StatelessWidget {
  const _QrShareSheet({required this.link});

  final PaymentLink link;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inkSoftColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Scan to pay',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Fraunces')),
            const SizedBox(height: 4),
            Text(link.label,
                style: const TextStyle(
                    color: AppColors.inkSoftColor, fontSize: 13)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.15)),
              ),
              child: QrImageView(
                data: link.payUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link.payUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment link copied')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openLink(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context) async {
    final uri = Uri.parse(link.payUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link')),
        );
      }
    }
  }
}
