import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/currency_provider.dart';
import '../services/api_service.dart';
import 'order_success_screen.dart';
import 'profile_screen.dart';

/// Native Store API checkout with auth gate, auto-login, and guest checkout.
///
/// Entry behavior:
///   1. If authenticated → pre-fill customer data from user profile, proceed
///   2. If guest → show auth gate: Login / Register / Continue as Guest
///   3. Guest checkout: collects email for order tracking, no WP account needed
///
/// Flow:
///   1. fetchStoreNonce() to get a WooCommerce cart session
///   2. addToStoreCart() for each local cart item
///   3. getStoreCart() to pull totals, shipping packages, payment methods
///   4. User fills billing address and selects shipping/payment
///   5. updateStoreCartCustomer() + storeCheckout() to place the order
///   6. On success → clear local cart → navigate to OrderSuccessScreen
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _CheckoutMode { authenticated, guest, authGate }

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Cart state from server ──
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _totals = {};
  List<Map<String, dynamic>> _shippingPackages = [];
  List<Map<String, dynamic>> _paymentMethods = [];
  Map<String, dynamic> _billing = {};
  Map<String, dynamic> _shipping = {};

  // ── Selected values ──
  String? _selectedPayment;
  final Map<String, String> _selectedRates = {};

  // ── Address controllers ──
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'NG');

  // ── UI state ──
  _CheckoutMode _mode = _CheckoutMode.authGate;
  bool _loading = true;
  bool _placingOrder = false;
  String? _error;

  ApiService get _api => context.read<AuthProvider>().apiService;
  String get _currency => context.watch<CurrencyProvider>().currencySymbol;
  AuthProvider get _auth => context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAuthAndInit());
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postcodeCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  // ── AUTH GATE ──

  /// Determine auth state and either proceed or show auth gate.
  void _resolveAuthAndInit() {
    if (_auth.isAuthenticated) {
      _mode = _CheckoutMode.authenticated;
      _initCheckout();
    } else {
      _mode = _CheckoutMode.authGate;
      _loading = false;
      setState(() {});
    }
  }

  /// User chose to log in first. Navigate to login, then re-resolve.
  Future<void> _loginFirst() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (mounted && _auth.isAuthenticated) {
      _resolveAuthAndInit();
    }
  }

  Future<void> _goToRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
    if (mounted && _auth.isAuthenticated) {
      _resolveAuthAndInit();
    }
  }

  /// User chose guest checkout — proceed without authentication.
  void _continueAsGuest() {
    _mode = _CheckoutMode.guest;
    _loading = true;
    setState(() {});
    _initCheckout();
  }

  // ── INIT ──

  Future<void> _initCheckout() async {
    setState(() { _loading = true; _error = null; });

    final cart = context.read<CartProvider>();
    final localItems = cart.cartItems;

    if (localItems.isEmpty) {
      setState(() { _loading = false; _error = 'Your cart is empty.'; });
      return;
    }

    try {
      // Step 0: Verify Store API is available
      debugPrint('[Checkout] Step 0: check Store API availability');
      final storeApiAvailable = await _api.isStoreApiAvailable();
      if (!storeApiAvailable) {
        setState(() {
          _loading = false;
          _error = 'Store API is not available. Make sure WooCommerce is up to date (v8.0+) '
              'and the Store API is not disabled.';
        });
        return;
      }

      // Step 1: Establish session (auto-login: if authenticated, the JWT token
      // is already set on the ApiService, so Store API will see the user identity.)
      debugPrint('[Checkout] Step 1: fetch nonce (mode=${_mode.name})');
      await _api.fetchStoreNonce();

      debugPrint('[Checkout] Step 2: add ${localItems.length} items');
      int added = 0;
      final failedItems = <String>[];
      for (final item in localItems) {
        final vid = item.variationId != null && item.variationId!.isNotEmpty
            ? int.tryParse(item.variationId!)
            : null;
        try {
          final result = await _api.addToStoreCart(
            item.product.id,
            quantity: item.quantity,
            variationId: vid,
          );
          if (result != null) {
            added++;
          } else {
            failedItems.add(item.product.name);
          }
        } catch (_) {
          failedItems.add(item.product.name);
        }
      }

      if (added == 0) {
        final detail = failedItems.isNotEmpty
            ? ' Failed items: ${failedItems.join(', ')}.'
            : '';
        setState(() {
          _loading = false;
          _error = 'Could not sync cart to server.$detail\n\n'
              'This may happen if products are missing variation data or the store API is misconfigured.';
        });
        return;
      }

      if (failedItems.isNotEmpty) {
        debugPrint('[Checkout] Warning: ${failedItems.length} items failed: ${failedItems.join(', ')}');
      }

      debugPrint('[Checkout] Step 3: fetch cart');
      final cartData = await _api.getStoreCart();
      if (cartData == null) {
        setState(() {
          _loading = false;
          _error = 'Could not load checkout. Check your connection and try again.';
        });
        return;
      }

      _parseCart(cartData);
      setState(() { _loading = false; });
    } catch (e) {
      debugPrint('[Checkout] Init failed: $e');
      setState(() {
        _loading = false;
        _error = 'Could not start checkout: ${e.toString()}\n\n'
            'Please check your internet connection and try again.';
      });
    }
  }

  void _parseCart(Map<String, dynamic> cart) {
    _items = (cart['items'] as List<dynamic>?)
        ?.map((i) => Map<String, dynamic>.from(i))
        .toList() ?? [];
    _totals = Map<String, dynamic>.from(cart['totals'] ?? {});

    final packages = cart['shipping_rates'] as List<dynamic>?;
    _shippingPackages = packages?.map((p) => Map<String, dynamic>.from(p)).toList() ?? [];

    final payments = cart['payment_methods'] as List<dynamic>?;
    _paymentMethods = payments?.map((p) => Map<String, dynamic>.from(p)).toList() ?? [];
    if (_paymentMethods.isNotEmpty) {
      _selectedPayment = _paymentMethods.first['id']?.toString();
    }

    _billing = Map<String, dynamic>.from(cart['billing_address'] ?? {});
    _shipping = Map<String, dynamic>.from(cart['shipping_address'] ?? {});

    // Pre-fill address from auth provider (registered user) or billing data
    if (_mode == _CheckoutMode.authenticated) {
      final user = _auth.user;
      _firstNameCtrl.text = _billing['first_name']?.toString() ?? user?.firstName ?? user?.username?.split(' ').first ?? '';
      _lastNameCtrl.text = _billing['last_name']?.toString() ?? user?.lastName ?? '';
      _emailCtrl.text = _billing['email']?.toString() ?? user?.email ?? '';
      _phoneCtrl.text = _billing['phone']?.toString() ?? '';
    } else {
      // Guest: pre-fill from any existing billing data, but email must be entered
      _firstNameCtrl.text = _billing['first_name']?.toString() ?? '';
      _lastNameCtrl.text = _billing['last_name']?.toString() ?? '';
      _emailCtrl.text = _billing['email']?.toString() ?? '';
      _phoneCtrl.text = _billing['phone']?.toString() ?? '';
    }
    _addressCtrl.text = _billing['address_1']?.toString() ?? '';
    _cityCtrl.text = _billing['city']?.toString() ?? '';
    _postcodeCtrl.text = _billing['postcode']?.toString() ?? '';
  }

  // ── AUTH GATE UI ──

  Widget _buildAuthGate() {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Checkout',
            style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.indigoPaleColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.shopping_bag_outlined, size: 36, color: AppColors.indigoColor),
              ),
              const SizedBox(height: 24),
              const Text('Ready to Checkout',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
              const SizedBox(height: 8),
              Text('Log in to use your saved addresses and track your order history.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
              const SizedBox(height: 32),

              // Primary: Login
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loginFirst,
                  icon: const Icon(Icons.login, size: 20),
                  label: const Text('Log In to Checkout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Secondary: Create account
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _goToRegister,
                  icon: const Icon(Icons.person_add_outlined, size: 20),
                  label: const Text('Create an Account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.indigoColor,
                    side: const BorderSide(color: AppColors.indigoColor),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),

              // Tertiary: Guest checkout
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _continueAsGuest,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                  label: const Text('Continue as Guest'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.inkSoftColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Order tracking will be linked to your email address.',
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ──

  @override
  Widget build(BuildContext context) {
    // Show auth gate if not authenticated and not yet chosen guest
    if (_mode == _CheckoutMode.authGate && !_loading) {
      return _buildAuthGate();
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.creamColor,
        appBar: AppBar(
          backgroundColor: AppColors.whiteColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Checkout',
              style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.goldColor)),
      );
    }

    if (_error != null) {
      return _buildErrorView();
    }

    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Checkout',
                style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.w600, fontFamily: 'Fraunces', fontSize: 16)),
            Text(_mode == _CheckoutMode.guest ? 'Guest checkout' : 'Signed in',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11)),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Guest notice banner
            if (_mode == _CheckoutMode.guest) _buildGuestNotice(),
            if (_mode == _CheckoutMode.guest) const SizedBox(height: 12),
            _buildOrderSummary(),
            const SizedBox(height: 20),
            _buildAddressForm(),
            const SizedBox(height: 20),
            if (_shippingPackages.isNotEmpty) ...[
              _buildShippingRates(),
              const SizedBox(height: 20),
            ],
            _buildPaymentMethods(),
            const SizedBox(height: 24),
            _buildTotals(),
            const SizedBox(height: 20),
            _buildPlaceOrderButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.indigoPaleColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.indigoColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.indigoColor, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Guest checkout — your order will be linked to your email. '
              'Create an account to save addresses and track orders.',
              style: TextStyle(fontSize: 12, color: AppColors.indigoColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.whiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Checkout',
            style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.w600, fontFamily: 'Fraunces')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.inkSoftColor),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkColor, fontSize: 15)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initCheckout,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ORDER SUMMARY ──

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Summary (${_items.length} item${_items.length == 1 ? '' : 's'})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
          const SizedBox(height: 12),
          ..._items.map((item) => _buildOrderItem(item)),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final qty = item['quantity'] ?? 1;
    final prices = item['prices'] as Map<String, dynamic>?;
    final total = prices?['price']?.toString() ?? '0';
    final images = item['images'] as List<dynamic>?;
    final imageUrl = images != null && images.isNotEmpty
        ? (images[0] is Map ? (images[0] as Map)['src']?.toString() : images[0]?.toString())
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imageUrl, width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 48, height: 48, color: AppColors.indigoPaleColor)),
            )
          else
            Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.indigoPaleColor, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.shopping_bag, color: AppColors.inkSoftColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('Qty: $qty', style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
              ],
            ),
          ),
          Text('$_currency${_parsePrice(total)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
        ],
      ),
    );
  }

  // ── ADDRESS ──

  Widget _buildAddressForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shipping Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _textField('First Name *', _firstNameCtrl)),
              const SizedBox(width: 10),
              Expanded(child: _textField('Last Name *', _lastNameCtrl)),
            ],
          ),
          const SizedBox(height: 10),
          _textField('Email *', _emailCtrl, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _textField('Phone *', _phoneCtrl, keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _textField('Address *', _addressCtrl),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _textField('City *', _cityCtrl)),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: _textField('Postcode *', _postcodeCtrl)),
            ],
          ),
          const SizedBox(height: 10),
          _textField('Country', _countryCtrl),
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: label.contains('*') ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor),
        filled: true, fillColor: AppColors.creamColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  // ── SHIPPING ──

  Widget _buildShippingRates() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shipping',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
          const SizedBox(height: 12),
          ..._shippingPackages.map((pkg) {
            final pkgId = pkg['package_id']?.toString() ?? '';
            final pkgName = pkg['name']?.toString() ?? 'Shipping Package';
            final rates = (pkg['shipping_rates'] as List<dynamic>?)
                ?.map((r) => Map<String, dynamic>.from(r))
                .toList() ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_shippingPackages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(pkgName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.indigoColor)),
                  ),
                ...rates.map((rate) {
                  final rateId = rate['rate_id']?.toString() ?? '';
                  final label = rate['name']?.toString() ?? rateId;
                  final cost = rate['price']?.toString() ?? '0';
                  final key = '$pkgId|$rateId';
                  final selected = _selectedRates[pkgId] == rateId;

                  return RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('$_currency${_parsePrice(cost)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.goldColor, fontWeight: FontWeight.w600)),
                    value: key,
                    groupValue: selected ? key : null,
                    activeColor: AppColors.goldColor,
                    onChanged: (v) {
                      if (v != null) {
                        final parts = v.split('|');
                        final pId = parts[0];
                        final rId = parts.sublist(1).join('|');
                        setState(() => _selectedRates[pId] = rId);
                      }
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── PAYMENT ──

  Widget _buildPaymentMethods() {
    if (_paymentMethods.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Method',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Fraunces', color: AppColors.inkColor)),
          const SizedBox(height: 8),
          ..._paymentMethods.map((method) {
            final id = method['id']?.toString() ?? '';
            final title = method['title']?.toString() ?? id;
            final desc = method['description']?.toString() ?? '';
            return RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(title, style: const TextStyle(fontSize: 13)),
              subtitle: desc.isNotEmpty ? Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.inkSoftColor)) : null,
              value: id,
              groupValue: _selectedPayment,
              activeColor: AppColors.goldColor,
              onChanged: (v) => setState(() => _selectedPayment = v),
            );
          }),
        ],
      ),
    );
  }

  // ── TOTALS ──

  Widget _buildTotals() {
    final itemsTotal = _totals['total_items']?.toString() ?? '0';
    final shippingTotal = _totals['total_shipping']?.toString() ?? '0';
    final taxTotal = _totals['total_tax']?.toString() ?? '0';
    final discount = _totals['total_discount']?.toString() ?? '0';
    final grandTotal = _totals['total_price']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _totalRow('Subtotal', '$_currency${_parsePrice(itemsTotal)}'),
          if ((double.tryParse(discount) ?? 0) > 0)
            _totalRow('Discount', '-$_currency${_parsePrice(discount)}', color: const Color(0xFF10B981)),
          _totalRow('Shipping', '$_currency${_parsePrice(shippingTotal)}'),
          if ((double.tryParse(taxTotal) ?? 0) > 0)
            _totalRow('Tax', '$_currency${_parsePrice(taxTotal)}'),
          const Divider(),
          _totalRow('Total', '$_currency${_parsePrice(grandTotal)}', isBold: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: color ?? AppColors.inkSoftColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400)),
          Text(value, style: TextStyle(fontSize: 14, color: color ?? AppColors.inkColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  // ── PLACE ORDER ──

  Widget _buildPlaceOrderButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _placingOrder ? null : _placeOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldColor,
          foregroundColor: AppColors.whiteColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: AppColors.goldColor.withValues(alpha: 0.5),
        ),
        child: _placingOrder
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Place Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate shipping rates selected
    for (final pkg in _shippingPackages) {
      final pkgId = pkg['package_id']?.toString() ?? '';
      final rates = (pkg['shipping_rates'] as List<dynamic>?) ?? [];
      if (rates.isNotEmpty && _selectedRates[pkgId] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a shipping method for all packages.')),
        );
        return;
      }
    }

    if (_selectedPayment == null && _paymentMethods.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method.')),
      );
      return;
    }

    setState(() => _placingOrder = true);

    try {
      debugPrint('[Checkout] Selecting shipping rates...');
      for (final pkg in _shippingPackages) {
        final pkgId = pkg['package_id']?.toString() ?? '';
        final rateId = _selectedRates[pkgId];
        if (rateId != null) {
          await _api.selectStoreShippingRate(pkgId, rateId);
        }
      }

      debugPrint('[Checkout] Updating customer...');
      final billing = {
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address_1': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'postcode': _postcodeCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
      };

      // For authenticated users, pass customer_id to link the order to their account
      if (_mode == _CheckoutMode.authenticated && _auth.user != null) {
        billing['customer_id'] = _auth.user!.id.toString();
      }

      await _api.updateStoreCartCustomer(billing, billing);

      debugPrint('[Checkout] Placing order...');
      final result = await _api.storeCheckout(
        paymentMethod: _selectedPayment ?? 'bacs',
      );

      if (result != null) {
        final orderId = result['id']?.toString() ?? '';
        final orderTotal = result['total']?.toString() ?? _totals['total_price']?.toString() ?? '0.00';
        final orderEmail = _emailCtrl.text.trim();
        final isGuest = _mode == _CheckoutMode.guest;

        // Clear local cart
        await context.read<CartProvider>().clearCart();

        if (mounted) {
          // Navigate to order success screen, removing checkout from stack
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OrderSuccessScreen(
                orderId: orderId,
                total: orderTotal,
                isGuest: isGuest,
                email: orderEmail,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _placingOrder = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order could not be placed. Please check your details and try again.'),
              backgroundColor: AppColors.coralColor,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Checkout] Place order failed: $e');
      if (mounted) {
        setState(() => _placingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: AppColors.coralColor,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: AppColors.whiteColor,
              onPressed: _placeOrder,
            ),
          ),
        );
      }
    }
  }

  String _parsePrice(String value) {
    final d = double.tryParse(value) ?? 0;
    if (d == d.roundToDouble()) return d.toStringAsFixed(0);
    return d.toStringAsFixed(2);
  }
}
