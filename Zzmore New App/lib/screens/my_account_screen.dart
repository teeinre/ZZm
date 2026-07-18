import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  Map<String, dynamic>? _customerData;
  bool _isLoading = true;
  String? _errorMessage;

  // Account edit state
  bool _isEditingAccount = false;
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Shipping edit state
  bool _isEditingShipping = false;
  final _shipAddressCtrl = TextEditingController();
  final _shipCityCtrl = TextEditingController();
  final _shipPostcodeCtrl = TextEditingController();
  final _shipCountryCtrl = TextEditingController();

  // Billing edit state
  bool _isEditingBilling = false;
  final _billAddressCtrl = TextEditingController();
  final _billCityCtrl = TextEditingController();
  final _billPostcodeCtrl = TextEditingController();
  final _billCountryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id ?? 0;
    if (userId == 0) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please sign in to view your account.';
        });
      }
      return;
    }

    try {
      final api = ApiService();
      final data = await api.getCustomerData(userId);
      if (mounted) {
        setState(() {
          _customerData = data;
          _isLoading = false;
          if (data != null) {
            _populateControllers(data);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load account data.';
        });
      }
    }
  }

  void _populateControllers(Map<String, dynamic> data) {
    _firstNameCtrl.text = data['first_name']?.toString() ?? '';
    _lastNameCtrl.text = data['last_name']?.toString() ?? '';
    _emailCtrl.text = data['email']?.toString() ?? '';

    final shipping = data['shipping'] as Map<String, dynamic>?;
    if (shipping != null) {
      _shipAddressCtrl.text = shipping['address_1']?.toString() ?? '';
      _shipCityCtrl.text = shipping['city']?.toString() ?? '';
      _shipPostcodeCtrl.text = shipping['postcode']?.toString() ?? '';
      _shipCountryCtrl.text = shipping['country']?.toString() ?? '';
    }

    final billing = data['billing'] as Map<String, dynamic>?;
    if (billing != null) {
      _billAddressCtrl.text = billing['address_1']?.toString() ?? '';
      _billCityCtrl.text = billing['city']?.toString() ?? '';
      _billPostcodeCtrl.text = billing['postcode']?.toString() ?? '';
      _billCountryCtrl.text = billing['country']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _shipAddressCtrl.dispose();
    _shipCityCtrl.dispose();
    _shipPostcodeCtrl.dispose();
    _shipCountryCtrl.dispose();
    _billAddressCtrl.dispose();
    _billCityCtrl.dispose();
    _billPostcodeCtrl.dispose();
    _billCountryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Account',
          style: TextStyle(
            color: AppColors.inkColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldColor),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: AppColors.goldColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: const TextStyle(
                              color: AppColors.inkSoftColor, fontSize: 14)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccountDetailsCard(),
                      const SizedBox(height: 16),
                      _buildShippingAddressCard(),
                      const SizedBox(height: 16),
                      _buildBillingAddressCard(),
                      const SizedBox(height: 16),
                      _buildPaymentMethodsCard(),
                      const SizedBox(height: 16),
                      _buildSavedItemsCard(),
                      const SizedBox(height: 32),
                      _buildLogoutButton(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  // ─── Account Details Card ───
  Widget _buildAccountDetailsCard() {
    final data = _customerData;
    final displayName = data?['username']?.toString() ??
        data?['display_name']?.toString() ?? '';
    final email = data?['email']?.toString() ?? '';
    final firstName = data?['first_name']?.toString() ?? '';
    final lastName = data?['last_name']?.toString() ?? '';

    return _buildCard(
      title: 'Account Details',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEditingAccount) ...[
            _buildInfoRow('Username', displayName.isNotEmpty ? displayName : 'N/A'),
            const SizedBox(height: 8),
            _buildInfoRow('Email', email.isNotEmpty ? email : 'N/A'),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Display Name',
              (firstName.isNotEmpty || lastName.isNotEmpty)
                  ? '$firstName $lastName'.trim()
                  : 'N/A',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isEditingAccount = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldColor,
                  side: const BorderSide(color: AppColors.goldColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            _buildTextField(
              controller: _firstNameCtrl,
              label: 'First Name',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _lastNameCtrl,
              label: 'Last Name',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailCtrl,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditingAccount = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.inkSoftColor,
                      side: const BorderSide(color: AppColors.inkSoftColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _isEditingAccount = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Profile updated (demo)')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Shipping Address Card ───
  Widget _buildShippingAddressCard() {
    final shipping = _customerData?['shipping'] as Map<String, dynamic>?;
    final hasAddress = shipping != null &&
        (shipping['address_1']?.toString().isNotEmpty == true);

    String displayAddress() {
      if (!hasAddress) return 'No shipping address saved.';
      final parts = <String>[
        if (shipping!['address_1']?.toString().isNotEmpty == true)
          shipping['address_1']!,
        if (shipping['address_2']?.toString().isNotEmpty == true)
          shipping['address_2']!,
        if (shipping['city']?.toString().isNotEmpty == true)
          shipping['city']!,
        if (shipping['postcode']?.toString().isNotEmpty == true)
          shipping['postcode']!,
        if (shipping['country']?.toString().isNotEmpty == true)
          shipping['country']!,
      ];
      return parts.join(', ');
    }

    return _buildCard(
      title: 'Shipping Address',
      icon: Icons.local_shipping_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEditingShipping) ...[
            Text(
              displayAddress(),
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isEditingShipping = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldColor,
                  side: const BorderSide(color: AppColors.goldColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            _buildTextField(
              controller: _shipAddressCtrl,
              label: 'Address',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _shipCityCtrl,
              label: 'City',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _shipPostcodeCtrl,
                    label: 'Postcode',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _shipCountryCtrl,
                    label: 'Country',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditingShipping = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.inkSoftColor,
                      side: const BorderSide(color: AppColors.inkSoftColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _isEditingShipping = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Shipping address updated (demo)')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Billing Address Card ───
  Widget _buildBillingAddressCard() {
    final billing = _customerData?['billing'] as Map<String, dynamic>?;
    final hasAddress = billing != null &&
        (billing['address_1']?.toString().isNotEmpty == true);

    String displayAddress() {
      if (!hasAddress) return 'No billing address saved.';
      final parts = <String>[
        if (billing!['address_1']?.toString().isNotEmpty == true)
          billing['address_1']!,
        if (billing['address_2']?.toString().isNotEmpty == true)
          billing['address_2']!,
        if (billing['city']?.toString().isNotEmpty == true) billing['city']!,
        if (billing['postcode']?.toString().isNotEmpty == true)
          billing['postcode']!,
        if (billing['country']?.toString().isNotEmpty == true)
          billing['country']!,
      ];
      return parts.join(', ');
    }

    return _buildCard(
      title: 'Billing Address',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEditingBilling) ...[
            Text(
              displayAddress(),
              style: const TextStyle(
                color: AppColors.inkColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isEditingBilling = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldColor,
                  side: const BorderSide(color: AppColors.goldColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            _buildTextField(
              controller: _billAddressCtrl,
              label: 'Address',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _billCityCtrl,
              label: 'City',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _billPostcodeCtrl,
                    label: 'Postcode',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _billCountryCtrl,
                    label: 'Country',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditingBilling = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.inkSoftColor,
                      side: const BorderSide(color: AppColors.inkSoftColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _isEditingBilling = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Billing address updated (demo)')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Payment Methods Card ───
  Widget _buildPaymentMethodsCard() {
    return _buildCard(
      title: 'Payment Methods',
      icon: Icons.credit_card_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.credit_card,
                  color: AppColors.goldColor.withOpacity(0.5), size: 40),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No saved payment methods',
                      style: TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add a payment method for faster checkout.',
                      style: TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Payment method management coming soon.')),
                );
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Payment Method'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.goldColor,
                side: const BorderSide(color: AppColors.goldColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Saved / Wishlist Items Card ───
  Widget _buildSavedItemsCard() {
    return _buildCard(
      title: 'Saved & Wishlist',
      icon: Icons.favorite_border,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.favorite_border,
                  color: AppColors.goldColor.withOpacity(0.5), size: 40),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your wishlist is empty',
                      style: TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Save items you love and come back to them anytime.',
                      style: TextStyle(
                        color: AppColors.inkSoftColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Browse products to add to your wishlist.')),
                );
              },
              icon: const Icon(Icons.explore_outlined, size: 16),
              label: const Text('Browse Products'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.goldColor,
                side: const BorderSide(color: AppColors.goldColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Logout Button ───
  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          context.read<AuthProvider>().logout();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Signed out')),
          );
          Navigator.pop(context);
        },
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.indigoPaleColor,
          foregroundColor: AppColors.indigoColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // ─── Reusable Card Builder ───
  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.goldColor, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Fraunces',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ─── Info Row ───
  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Text Field Builder ───
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.inkSoftColor,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.creamColor,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.indigoPaleColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.goldColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
