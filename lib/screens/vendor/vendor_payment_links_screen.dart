import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/payment_link.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/currency_provider.dart';
import 'vendor_payment_link_orders_screen.dart';
import 'vendor_payment_link_qr_screen.dart';

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

  /// Ids of cards whose non-essential details are expanded on mobile.
  final Set<int> _expanded = {};

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

  void _openQr(PaymentLink link) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorPaymentLinkQrScreen(link: link)),
    );
  }

  void _openOrders(PaymentLink link) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => VendorPaymentLinkOrdersScreen(link: link)),
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
                      : _buildLinksBody(),
            ),
    );
  }

  Widget _buildLinksBody() {
    final currency = context.watch<CurrencyProvider>().currencySymbol;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tablets / wide screens keep the full table (horizontal-scrollable).
        // Phones get a vertically stacked, touch-friendly card list.
        if (constraints.maxWidth >= 600) {
          return _buildLinksTable(currency);
        }
        return _buildLinksCards(currency);
      },
    );
  }

  /// Wide-screen table. Kept horizontally scrollable so that every column
  /// (including actions) stays reachable without squeezing content.
  Widget _buildLinksTable(String currency) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 88),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.inkSoftColor.withOpacity(0.08)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(),
                1: FixedColumnWidth(70),
                2: FixedColumnWidth(90),
                3: FixedColumnWidth(110),
                4: FixedColumnWidth(120),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(
                    color: AppColors.inkSoftColor.withOpacity(0.08)),
              ),
              children: [
                _headerRow(),
                for (final link in _links) _linkRow(link, currency),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile stacked-card list. Prioritizes the highest-value fields
  /// (id, label, amount, status, orders) and folds secondary details behind
  /// an expandable "Details" row.
  Widget _buildLinksCards(String currency) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _links.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildLinkCard(_links[index], currency),
    );
  }

  Widget _buildLinkCard(PaymentLink link, String currency) {
    final expanded = _expanded.contains(link.id);
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text('#${link.id}',
                  style: const TextStyle(
                      color: AppColors.inkSoftColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _statusChip(link),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openOrders(link),
            child: Text(
              link.label,
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Fraunces',
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _amountLabel(link, currency),
            style: const TextStyle(
              color: AppColors.goldColor,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFamily: 'Fraunces',
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _openOrders(link),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      size: 16, color: AppColors.inkSoftColor),
                  const SizedBox(width: 6),
                  Text(
                    '${link.orderCount} order${link.orderCount == 1 ? '' : 's'}'
                    '${link.paidCount > 0 ? ' · ${link.paidCount} paid' : ''}',
                    style: const TextStyle(
                        color: AppColors.inkColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.inkSoftColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _cardButton(
                icon: Icons.qr_code_2,
                label: 'QR Page',
                onTap: () => _openQr(link),
                filled: true,
              ),
              _cardButton(
                icon: Icons.copy,
                label: 'Copy',
                onTap: () => _copyLink(link),
              ),
              if (link.isCancellable)
                _cardButton(
                  icon: Icons.close,
                  label: 'Cancel',
                  onTap: () => _cancelLink(link),
                  destructive: true,
                ),
            ],
          ),
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(link.id);
              } else {
                _expanded.add(link.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.inkSoftColor),
                  const SizedBox(width: 6),
                  const Text('Details',
                      style: TextStyle(
                          color: AppColors.inkSoftColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: AppColors.inkSoftColor),
                ],
              ),
            ),
          ),
          if (expanded) _buildCardDetails(link, currency),
        ],
      ),
    );
  }

  void _copyLink(PaymentLink link) {
    Clipboard.setData(ClipboardData(text: link.payUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment link copied')),
    );
  }

  Widget _cardButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
    bool destructive = false,
  }) {
    final foreground = destructive
        ? AppColors.coralColor
        : (filled ? AppColors.whiteColor : AppColors.inkColor);
    final background = filled ? AppColors.goldColor : Colors.transparent;
    final side = filled
        ? BorderSide.none
        : BorderSide(
            color: (destructive ? AppColors.coralColor : AppColors.inkColor)
                .withOpacity(0.4));

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        side: side,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildCardDetails(PaymentLink link, String currency) {
    final rows = <(String, String)>[
      if (link.createdDate.isNotEmpty) ('Created', link.createdDate),
      if (link.expires.isNotEmpty) ('Expires', link.expires),
      if (link.paidCount > 0)
        ('Total paid', '$currency${link.totalPaid.toStringAsFixed(2)}'),
      if (link.needsShipping) ('Shipping', 'Required'),
      if (link.deliveryNote != null && link.deliveryNote!.isNotEmpty)
        ('Delivery note', link.deliveryNote!),
    ];
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('No additional details',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.inkSoftColor, fontSize: 12)),
                ),
                Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          color: AppColors.inkColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  TableRow _headerRow() {
    const style = TextStyle(
        color: AppColors.inkSoftColor, fontSize: 11, fontWeight: FontWeight.w700);
    return TableRow(
      decoration: BoxDecoration(color: AppColors.creamColor),
      children: const [
        _Cell(text: 'Payment Link', style: style, padding: 12),
        _Cell(text: 'Orders', style: style, padding: 12),
        _Cell(text: 'Status', style: style, padding: 12),
        _Cell(text: 'QR Page', style: style, padding: 12),
        _Cell(text: 'Actions', style: style, padding: 12),
      ],
    );
  }

  TableRow _linkRow(PaymentLink link, String currency) {
    return TableRow(
      children: [
        _Cell(
          padding: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _openOrders(link),
                child: Text(
                  link.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.goldColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.goldColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _amountLabel(link, currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
              ),
            ],
          ),
        ),
        _Cell(
          padding: 12,
          child: InkWell(
            onTap: () => _openOrders(link),
            child: Text(
              '${link.orderCount}',
              style: const TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        _Cell(padding: 12, child: _statusChip(link)),
        _Cell(
          padding: 12,
          child: OutlinedButton.icon(
            onPressed: () => _openQr(link),
            icon: const Icon(Icons.qr_code_2, size: 15),
            label: const Text('View'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.indigoDeepColor,
              side:
                  BorderSide(color: AppColors.indigoDeepColor.withOpacity(0.4)),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        _Cell(
          padding: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copy link',
                onPressed: () => _copyLink(link),
                icon: const Icon(Icons.copy, size: 17, color: AppColors.inkColor),
              ),
              if (link.isCancellable)
                IconButton(
                  tooltip: 'Cancel link',
                  onPressed: () => _cancelLink(link),
                  icon:
                      const Icon(Icons.close, size: 17, color: AppColors.coralColor),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _amountLabel(PaymentLink link, String currency) {
    final formatted = link.amountFormatted;
    if (formatted != null && formatted.isNotEmpty) return formatted;
    if (link.amount > 0) return '$currency${link.amount.toStringAsFixed(2)}';
    return 'Open amount';
  }

  Widget _statusChip(PaymentLink link) {
    Color color;
    String text;
    if (link.isCancelled) {
      color = AppColors.coralColor;
      text = 'CANCELLED';
    } else if (link.isExpired) {
      color = AppColors.inkSoftColor;
      text = 'EXPIRED';
    } else {
      color = const Color(0xFF10B981);
      text = 'ACTIVE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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
  bool _needsShipping = false;
  String _expiry = 'none';
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _labelController.dispose();
    _deliveryNoteController.dispose();
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

class _Cell extends StatelessWidget {
  const _Cell({this.text, this.child, this.padding = 16, this.style});

  final String? text;
  final Widget? child;
  final double padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: child ?? Text(text ?? '', style: style),
    );
  }
}
