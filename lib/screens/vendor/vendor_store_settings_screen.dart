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
  final _bankNameCtrl = TextEditingController();
  final _bankIbanCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _socialFbCtrl = TextEditingController();
  final _socialIgCtrl = TextEditingController();
  final _socialTwCtrl = TextEditingController();

  bool _storeOpen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final vendor = context.read<VendorProvider>();
    final info = vendor.storeInfo;
    if (info != null) {
      _storeNameCtrl.text = info['store_name']?.toString() ?? '';
      _phoneCtrl.text = info['phone']?.toString() ?? '';
      _emailCtrl.text = info['email']?.toString() ?? '';

      final addr = info['address'];
      if (addr is Map) {
        _street1Ctrl.text = addr['street_1']?.toString() ?? '';
        _street2Ctrl.text = addr['street_2']?.toString() ?? '';
        _cityCtrl.text = addr['city']?.toString() ?? '';
        _stateCtrl.text = addr['state']?.toString() ?? '';
        _postcodeCtrl.text = addr['zip']?.toString() ?? addr['postcode']?.toString() ?? '';
        _countryCtrl.text = addr['country']?.toString() ?? '';
      }

      _bankNameCtrl.text = info['bank_name']?.toString() ?? '';
      _bankIbanCtrl.text = info['bank_iban']?.toString() ?? '';
      _accountNameCtrl.text = info['company_name']?.toString() ?? '';

      final openClose = info['store_open_close'];
      if (openClose is Map) {
        _storeOpen = openClose['is_open'] == true || openClose['open'] == true;
      }

      final social = info['social'];
      if (social is Map) {
        _socialFbCtrl.text = social['fb']?.toString() ?? '';
        _socialIgCtrl.text = social['instagram']?.toString() ?? '';
        _socialTwCtrl.text = social['twitter']?.toString() ?? '';
      }

      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = {
      'store_name': _storeNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'address': {
        'street_1': _street1Ctrl.text.trim(),
        'street_2': _street2Ctrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'zip': _postcodeCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
      },
      'bank_name': _bankNameCtrl.text.trim(),
      'bank_iban': _bankIbanCtrl.text.trim(),
      'company_name': _accountNameCtrl.text.trim(),
      'store_open_close': {'is_open': _storeOpen},
      'social': {
        'fb': _socialFbCtrl.text.trim(),
        'instagram': _socialIgCtrl.text.trim(),
        'twitter': _socialTwCtrl.text.trim(),
      },
    };

    final api = context.read<VendorProvider>().apiService;
    final ok = await api.updateStoreSettings(data);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Settings saved' : 'Failed to save settings'),
        backgroundColor: ok ? const Color(0xFF10B981) : AppColors.coralColor,
      ));
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
