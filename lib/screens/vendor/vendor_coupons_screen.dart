import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';
import '../../services/api_service.dart';

class VendorCouponsScreen extends StatefulWidget {
  const VendorCouponsScreen({super.key});

  @override
  State<VendorCouponsScreen> createState() => _VendorCouponsScreenState();
}

class _VendorCouponsScreenState extends State<VendorCouponsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadCoupons();
    });
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
        title: const Text('Coupons',
            style: TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          TextButton.icon(
            onPressed: () => _openAddEditCoupon(),
            icon: const Icon(Icons.add_circle_outline, color: AppColors.goldColor, size: 20),
            label: const Text('Add',
                style: TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Consumer<VendorProvider>(
        builder: (context, vendor, _) {
          final coupons = vendor.coupons;
          return vendor.isLoadingCoupons
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.goldColor))
              : coupons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.discount_outlined,
                              size: 64, color: AppColors.goldColor.withOpacity(0.4)),
                          const SizedBox(height: 16),
                          const Text('No coupons yet',
                              style: TextStyle(
                                  color: AppColors.inkColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Fraunces')),
                          const SizedBox(height: 8),
                          const Text('Create discount coupons for your store',
                              style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _openAddEditCoupon(),
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Create Coupon'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.goldColor,
                              foregroundColor: AppColors.whiteColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.goldColor,
                      onRefresh: () => vendor.loadCoupons(),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: coupons.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _buildCouponCard(coupons[index], vendor),
                      ),
                    );
        },
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon, VendorProvider vendor) {
    final code = coupon['code']?.toString() ?? '';
    final amount = coupon['amount']?.toString() ?? '0';
    final type = coupon['discount_type']?.toString() ?? 'fixed_cart';
    final usageCount = coupon['usage_count']?.toString() ?? '0';
    final usageLimit = coupon['usage_limit'];
    final expired = coupon['date_expires'] != null &&
        DateTime.tryParse(coupon['date_expires'].toString())
                ?.isBefore(DateTime.now()) ==
            true;

    String desc;
    switch (type) {
      case 'percent':
        desc = '$amount% off';
        break;
      case 'fixed_product':
        desc = '\u00A3${double.tryParse(amount)?.toStringAsFixed(2) ?? amount} off products';
        break;
      default:
        desc = '\u00A3${double.tryParse(amount)?.toStringAsFixed(2) ?? amount} off cart';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: expired
            ? Border.all(color: AppColors.coralColor.withOpacity(0.3))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: expired
                  ? AppColors.coralColor.withOpacity(0.1)
                  : AppColors.goldColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (expired ? AppColors.coralColor : AppColors.goldColor)
                      .withOpacity(0.3),
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignInside),
            ),
            child: Icon(
              expired ? Icons.discount_outlined : Icons.discount,
              color: expired ? AppColors.coralColor : AppColors.goldColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code,
                    style: TextStyle(
                        color: expired ? AppColors.inkSoftColor : AppColors.inkColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        color: expired ? AppColors.inkSoftColor : AppColors.goldColor,
                        fontSize: 12)),
                const SizedBox(height: 2),
                Text('Used $usageCount${usageLimit != null ? ' of $usageLimit' : ''} times',
                    style: const TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 10)),
              ],
            ),
          ),
          if (expired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.coralColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Expired',
                  style: TextStyle(
                      color: AppColors.coralColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.inkSoftColor, size: 20),
            onSelected: (action) {
              if (action == 'edit') _openAddEditCoupon(coupon: coupon);
              if (action == 'delete') _confirmDelete(coupon, vendor);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit, color: AppColors.indigoColor, size: 18),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ])),
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: AppColors.coralColor, size: 18),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: AppColors.coralColor)),
                  ])),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> coupon, VendorProvider vendor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Coupon', style: TextStyle(fontWeight: FontWeight.w600)),
        content: Text('Delete coupon "${coupon['code']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.inkSoftColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await vendor.deleteCouponById(coupon['id'] as int);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Coupon deleted' : 'Failed to delete'),
                  backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coralColor,
              foregroundColor: AppColors.whiteColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openAddEditCoupon({Map<String, dynamic>? coupon}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => VendorAddEditCouponScreen(
        coupon: coupon,
        onSaved: () => context.read<VendorProvider>().loadCoupons(),
      ),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADD / EDIT COUPON SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class VendorAddEditCouponScreen extends StatefulWidget {
  final Map<String, dynamic>? coupon;
  final VoidCallback? onSaved;

  const VendorAddEditCouponScreen({super.key, this.coupon, this.onSaved});

  @override
  State<VendorAddEditCouponScreen> createState() =>
      _VendorAddEditCouponScreenState();
}

class _VendorAddEditCouponScreenState extends State<VendorAddEditCouponScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiService _api;
  bool _isSaving = false;
  bool _isEdit = false;

  final _codeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _minSpendCtrl = TextEditingController();
  final _maxSpendCtrl = TextEditingController();
  final _usageLimitCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();

  String _discountType = 'fixed_cart';
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _api = context.read<VendorProvider>().apiService;
    _isEdit = widget.coupon != null;
    if (widget.coupon != null) {
      final c = widget.coupon!;
      _codeCtrl.text = c['code']?.toString() ?? '';
      _amountCtrl.text = c['amount']?.toString() ?? '';
      _discountType = c['discount_type']?.toString() ?? 'fixed_cart';
      _minSpendCtrl.text = c['minimum_amount']?.toString() ?? '';
      _maxSpendCtrl.text = c['maximum_amount']?.toString() ?? '';
      _usageLimitCtrl.text = c['usage_limit']?.toString() ?? '';
      if (c['date_expires'] != null) {
        _expiryDate = DateTime.tryParse(c['date_expires'].toString());
        if (_expiryDate != null) {
          _expiryCtrl.text =
              '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}';
        }
      }
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _amountCtrl.dispose();
    _minSpendCtrl.dispose();
    _maxSpendCtrl.dispose();
    _usageLimitCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'code': _codeCtrl.text.trim(),
      'discount_type': _discountType,
      'amount': _amountCtrl.text.trim(),
    };

    if (_minSpendCtrl.text.isNotEmpty) {
      data['minimum_amount'] = _minSpendCtrl.text.trim();
    }
    if (_maxSpendCtrl.text.isNotEmpty) {
      data['maximum_amount'] = _maxSpendCtrl.text.trim();
    }
    if (_usageLimitCtrl.text.isNotEmpty) {
      data['usage_limit'] = int.tryParse(_usageLimitCtrl.text) ?? 0;
    }
    if (_expiryDate != null) {
      data['date_expires'] = _expiryDate!.toIso8601String();
    }

    bool success;
    if (_isEdit && widget.coupon != null) {
      success = await _api.updateCoupon(widget.coupon!['id'] as int, data);
    } else {
      final result = await _api.createCoupon(data);
      success = result != null;
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Coupon ${_isEdit ? "updated" : "created"}!' : 'Failed to save'),
        backgroundColor: success ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
      if (success) {
        widget.onSaved?.call();
        Navigator.pop(context);
      }
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
        title: Text(_isEdit ? 'Edit Coupon' : 'New Coupon',
            style: const TextStyle(
                color: AppColors.inkColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.goldColor))
                : const Text('Save',
                    style: TextStyle(
                        color: AppColors.goldColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('Basic'),
              const SizedBox(height: 12),
              _field(_codeCtrl, 'Coupon Code', required: true,
                  hint: 'e.g. SUMMER20'),
              const SizedBox(height: 10),
              _field(_amountCtrl, 'Amount', required: true,
                  keyboardType: TextInputType.number,
                  hint: _discountType == 'percent' ? 'Percentage' : 'Amount in \u00A3'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonFormField<String>(
                  value: _discountType,
                  decoration: const InputDecoration(
                    labelText: 'Discount Type',
                    labelStyle: TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fixed_cart', child: Text('Fixed Cart Discount')),
                    DropdownMenuItem(value: 'percent', child: Text('Percentage Discount')),
                    DropdownMenuItem(value: 'fixed_product', child: Text('Fixed Product Discount')),
                  ],
                  onChanged: (v) => setState(() => _discountType = v ?? 'fixed_cart'),
                ),
              ),

              const SizedBox(height: 20),
              _section('Usage Restrictions'),
              const SizedBox(height: 12),
              _field(_minSpendCtrl, 'Minimum Spend (\u00A3)',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(_maxSpendCtrl, 'Maximum Spend (\u00A3)',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(_usageLimitCtrl, 'Usage Limit',
                  keyboardType: TextInputType.number,
                  hint: 'Leave empty for unlimited'),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (picked != null) {
                    setState(() {
                      _expiryDate = picked;
                      _expiryCtrl.text =
                          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    });
                  }
                },
                child: AbsorbPointer(
                  child: _field(_expiryCtrl, 'Expiry Date',
                      hint: 'Tap to pick date'),
                ),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.whiteColor))
                      : Text(_isEdit ? 'Update Coupon' : 'Create Coupon',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Text(title,
        style: const TextStyle(
            color: AppColors.inkColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Fraunces'));
  }

  Widget _field(TextEditingController ctrl, String label,
      {int maxLines = 1,
      TextInputType? keyboardType,
      bool required = false,
      String? hint}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
        hintStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
        filled: true,
        fillColor: AppColors.whiteColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      style: const TextStyle(color: AppColors.inkColor, fontSize: 14),
    );
  }
}
