import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/country_data.dart';
import '../widgets/brand_logo.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';
import 'order_detail_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final double total;

  const CheckoutScreen({super.key, required this.total});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  String _selectedPaymentMethod = '';
  bool _orderPlaced = false;
  int? _placedOrderId;
  bool _isLoadingGateways = true;
  bool _isLoggingIn = false;
  bool _isPlacingOrder = false;
  bool _sameAsShipping = true;

  // Login controllers
  final TextEditingController _loginUserCtrl = TextEditingController();
  final TextEditingController _loginPassCtrl = TextEditingController();

  // Shipping controllers
  final TextEditingController _shipFirstNameCtrl = TextEditingController();
  final TextEditingController _shipLastNameCtrl = TextEditingController();
  final TextEditingController _shipAddress1Ctrl = TextEditingController();
  final TextEditingController _shipAddress2Ctrl = TextEditingController();
  final TextEditingController _shipCityCtrl = TextEditingController();
  final TextEditingController _shipPostcodeCtrl = TextEditingController();

  // Shipping country/state as String (dropdowns)
  String _shipCountry = 'GB'; // default UK
  String _shipState = '';
  String _billCountry = 'GB';
  String _billState = '';
  bool _hasSavedAddress = false;
  String _oldShipCountry = ''; // to clear state on country change
  bool _showShippingForm = false;

  // Billing controllers
  final TextEditingController _billFirstNameCtrl = TextEditingController();
  final TextEditingController _billLastNameCtrl = TextEditingController();
  final TextEditingController _billAddress1Ctrl = TextEditingController();
  final TextEditingController _billAddress2Ctrl = TextEditingController();
  final TextEditingController _billCityCtrl = TextEditingController();
  final TextEditingController _billPostcodeCtrl = TextEditingController();
  final TextEditingController _billPhoneCtrl = TextEditingController();
  final TextEditingController _billEmailCtrl = TextEditingController();

  double _shippingCost = 0.0;
  List<Map<String, dynamic>> _paymentGateways = [];
  List<Map<String, dynamic>> _shippingMethods = [];

  @override
  void initState() {
    super.initState();
    // 1. First load user profile to populate shipping address
    // 2. Then load payment/shipping data with the address available
    _loadUserProfile().then((_) => _loadPaymentData()).catchError((_) => _loadPaymentData());
  }

  /// Recalculate shipping methods when the user changes their shipping address.
  Future<void> _refreshShippingMethods() async {
    final api = ApiService();
    final cart = context.read<CartProvider>();
    try {
      final Set<int> vendorIds = {};
      for (final item in cart.cartItems) {
        if (item.product.vendorId != null) {
          vendorIds.add(item.product.vendorId!);
        }
      }
      List<Map<String, dynamic>> shipping = [];
      if (vendorIds.isNotEmpty) {
        for (final vendorId in vendorIds) {
          final vendorMethods = await api.getVendorShippingMethods(vendorId);
          shipping.addAll(vendorMethods);
        }
      }
      shipping = await _filterEligibleShipping(api, shipping);
      if (mounted) {
        setState(() {
          _shippingMethods = shipping;
          if (_shippingMethods.isNotEmpty) {
            _shippingCost = double.tryParse(_shippingMethods.first['cost']?.toString() ?? '') ?? 0.0;
          } else {
            _shippingCost = 0.0;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPaymentData() async {
    final api = ApiService();
    final cart = context.read<CartProvider>();
    try {
      final gateways = await api.getPaymentGateways();

      // Fetch vendor-specific shipping methods based on cart products
      final Set<int> vendorIds = {};
      for (final item in cart.cartItems) {
        if (item.product.vendorId != null) {
          vendorIds.add(item.product.vendorId!);
        }
      }

      List<Map<String, dynamic>> shipping = [];
      if (vendorIds.isNotEmpty) {
        for (final vendorId in vendorIds) {
          final vendorMethods = await api.getVendorShippingMethods(vendorId);
          shipping.addAll(vendorMethods);
        }
      }

      // Validate against customer's shipping address if available
      shipping = await _filterEligibleShipping(api, shipping);

      if (mounted) {
        setState(() {
          _paymentGateways = gateways.where((g) => g['enabled'] == true).toList();
          if (_paymentGateways.isEmpty) {
            _paymentGateways = gateways;
          }
          _shippingMethods = shipping;
          if (_shippingMethods.isNotEmpty) {
            _shippingCost = double.tryParse(_shippingMethods.first['cost']?.toString() ?? '') ?? 0.0;
          }
          _selectedPaymentMethod = _paymentGateways.isNotEmpty ? _paymentGateways.first['id'] ?? '' : '';
          _isLoadingGateways = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentGateways = [];
          _shippingMethods = [];
          _selectedPaymentMethod = '';
          _isLoadingGateways = false;
        });
      }
    }
  }

  /// Filter shipping methods to only show those likely eligible for the
  /// customer's shipping address based on shipping zone geography.
  Future<List<Map<String, dynamic>>> _filterEligibleShipping(
    ApiService api,
    List<Map<String, dynamic>> methods,
  ) async {
    if (_shipCountry.isEmpty) return methods;

    try {
      final zones = await api.getShippingZones();
      final customerCountry = _shipCountry.trim().toLowerCase();

      if (zones.isEmpty) return methods;

      final matchingZoneIds = <int>{};
      for (final zone in zones) {
        final zoneLocations = zone['locations'] as List<dynamic>? ?? [];
        for (final loc in zoneLocations) {
          final locCode = loc['code']?.toString().toLowerCase() ?? '';
          if (locCode == customerCountry || locCode.startsWith(customerCountry)) {
            matchingZoneIds.add(zone['id'] as int);
            break;
          }
        }
      }

      if (matchingZoneIds.isNotEmpty) {
        // Keep methods that belong to matching zones or fallback ones
        final filtered = methods.where((m) {
          final zoneId = m['zone_id'] is int ? m['zone_id'] as int : null;
          // Keep methods with matching zone IDs or those without zone assignment (fallback)
          return zoneId == null || matchingZoneIds.contains(zoneId);
        }).toList();
        return filtered.isNotEmpty ? filtered : methods;
      }
    } catch (_) {}

    return methods;
  }

  Future<void> _loadUserProfile() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated || auth.user == null) return;
    final uid = auth.user!.id;
    if (uid <= 0) return;
    final user = auth.user!;

    try {
      final api = ApiService();
      final customer = await api.getCustomerData(uid);
      if (customer != null && mounted) {
        final billing = customer['billing'] as Map<String, dynamic>?;
        final shipping = customer['shipping'] as Map<String, dynamic>?;

        // Pre-fill shipping from customer shipping address
        if (shipping != null) {
          _shipFirstNameCtrl.text = _nonEmpty(shipping['first_name'], user.firstName);
          _shipLastNameCtrl.text = _nonEmpty(shipping['last_name'], user.lastName);
          _shipAddress1Ctrl.text = shipping['address_1']?.toString() ?? '';
          _shipAddress2Ctrl.text = shipping['address_2']?.toString() ?? '';
          _shipCityCtrl.text = shipping['city']?.toString() ?? '';
          _shipPostcodeCtrl.text = shipping['postcode']?.toString() ?? '';
          _shipCountry = shipping['country']?.toString() ?? 'GB';
          if (countryHasStates(_shipCountry)) {
            _shipState = shipping['state']?.toString() ?? '';
          }

          // Check if saved address has meaningful data
          final hasAddress = (_shipAddress1Ctrl.text.isNotEmpty &&
              _shipCityCtrl.text.isNotEmpty &&
              _shipCountry.isNotEmpty);
          _hasSavedAddress = hasAddress;
        } else {
          // No shipping on file — use account details
          _shipFirstNameCtrl.text = user.firstName ?? '';
          _shipLastNameCtrl.text = user.lastName ?? '';
        }

        // Pre-fill billing from customer billing address
        if (billing != null) {
          _billFirstNameCtrl.text = _nonEmpty(billing['first_name'], user.firstName);
          _billLastNameCtrl.text = _nonEmpty(billing['last_name'], user.lastName);
          _billAddress1Ctrl.text = billing['address_1']?.toString() ?? '';
          _billAddress2Ctrl.text = billing['address_2']?.toString() ?? '';
          _billCityCtrl.text = billing['city']?.toString() ?? '';
          _billPostcodeCtrl.text = billing['postcode']?.toString() ?? '';
          _billCountry = billing['country']?.toString() ?? 'GB';
          if (countryHasStates(_billCountry)) {
            _billState = billing['state']?.toString() ?? '';
          }
          _billPhoneCtrl.text = billing['phone']?.toString() ?? '';
          _billEmailCtrl.text = _nonEmpty(billing['email'], user.email);
        } else {
          // No billing on file — use account details
          _billFirstNameCtrl.text = user.firstName ?? '';
          _billLastNameCtrl.text = user.lastName ?? '';
          _billEmailCtrl.text = user.email;
        }

        // Cross-fill: if shipping still empty, copy from billing
        if (_shipFirstNameCtrl.text.isEmpty && _billFirstNameCtrl.text.isNotEmpty) {
          _shipFirstNameCtrl.text = _billFirstNameCtrl.text;
          _shipLastNameCtrl.text = _billLastNameCtrl.text;
        }
      }
    } catch (_) {
      // API call failed — still try to pre-fill from auth user
      if (mounted) {
        _billEmailCtrl.text = user.email;
        _billFirstNameCtrl.text = user.firstName ?? '';
        _billLastNameCtrl.text = user.lastName ?? '';
        _shipFirstNameCtrl.text = user.firstName ?? '';
        _shipLastNameCtrl.text = user.lastName ?? '';
      }
    }
  }

  /// Return [value] if non-empty, otherwise fall back to [fallback].
  String _nonEmpty(dynamic value, String? fallback) {
    final s = value?.toString() ?? '';
    return s.isNotEmpty ? s : (fallback ?? '');
  }

  @override
  void dispose() {
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _shipFirstNameCtrl.dispose();
    _shipLastNameCtrl.dispose();
    _shipAddress1Ctrl.dispose();
    _shipAddress2Ctrl.dispose();
    _shipCityCtrl.dispose();
    _shipPostcodeCtrl.dispose();
    _billFirstNameCtrl.dispose();
    _billLastNameCtrl.dispose();
    _billAddress1Ctrl.dispose();
    _billAddress2Ctrl.dispose();
    _billCityCtrl.dispose();
    _billPostcodeCtrl.dispose();
    _billPhoneCtrl.dispose();
    _billEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (_orderPlaced) {
      return _buildOrderConfirmation();
    }

    if (!authProvider.isAuthenticated) {
      return _buildLoginRequired(authProvider);
    }

    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const BrandLogo(height: 28),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Checkout',
                    style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Fraunces',
                    )),
                const SizedBox(height: 8),
                Text(
                  'Signed in as ${authProvider.user?.username ?? authProvider.user?.email}',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // ═══ STEP 1: SHIPPING ADDRESS ═══
                if (_hasSavedAddress && !_showShippingForm) ...[
                  _buildSavedAddressSummary(),
                ] else ...[
                  _buildShippingFields(),
                ],
                const SizedBox(height: 24),

                // ═══ STEP 2: SHIPPING METHOD ═══
                _buildShippingMethodSection(),
                const SizedBox(height: 24),

                // ═══ STEP 3: BILLING ADDRESS ═══
                _buildBillingStep(),
                const SizedBox(height: 24),

                // ═══ STEP 4: PAYMENT METHOD ═══
                _buildPaymentStep(),
                const SizedBox(height: 24),

                // ═══ STEP 5: PLACE ORDER ═══
                _buildPlaceOrderButton(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ LOGIN REQUIRED ═══

  Widget _buildLoginRequired(AuthProvider authProvider) {
    final nameCtrl = _loginUserCtrl;
    final passCtrl = _loginPassCtrl;
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const BrandLogo(height: 28),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: AppColors.goldColor),
                const SizedBox(height: 16),
                Text(
                  'Sign in to checkout',
                  style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Fraunces',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You need to be signed in to place an order.',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Username or Email',
                    filled: true,
                    fillColor: AppColors.whiteColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    filled: true,
                    fillColor: AppColors.whiteColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (authProvider.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    authProvider.errorMessage!,
                    style: const TextStyle(color: AppColors.coralColor, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoggingIn
                        ? null
                        : () async {
                            if (nameCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter your username/email and password')),
                              );
                              return;
                            }
                            setState(() => _isLoggingIn = true);
                            authProvider.clearError();
                            final success = await authProvider.login(
                              nameCtrl.text.trim(),
                              passCtrl.text,
                            );
                            if (mounted) {
                              setState(() => _isLoggingIn = false);
                              if (success) {
                                _loadUserProfile();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(authProvider.errorMessage ?? 'Login failed'),
                                    backgroundColor: AppColors.coralColor,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoggingIn
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign In & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ SAVED ADDRESS SUMMARY ═══

  Widget _buildSavedAddressSummary() {
    final countryName = countries[_shipCountry] ?? _shipCountry;
    final stateName = _shipState.isNotEmpty && countryHasStates(_shipCountry)
        ? '${getStatesForCountry(_shipCountry)[_shipState] ?? _shipState}, '
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Shipping Address',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.whiteColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.indigoPaleColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_shipFirstNameCtrl.text} ${_shipLastNameCtrl.text}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
              if (_shipAddress1Ctrl.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_shipAddress1Ctrl.text,
                    style: TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 14)),
              ],
              if (_shipAddress2Ctrl.text.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(_shipAddress2Ctrl.text,
                    style: TextStyle(
                        color: AppColors.inkSoftColor, fontSize: 14)),
              ],
              const SizedBox(height: 2),
              Text(
                '${_shipCityCtrl.text.isNotEmpty ? "${_shipCityCtrl.text}, " : ""}$stateName$countryName${_shipPostcodeCtrl.text.isNotEmpty ? " ${_shipPostcodeCtrl.text}" : ""}',
                style: TextStyle(
                    color: AppColors.inkSoftColor, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showShippingForm = true),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldColor,
                  side: BorderSide(color: AppColors.goldColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══ STEP 1: SHIPPING FIELDS ═══

  Widget _buildShippingFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Shipping Address',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _buildTextField(
              controller: _shipFirstNameCtrl,
              label: 'First Name',
              validator: (val) =>
                  val?.isEmpty ?? true ? 'Required' : null,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _buildTextField(
              controller: _shipLastNameCtrl,
              label: 'Last Name',
              validator: (val) =>
                  val?.isEmpty ?? true ? 'Required' : null,
            )),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _shipAddress1Ctrl,
          label: 'Address Line 1',
          validator: (val) => val?.isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _buildTextField(
            controller: _shipAddress2Ctrl,
            label: 'Address Line 2 (Optional)'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _buildTextField(
              controller: _shipCityCtrl,
              label: 'City',
              validator: (val) =>
                  val?.isEmpty ?? true ? 'Required' : null,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _buildTextField(
              controller: _shipPostcodeCtrl,
              label: 'Postcode',
              validator: (val) =>
                  val?.isEmpty ?? true ? 'Required' : null,
            )),
          ],
        ),
        const SizedBox(height: 16),
        _buildCountryDropdown(
          value: _shipCountry,
          label: 'Country',
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _oldShipCountry = _shipCountry;
              _shipCountry = val;
              if (_oldShipCountry != _shipCountry) {
                _shipState = '';
              }
            });
          },
          validator: (val) => val?.isEmpty ?? true ? 'Required' : null,
        ),
        if (countryHasStates(_shipCountry)) ...[
          const SizedBox(height: 16),
          _buildStateDropdown(
            value: _shipState,
            countryCode: _shipCountry,
            label: 'State / Province',
            onChanged: (val) {
              if (val != null) {
                setState(() => _shipState = val);
              }
            },
          ),
        ],
      ],
    );
  }

  // ═══ STEP 2: SHIPPING METHOD ═══

  Widget _buildShippingMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Shipping Method',
                style: TextStyle(
                    color: AppColors.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _refreshShippingMethods,
              child: const Icon(Icons.refresh,
                  size: 18, color: AppColors.indigoLightColor),
            ),
            const Spacer(),
            Text(
              'Rates by vendor zone',
              style: TextStyle(
                  color: AppColors.inkSoftColor.withOpacity(0.6),
                  fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_shippingMethods.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Loading shipping methods...',
                style: TextStyle(color: AppColors.inkSoftColor)),
          )
        else
          ..._shippingMethods.map((method) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildShippingOption(
                  method['title'] ?? 'Shipping',
                  double.tryParse(
                          method['cost']?.toString() ?? '0.0') ??
                      0.0,
                ),
              )),
      ],
    );
  }

  // ═══ STEP 3: BILLING ═══

  Widget _buildBillingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Billing Address',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        // "Same as shipping" toggle
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.indigoPaleColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _sameAsShipping,
                  activeColor: AppColors.goldColor,
                  onChanged: (v) => setState(() {
                    _sameAsShipping = v ?? false;
                    if (_sameAsShipping) {
                      _billFirstNameCtrl.text = _shipFirstNameCtrl.text;
                      _billLastNameCtrl.text = _shipLastNameCtrl.text;
                      _billAddress1Ctrl.text = _shipAddress1Ctrl.text;
                      _billAddress2Ctrl.text = _shipAddress2Ctrl.text;
                      _billCityCtrl.text = _shipCityCtrl.text;
                      _billPostcodeCtrl.text = _shipPostcodeCtrl.text;
                      _billCountry = _shipCountry;
                      _billState = _shipState;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Same as shipping address',
                    style:
                        TextStyle(color: AppColors.inkColor, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_sameAsShipping) ...[
          // Show summary when same as shipping
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.indigoPaleColor),
            ),
            child: Text(
              'Billing address same as shipping address.',
              style: TextStyle(
                  color: AppColors.inkSoftColor, fontSize: 14),
            ),
          ),
        ] else ...[
          // Show billing form
          _buildTextField(
            controller: _billEmailCtrl,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            validator: (val) =>
                val?.isEmpty ?? true ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _billPhoneCtrl,
            label: 'Phone',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildTextField(
                controller: _billFirstNameCtrl,
                label: 'First Name',
                validator: (val) =>
                    val?.isEmpty ?? true ? 'Required' : null,
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildTextField(
                controller: _billLastNameCtrl,
                label: 'Last Name',
                validator: (val) =>
                    val?.isEmpty ?? true ? 'Required' : null,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _billAddress1Ctrl,
            label: 'Address Line 1',
            validator: (val) =>
                val?.isEmpty ?? true ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _billAddress2Ctrl,
            label: 'Address Line 2 (Optional)',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildTextField(
                controller: _billCityCtrl,
                label: 'City',
                validator: (val) =>
                    val?.isEmpty ?? true ? 'Required' : null,
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildTextField(
                controller: _billPostcodeCtrl,
                label: 'Postcode',
                validator: (val) =>
                    val?.isEmpty ?? true ? 'Required' : null,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _buildCountryDropdown(
            value: _billCountry,
            label: 'Country',
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _billCountry = val;
                _billState = '';
              });
            },
            validator: (val) =>
                val?.isEmpty ?? true ? 'Required' : null,
          ),
          if (countryHasStates(_billCountry)) ...[
            const SizedBox(height: 16),
            _buildStateDropdown(
              value: _billState,
              countryCode: _billCountry,
              label: 'State / Province',
              onChanged: (val) {
                if (val != null) {
                  setState(() => _billState = val);
                }
              },
            ),
          ],
        ],
      ],
    );
  }

  // ═══ STEP 4: PAYMENT ═══

  Widget _buildPaymentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment',
            style: TextStyle(
                color: AppColors.inkColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (_isLoadingGateways)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.goldColor)),
          )
        else ...[
          ..._paymentGateways.map((gw) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPaymentMethod(
                  gw['title'] ?? gw['id'] ?? '',
                  _getIconForGateway(gw['id'] ?? ''),
                  gw['id'] ?? '',
                ),
              )),
          const SizedBox(height: 24),
          _buildOrderSummary(),
          const SizedBox(height: 8),
          const Text(
            'By placing this order you agree to our Terms & Conditions and Privacy Policy',
            style:
                TextStyle(fontSize: 12, color: AppColors.inkSoftColor),
          ),
        ],
      ],
    );
  }

  // ═══ STEP 5: PLACE ORDER BUTTON ═══

  Widget _buildPlaceOrderButton() {
    final grandTotal = widget.total + _shippingCost;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isPlacingOrder ? null : _handleContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldColor,
          foregroundColor: AppColors.whiteColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: _isPlacingOrder
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(
                'Place Order - £${grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _handleContinue() {
    if (_formKey.currentState!.validate()) {
      // If "same as shipping" is checked, sync billing from shipping
      if (_sameAsShipping) {
        _billFirstNameCtrl.text = _shipFirstNameCtrl.text;
        _billLastNameCtrl.text = _shipLastNameCtrl.text;
        _billAddress1Ctrl.text = _shipAddress1Ctrl.text;
        _billAddress2Ctrl.text = _shipAddress2Ctrl.text;
        _billCityCtrl.text = _shipCityCtrl.text;
        _billPostcodeCtrl.text = _shipPostcodeCtrl.text;
        _billCountry = _shipCountry;
        _billState = _shipState;
      }
      _placeOrder();
    }
  }

  Future<void> _placeOrder() async {
    setState(() => _isPlacingOrder = true);

    try {
      final cart = context.read<CartProvider>();
      final api = ApiService();

      // Sync billing from shipping if needed
      if (_sameAsShipping) {
        _billFirstNameCtrl.text = _shipFirstNameCtrl.text;
        _billLastNameCtrl.text = _shipLastNameCtrl.text;
        _billAddress1Ctrl.text = _shipAddress1Ctrl.text;
        _billAddress2Ctrl.text = _shipAddress2Ctrl.text;
        _billCityCtrl.text = _shipCityCtrl.text;
        _billPostcodeCtrl.text = _shipPostcodeCtrl.text;
        _billCountry = _shipCountry;
        _billState = _shipState;
      }

      final billing = {
        'first_name': _billFirstNameCtrl.text.trim(),
        'last_name': _billLastNameCtrl.text.trim(),
        'address_1': _billAddress1Ctrl.text.trim(),
        'address_2': _billAddress2Ctrl.text.trim(),
        'city': _billCityCtrl.text.trim(),
        'postcode': _billPostcodeCtrl.text.trim(),
        'country': _billCountry,
        'state': _billState,
        'email': _billEmailCtrl.text.trim(),
        'phone': _billPhoneCtrl.text.trim(),
      };

      final shipping = {
        'first_name': _shipFirstNameCtrl.text.trim(),
        'last_name': _shipLastNameCtrl.text.trim(),
        'address_1': _shipAddress1Ctrl.text.trim(),
        'address_2': _shipAddress2Ctrl.text.trim(),
        'city': _shipCityCtrl.text.trim(),
        'postcode': _shipPostcodeCtrl.text.trim(),
        'country': _shipCountry,
        'state': _shipState,
      };

      // ── Try Store API first (enables Dokan multi-vendor shipping split) ──
      final storeApiAvailable = await api.isStoreApiAvailable();
      if (storeApiAvailable) {
        final storeOrder = await _placeOrderViaStoreApi(api, cart, billing, shipping);
        if (storeOrder != null) {
          _handleOrderSuccess(storeOrder, cart, api);
          return;
        }
      }

      // ── Fallback: direct wc/v3 order creation with per-vendor shipping ──
      debugPrint('[Checkout] Store API unavailable or failed — using wc/v3 fallback.');
      final fallbackOrder = await _placeOrderViaWcApi(api, cart, billing, shipping);
      if (fallbackOrder != null) {
        _handleOrderSuccess(fallbackOrder, cart, api);
        return;
      }

      throw Exception('All checkout methods failed.');
    } catch (e) {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order error: ${e.toString()}'),
            backgroundColor: AppColors.coralColor,
          ),
        );
      }
    }
  }

  /// Place order via WooCommerce Store API (block-based checkout).
  /// This triggers Dokan's cart hooks for proper per-vendor shipping.
  Future<Map<String, dynamic>?> _placeOrderViaStoreApi(
    ApiService api,
    CartProvider cart,
    Map<String, dynamic> billing,
    Map<String, dynamic> shipping,
  ) async {
    // STEP 1: Fetch Store API nonce & cart token
    await api.fetchStoreNonce();

    // STEP 2: Build server-side cart from local cart items
    for (final item in cart.cartItems) {
      final result = await api.addToStoreCart(
        item.product.id,
        quantity: item.quantity,
        variationId: item.variationId != null && item.variationId!.isNotEmpty
            ? int.tryParse(item.variationId!)
            : null,
      );
      if (result == null) return null;
    }

    // STEP 3: Set customer shipping/billing address (triggers zone matching)
    final addressUpdated = await api.updateStoreCartCustomer(billing, shipping);
    if (!addressUpdated) return null;

    // STEP 4: Fetch cart to get Dokan multi-vendor shipping packages
    final storeCart = await api.getStoreCart();
    if (storeCart == null) return null;

    // STEP 5: Select shipping rate per package (Dokan splits by vendor)
    final shippingRates = storeCart['shipping_rates'] as List<dynamic>? ?? [];
    double totalShipping = 0.0;

    for (final pkg in shippingRates) {
      final packageId = pkg['package_id']?.toString() ?? '';
      final rates = pkg['shipping_rates'] as List<dynamic>? ?? [];
      if (rates.isEmpty || packageId.isEmpty) continue;

      // Auto-select the cheapest available rate per package
      Map<String, dynamic>? cheapest;
      double cheapestPrice = double.infinity;
      for (final rate in rates) {
        final price = double.tryParse(rate['price']?.toString() ?? '0') ?? 0;
        if (price < cheapestPrice) {
          cheapestPrice = price;
          cheapest = Map<String, dynamic>.from(rate);
        }
      }

      if (cheapest != null) {
        final rateId = cheapest['rate_id']?.toString() ?? '';
        if (rateId.isNotEmpty) {
          await api.selectStoreShippingRate(packageId, rateId);
          totalShipping += cheapestPrice;
        }
      }
    }

    _shippingCost = totalShipping;

    // STEP 6: Checkout via Store API
    final order = await api.storeCheckout(
      paymentMethod: _selectedPaymentMethod.isNotEmpty
          ? _selectedPaymentMethod
          : 'bacs',
    );

    return order;
  }

  /// Fallback: create order via wc/v3 REST API with Dokan vendor sub-orders.
  /// Since Store API and WC API don't trigger Dokan's order splitting from
  /// external clients, we manually create sub-orders linked to the parent
  /// with `_dokan_vendor_id` metadata so they appear in vendor dashboards.
  Future<Map<String, dynamic>?> _placeOrderViaWcApi(
    ApiService api,
    CartProvider cart,
    Map<String, dynamic> billing,
    Map<String, dynamic> shipping,
  ) async {
    final auth = context.read<AuthProvider>();

    // Group cart items by vendor to compute per-vendor shipping
    final vendorShipping = <int, double>{};
    double totalShipping = 0.0;

    for (final item in cart.cartItems) {
      if (item.product.vendorId != null && item.product.vendorId! > 0) {
        if (!vendorShipping.containsKey(item.product.vendorId)) {
          final methods = await api.getVendorShippingMethods(item.product.vendorId!);
          if (methods.isNotEmpty) {
            double cheapest = double.infinity;
            for (final m in methods) {
              final cost = double.tryParse(m['cost']?.toString() ?? '0') ?? 0;
              if (cost < cheapest) cheapest = cost;
            }
            vendorShipping[item.product.vendorId!] = cheapest == double.infinity ? 0 : cheapest;
            totalShipping += vendorShipping[item.product.vendorId!]!;
          }
        }
      }
    }

    _shippingCost = totalShipping;

    final lineItems = cart.cartItems.map((item) {
      final li = <String, dynamic>{
        'product_id': item.product.id,
        'quantity': item.quantity,
      };
      if (item.variationId != null && item.variationId!.isNotEmpty) {
        li['variation_id'] = int.tryParse(item.variationId!);
      }
      return li;
    }).toList();

    final shippingLines = _shippingCost > 0
        ? [
            {
              'method_id': 'flat_rate',
              'method_title': _shippingMethods.isNotEmpty
                  ? _shippingMethods.first['title'] ?? 'Standard Delivery'
                  : 'Standard Delivery',
              'total': _shippingCost.toString(),
            }
          ]
        : null;

    // ── Create parent order ──
    final parentOrder = await api.placeOrder(
      customerId: auth.user!.id,
      lineItems: lineItems,
      billing: billing,
      shipping: shipping,
      paymentMethod: _selectedPaymentMethod,
      paymentMethodTitle: _paymentGateways
              .firstWhere((g) => g['id'] == _selectedPaymentMethod,
                  orElse: () => {'title': 'Direct Bank Transfer'})['title']
              ?.toString() ??
          'Direct Bank Transfer',
      shippingLines: shippingLines,
    );

    if (parentOrder == null) return null;

    // ── Create per-vendor sub-orders (Dokan-compatible) ──
    final parentId = parentOrder['id'] as int;
    await _createVendorSubOrders(api, cart, billing, shipping, parentId);

    // Mark parent as having sub-orders
    await api.updateOrderMeta(parentId, {
      'has_sub_order': '1',
    });

    return parentOrder;
  }

  /// Create Dokan-compatible sub-orders for each vendor in the cart.
  Future<void> _createVendorSubOrders(
    ApiService api,
    CartProvider cart,
    Map<String, dynamic> billing,
    Map<String, dynamic> shipping,
    int parentId,
  ) async {
    final vendorItems = <int, List<CartItem>>{};
    for (final item in cart.cartItems) {
      final vid = item.product.vendorId ?? 0;
      vendorItems.putIfAbsent(vid, () => []).add(item);
    }

    for (final entry in vendorItems.entries) {
      final vendorId = entry.key;
      if (vendorId <= 0) continue;

      final items = entry.value;
      if (items.isEmpty) continue;
      
      final subLineItems = items.map((item) {
        final li = <String, dynamic>{
          'product_id': item.product.id,
          'quantity': item.quantity,
        };
        if (item.variationId != null && item.variationId!.isNotEmpty) {
          li['variation_id'] = int.tryParse(item.variationId!);
        }
        return li;
      }).toList();

      try {
        await api.createSubOrder(
          parentId: parentId,
          vendorId: vendorId,
          lineItems: subLineItems,
          billing: billing,
          shipping: shipping,
          paymentMethod: _selectedPaymentMethod,
          paymentMethodTitle: _paymentGateways
                  .firstWhere((g) => g['id'] == _selectedPaymentMethod,
                      orElse: () => {'title': 'Direct Bank Transfer'})['title']
                  ?.toString() ??
              'Direct Bank Transfer',
        );
      } catch (e) {
        debugPrint('[Checkout] Sub-order creation failed for vendor $vendorId: $e');
      }
    }
  }

  void _handleOrderSuccess(
    Map<String, dynamic> order,
    CartProvider cart,
    ApiService api,
  ) {
    if (!mounted) return;
    setState(() => _isPlacingOrder = false);

    final orderId = order['id'] as int?;
    setState(() {
      _orderPlaced = true;
      _placedOrderId = orderId;
    });
    cart.clearCart();
    api.clearStoreSession();
  }

  Widget _buildOrderConfirmation() {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandLogo(height: 48),
                const SizedBox(height: 32),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.goldColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(Icons.check_circle,
                        color: AppColors.goldColor, size: 56),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Order Confirmed!',
                    style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Fraunces',
                    )),
                const SizedBox(height: 12),
                const Text(
                    'Thank you for your order. Your order has been received and is now being processed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: AppColors.inkSoftColor)),
                const SizedBox(height: 32),
                if (_placedOrderId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                OrderDetailScreen(orderId: _placedOrderId!),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.indigoColor,
                        foregroundColor: AppColors.whiteColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      child: const Text('View Order Details',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    elevation: 0,
                  ),
                  child: const Text('Continue Shopping',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ REUSABLE WIDGETS ═══

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? hintText,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor:
                enabled ? AppColors.whiteColor : AppColors.indigoPaleColor,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.indigoPaleColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.goldColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountryDropdown({
    required String value,
    required String label,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    final sortedCountries = countries.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: countries.containsKey(value) ? value : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.whiteColor,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.indigoPaleColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.goldColor, width: 2),
            ),
          ),
          validator: validator,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppColors.inkSoftColor),
          dropdownColor: AppColors.whiteColor,
          style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 15,
              fontWeight: FontWeight.w500),
          items: sortedCountries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value,
                  overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildStateDropdown({
    required String value,
    required String countryCode,
    required String label,
    required ValueChanged<String?> onChanged,
  }) {
    final stateMap = getStatesForCountry(countryCode);
    final sortedStates = stateMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: stateMap.containsKey(value) ? value : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.whiteColor,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.indigoPaleColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.goldColor, width: 2),
            ),
          ),
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppColors.inkSoftColor),
          dropdownColor: AppColors.whiteColor,
          style: const TextStyle(
              color: AppColors.inkColor,
              fontSize: 15,
              fontWeight: FontWeight.w500),
          items: sortedStates.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value,
                  overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildShippingOption(String label, double cost) {
    return GestureDetector(
      onTap: () => setState(() => _shippingCost = cost),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _shippingCost == cost
                  ? AppColors.goldColor
                  : AppColors.indigoPaleColor,
              width: _shippingCost == cost ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            Text('£${cost.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppColors.goldColor,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethod(String label, IconData icon, String value) {
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _selectedPaymentMethod == value
                  ? AppColors.goldColor
                  : AppColors.indigoPaleColor,
              width: _selectedPaymentMethod == value ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: _selectedPaymentMethod == value
                    ? AppColors.goldColor
                    : AppColors.inkColor,
                size: 24),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            if (_selectedPaymentMethod == value)
              Icon(Icons.check_circle,
                  color: AppColors.goldColor, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final grandTotal = widget.total + _shippingCost;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal',
                  style: TextStyle(
                      color: AppColors.inkSoftColor, fontSize: 15)),
              Text('£${widget.total.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.inkColor, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shipping',
                  style: TextStyle(
                      color: AppColors.inkSoftColor, fontSize: 15)),
              Text('£${_shippingCost.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.inkColor, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: TextStyle(
                      color: AppColors.inkColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text('£${grandTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.goldColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getIconForGateway(String id) {
    switch (id) {
      case 'stripe':
        return Icons.credit_card;
      case 'paypal':
        return Icons.payment;
      case 'bacs':
        return Icons.account_balance;
      case 'cod':
        return Icons.money;
      default:
        return Icons.payment_outlined;
    }
  }
}
