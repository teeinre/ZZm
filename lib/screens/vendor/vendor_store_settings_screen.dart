import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/vendor_provider.dart';

class VendorStoreSettingsScreen extends StatefulWidget {
  const VendorStoreSettingsScreen({super.key});

  @override
  State<VendorStoreSettingsScreen> createState() => _VendorStoreSettingsScreenState();
}

class _VendorStoreSettingsScreenState extends State<VendorStoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  final _storeNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _street1Ctrl = TextEditingController();
  final _street2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _companyIdCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankIbanCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _socialFbCtrl = TextEditingController();
  final _socialIgCtrl = TextEditingController();
  final _socialTwCtrl = TextEditingController();

  bool _storeOpen = true;
  bool _tncEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  void _loadSettings() async {
    var vendor = context.read<VendorProvider>();

    // If store info hasn't been loaded yet (dashboard still loading),
    // trigger a load and wait for it.
    if (vendor.storeInfo == null && vendor.vendorId != null && vendor.vendorId! > 0) {
      await vendor.loadStoreInfo(vendor.vendorId!);
      if (!mounted) return;
      vendor = context.read<VendorProvider>(); // get updated instance
    }

    final info = vendor.storeInfo;
    if (info != null) {
      // ── Basic fields (Dokan returns these as top-level keys) ──
      _storeNameCtrl.text = (info['store_name'] ?? info['shop_name'] ?? info['name'] ?? '').toString();
      _phoneCtrl.text = (info['phone'] ?? '').toString();
      _emailCtrl.text = (info['email'] ?? info['store_email'] ?? '').toString();

      // ── Address (Dokan nests this under 'address' or as flat fields) ──
      final addr = info['address'];
      if (addr is Map) {
        _street1Ctrl.text = (addr['street_1'] ?? addr['street1'] ?? addr['address'] ?? '').toString();
        _street2Ctrl.text = (addr['street_2'] ?? addr['street2'] ?? '').toString();
        _cityCtrl.text = (addr['city'] ?? '').toString();
        _stateCtrl.text = (addr['state'] ?? addr['province'] ?? '').toString();
        _postcodeCtrl.text = (addr['zip'] ?? addr['postcode'] ?? addr['postal_code'] ?? '').toString();
        _countryCtrl.text = (addr['country'] ?? '').toString();
      } else {
        // Flat field fallback
        _street1Ctrl.text = (info['address_street_1'] ?? info['street_1'] ?? '').toString();
        _cityCtrl.text = (info['address_city'] ?? info['city'] ?? '').toString();
        _postcodeCtrl.text = (info['address_zip'] ?? info['postcode'] ?? '').toString();
      }

      // ── Company details (Dokan saves to dokan_company_name/company_id_number/vat_number meta) ──
      _companyNameCtrl.text = (info['company_name'] ?? '').toString();
      _companyIdCtrl.text = (info['company_id_number'] ?? '').toString();
      _vatNumberCtrl.text = (info['vat_number'] ?? '').toString();

      // ── T&C toggle ──
      _tncEnabled = info['tnc_enabled'] == true || info['tnc_enabled'] == 'on';

      // ── Bank details (Dokan stores in 'payment' → 'bank' or as flat fields) ──
      final payment = info['payment'];
      Map<String, dynamic>? bank;
      if (payment is Map) {
        bank = payment['bank'] is Map ? Map<String, dynamic>.from(payment['bank']) : null;
      }
      _bankNameCtrl.text = (bank?['bank_name'] ?? info['bank_name'] ?? '').toString();
      _bankIbanCtrl.text = (bank?['iban'] ?? info['bank_iban'] ?? info['iban'] ?? '').toString();
      _accountNameCtrl.text = (bank?['ac_name'] ?? info['account_name'] ?? info['company_name'] ?? '').toString();

      // ── Store open/close ──
      final openClose = info['store_open_close'];
      if (openClose is Map) {
        _storeOpen = openClose['is_open'] == true || openClose['open'] == true;
      } else {
        // Dokan may return a simple boolean or string field
        final isOpen = info['store_open_close'] ?? info['open'] ?? info['is_open'];
        _storeOpen = isOpen == true || isOpen == 'yes' || isOpen == '1' || isOpen == 'open';
      }

      // ── Social links (Dokan nests under 'social' or as flat fields) ──
      final social = info['social'];
      if (social is Map) {
        _socialFbCtrl.text = (social['fb'] ?? social['facebook'] ?? '').toString();
        _socialIgCtrl.text = (social['instagram'] ?? social['ig'] ?? '').toString();
        _socialTwCtrl.text = (social['twitter'] ?? social['tw'] ?? '').toString();
      } else {
        _socialFbCtrl.text = (info['social_fb'] ?? info['facebook'] ?? '').toString();
        _socialIgCtrl.text = (info['social_instagram'] ?? info['instagram'] ?? '').toString();
        _socialTwCtrl.text = (info['social_twitter'] ?? info['twitter'] ?? '').toString();
      }

      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    // Data structured to match the vendor-bridge endpoint format
    // (nested payment.bank, payment.paypal, social, store_open_close)
    final data = {
      'store_name': _storeNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'company_name': _companyNameCtrl.text.trim(),
      'company_id_number': _companyIdCtrl.text.trim(),
      'vat_number': _vatNumberCtrl.text.trim(),
      'tnc_enabled': _tncEnabled,
      'address': {
        'street_1': _street1Ctrl.text.trim(),
        'street_2': _street2Ctrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'zip': _postcodeCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
      },
      'payment': {
        'bank': {
          'bank_name': _bankNameCtrl.text.trim(),
          'iban': _bankIbanCtrl.text.trim(),
          'ac_name': _accountNameCtrl.text.trim(),
        },
      },
      'store_open_close': {'is_open': _storeOpen},
      'social': {
        'fb': _socialFbCtrl.text.trim(),
        'instagram': _socialIgCtrl.text.trim(),
        'twitter': _socialTwCtrl.text.trim(),
      },
    };

    final api = context.read<VendorProvider>().apiService;
    // Try vendor bridge first, then vendor-api.php bypass (REST-blocked fallback)
    bool ok = await api.updateVendorBridgeStore(data);
    if (!ok) {
      ok = await api.updateVendorApiStore(data);
    }
    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) {
        // Reload store info so the form reflects saved values on next open
        final vendor = context.read<VendorProvider>();
        final vid = vendor.vendorId;
        if (vid != null && vid > 0) {
          await vendor.loadStoreInfo(vid);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Settings saved'),
            backgroundColor: Color(0xFF10B981),
          ));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save settings — check your connection'),
          backgroundColor: AppColors.coralColor,
        ));
      }
    }
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _street1Ctrl.dispose();
    _street2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postcodeCtrl.dispose();
    _countryCtrl.dispose();
    _companyNameCtrl.dispose();
    _companyIdCtrl.dispose();
    _vatNumberCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankIbanCtrl.dispose();
    _accountNameCtrl.dispose();
    _socialFbCtrl.dispose();
    _socialIgCtrl.dispose();
    _socialTwCtrl.dispose();
    super.dispose();
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
        title: const Text('Store Settings',
            style: TextStyle(
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
              _section('Store Information'),
              const SizedBox(height: 12),
              _field(_storeNameCtrl, 'Store Name', required: true),
              const SizedBox(height: 10),
              _field(_phoneCtrl, 'Phone', keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              _field(_emailCtrl, 'Email', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Store Open',
                    style: TextStyle(fontSize: 13, color: AppColors.inkColor)),
                subtitle: Text(_storeOpen ? 'Open for business' : 'Temporarily closed',
                    style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
                value: _storeOpen,
                activeColor: AppColors.goldColor,
                onChanged: (v) => setState(() => _storeOpen = v),
              ),

              const SizedBox(height: 20),
              _section('Company Details'),
              const SizedBox(height: 12),
              _field(_companyNameCtrl, 'Company Name'),
              const SizedBox(height: 10),
              _field(_companyIdCtrl, 'Company ID / EUID Number'),
              const SizedBox(height: 10),
              _field(_vatNumberCtrl, 'VAT / TAX ID'),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Terms & Conditions',
                    style: TextStyle(fontSize: 13, color: AppColors.inkColor)),
                subtitle: Text(_tncEnabled ? 'Show on store page' : 'Not shown',
                    style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
                value: _tncEnabled,
                activeColor: AppColors.goldColor,
                onChanged: (v) => setState(() => _tncEnabled = v),
              ),

              const SizedBox(height: 20),
              _section('Address'),
              const SizedBox(height: 12),
              _field(_street1Ctrl, 'Street Address'),
              const SizedBox(height: 10),
              _field(_street2Ctrl, 'Street Address 2'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_cityCtrl, 'City')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_stateCtrl, 'State/Province')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_postcodeCtrl, 'Postcode')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_countryCtrl, 'Country')),
                ],
              ),

              const SizedBox(height: 20),
              _section('Bank Details'),
              const SizedBox(height: 12),
              _field(_bankNameCtrl, 'Bank Name'),
              const SizedBox(height: 10),
              _field(_bankIbanCtrl, 'IBAN / Account Number'),
              const SizedBox(height: 10),
              _field(_accountNameCtrl, 'Account Holder Name'),

              const SizedBox(height: 20),
              _section('Social Links'),
              const SizedBox(height: 12),
              _field(_socialFbCtrl, 'Facebook URL'),
              const SizedBox(height: 10),
              _field(_socialIgCtrl, 'Instagram URL'),
              const SizedBox(height: 10),
              _field(_socialTwCtrl, 'Twitter URL'),

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
                      : const Text('Save Settings',
                          style: TextStyle(
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
      {int maxLines = 1, TextInputType? keyboardType, bool required = false}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12),
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
