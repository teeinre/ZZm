import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class VendorRegisterScreen extends StatefulWidget {
  const VendorRegisterScreen({super.key});

  @override
  State<VendorRegisterScreen> createState() => _VendorRegisterScreenState();
}

class _VendorRegisterScreenState extends State<VendorRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step 1: Personal Info
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // Step 2: Store Info
  final _storeNameCtrl = TextEditingController();
  final _businessDescCtrl = TextEditingController();
  final _storeEmailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  // Step 3: Plan & Social
  final _socialFbCtrl = TextEditingController();
  final _socialIgCtrl = TextEditingController();
  final _socialTwCtrl = TextEditingController();
  String _selectedPlan = 'payg';
  bool _agreedTerms = false;
  bool _agreeMarketing = true;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    _storeNameCtrl.dispose();
    _businessDescCtrl.dispose();
    _storeEmailCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postcodeCtrl.dispose();
    _countryCtrl.dispose();
    _socialFbCtrl.dispose();
    _socialIgCtrl.dispose();
    _socialTwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms and conditions'),
            backgroundColor: AppColors.coralColor));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Step 1: Register as WooCommerce customer
      final customer = await _api.registerCustomer(
        email: _emailCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        username: _emailCtrl.text.trim().split('@').first,
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim(),
        billing: {
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'address_1': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _stateCtrl.text.trim(),
          'postcode': _postcodeCtrl.text.trim(),
          'country': _countryCtrl.text.trim(),
        },
        shipping: {
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'address_1': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _stateCtrl.text.trim(),
          'postcode': _postcodeCtrl.text.trim(),
          'country': _countryCtrl.text.trim(),
        },
      );

      if (customer == null) {
        if (mounted) {
          _showError('Failed to create account. Email may already be in use.');
        }
        return;
      }

      final userId = customer['id'] as int;

      // Step 2: Login with the new account
      final auth = context.read<AuthProvider>();
      await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);

      if (!auth.isAuthenticated) {
        if (mounted) _showError('Account created but login failed. Please sign in manually.');
        return;
      }

      // Step 3: Create Dokan vendor store
      final store = await _api.createVendorStore(
        userId: userId,
        storeName: _storeNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
        postcode: _postcodeCtrl.text.trim(),
        country: _countryCtrl.text.trim(),
        businessDescription: _businessDescCtrl.text.trim(),
        storeEmail: _storeEmailCtrl.text.trim().isEmpty
            ? _emailCtrl.text.trim()
            : _storeEmailCtrl.text.trim(),
        socialFb: _socialFbCtrl.text.trim(),
        socialIg: _socialIgCtrl.text.trim(),
        socialTw: _socialTwCtrl.text.trim(),
      );

      if (mounted) {
        setState(() => _isSubmitting = false);

        if (store != null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Vendor account created! Your store will be ready within 24 hours.'),
            backgroundColor: Color(0xFF10B981),
          ));
          Navigator.pop(context);
        } else {
          _showSuccess('Account created! Store setup pending admin review.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.coralColor));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF10B981)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.indigoDeepColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.whiteColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Become a Vendor',
            style: TextStyle(
                color: AppColors.whiteColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Step indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: AppColors.whiteColor,
              child: Row(
                children: List.generate(3, (i) {
                  final isActive = i <= _currentStep;
                  final isCurrent = i == _currentStep;
                  return Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.goldColor : AppColors.sandColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isActive
                                ? Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold))
                                : Icon(Icons.check,
                                    color: isCurrent
                                        ? AppColors.goldColor
                                        : AppColors.sandColor,
                                    size: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (i < 2) Expanded(
                          child: Container(
                            height: 2,
                            color: i < _currentStep
                                ? AppColors.goldColor
                                : AppColors.sandColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),

            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _currentStep == 0
                    ? _buildPersonalInfoStep()
                    : _currentStep == 1
                        ? _buildStoreInfoStep()
                        : _buildPlanStep(),
              ),
            ),

            // Bottom nav
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.whiteColor,
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            setState(() => _currentStep--),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.inkColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: AppColors.sandColor),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentStep < 2
                          ? () => setState(() => _currentStep++)
                          : _isSubmitting
                              ? null
                              : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldColor,
                        foregroundColor: AppColors.whiteColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_currentStep < 2 ? 'Continue' : 'Submit',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Personal Info ───

  Widget _buildPersonalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Personal Information',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 8),
        const Text('Create your vendor account',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _field(_firstNameCtrl, 'First Name', required: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_lastNameCtrl, 'Last Name', required: true)),
          ],
        ),
        const SizedBox(height: 14),
        _field(_emailCtrl, 'Email Address', required: true,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _field(_phoneCtrl, 'Phone Number', required: true,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 14),
        _field(_passwordCtrl, 'Password', required: true, obscure: true,
            validator: (v) => (v == null || v.length < 8)
                ? 'Password must be at least 8 characters'
                : null),
        const SizedBox(height: 14),
        _field(_confirmPassCtrl, 'Confirm Password', required: true,
            obscure: true,
            validator: (v) => v != _passwordCtrl.text
                ? 'Passwords do not match'
                : null),
      ],
    );
  }

  // ─── Step 2: Store Info ───

  Widget _buildStoreInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Store Information',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 8),
        const Text('Set up your store details',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        const SizedBox(height: 24),
        _field(_storeNameCtrl, 'Store / Business Name', required: true,
            hint: 'Your registered business name'),
        const SizedBox(height: 14),
        _field(_businessDescCtrl, 'Business Description', maxLines: 3,
            hint: 'What your business does, the problem it solves, and your target customers'),
        const SizedBox(height: 14),
        _field(_storeEmailCtrl, 'Store Email (optional)',
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 20),
        const Text('Store Address',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _field(_addressCtrl, 'Street Address', required: true),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(_cityCtrl, 'City', required: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_stateCtrl, 'State/Province')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(_postcodeCtrl, 'Postcode')),
            const SizedBox(width: 12),
            Expanded(child: _field(_countryCtrl, 'Country', hint: 'NG')),
          ],
        ),

        // Social links
        const SizedBox(height: 20),
        const Text('Social Links (Optional)',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _field(_socialFbCtrl, 'Facebook URL',
            hint: 'https://facebook.com/yourstore'),
        const SizedBox(height: 10),
        _field(_socialIgCtrl, 'Instagram URL',
            hint: 'https://instagram.com/yourstore'),
        const SizedBox(height: 10),
        _field(_socialTwCtrl, 'Twitter URL',
            hint: 'https://twitter.com/yourstore'),
      ],
    );
  }

  // ─── Step 3: Plan & Review ───

  Widget _buildPlanStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose Your Plan',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Fraunces')),
        const SizedBox(height: 8),
        const Text('Select the option that fits your business',
            style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
        const SizedBox(height: 20),

        // Pay-As-You-Sell
        GestureDetector(
          onTap: () => setState(() => _selectedPlan = 'payg'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _selectedPlan == 'payg'
                      ? AppColors.goldColor
                      : AppColors.sandColor,
                  width: _selectedPlan == 'payg' ? 2 : 1),
            ),
            child: Row(
              children: [
                Radio<String>(
                  value: 'payg',
                  groupValue: _selectedPlan,
                  activeColor: AppColors.goldColor,
                  onChanged: (v) => setState(() => _selectedPlan = v!),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pay-As-You-Sell',
                          style: TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Fraunces')),
                      const SizedBox(height: 4),
                      Text('\u00A380 one-off setup  \u2022  3% commission per sale',
                          style: TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 12)),
                      const SizedBox(height: 2),
                      const Text('Perfect for emerging vendors',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.inkSoftColor,
                              fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.goldColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Starter',
                      style: TextStyle(
                          color: AppColors.goldColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Branded Store
        GestureDetector(
          onTap: () => setState(() => _selectedPlan = 'branded'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _selectedPlan == 'branded'
                      ? AppColors.goldColor
                      : AppColors.sandColor,
                  width: _selectedPlan == 'branded' ? 2 : 1),
            ),
            child: Row(
              children: [
                Radio<String>(
                  value: 'branded',
                  groupValue: _selectedPlan,
                  activeColor: AppColors.goldColor,
                  onChanged: (v) => setState(() => _selectedPlan = v!),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Branded Store Subscription',
                          style: TextStyle(
                              color: AppColors.inkColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Fraunces')),
                      const SizedBox(height: 4),
                      Text('\u00A3250/year  \u2022  0% commission  \u2022  Full dashboard',
                          style: TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text('Custom URL, storefront & vendor dashboard',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.inkSoftColor,
                              fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Pro',
                      style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Benefits
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.goldColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.goldColor.withOpacity(0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Special Benefits for New Sellers',
                  style: TextStyle(
                      color: AppColors.goldColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 8),
              _benefitItem('No commission for your first 2 months'),
              _benefitItem('Free listing — no product listing charges'),
              _benefitItem('Free upload of 100+ products on sign-up'),
              _benefitItem('Free social media support bundle'),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Terms
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24, width: 24,
              child: Checkbox(
                value: _agreedTerms,
                activeColor: AppColors.goldColor,
                onChanged: (v) => setState(() => _agreedTerms = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'I agree to the Terms & Conditions and Privacy Policy. I understand my store will be reviewed and setup within 24 hours.',
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Shared helper: build a text field ───

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool obscure = false,
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkColor)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator ??
              (required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.whiteColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(color: AppColors.inkColor, fontSize: 14),
        ),
      ],
    );
  }

  Widget _benefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.goldColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.inkColor, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
