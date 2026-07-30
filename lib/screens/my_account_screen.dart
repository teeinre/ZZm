import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // User data
  Map<String, dynamic>? _wpUserData;
  Map<String, dynamic>? _wcCustomerData;
  int? _wcCustomerId;
  bool _isLoading = true;
  String? _errorMessage;

  // Orders
  List<Map<String, dynamic>> _orders = [];
  bool _isLoadingOrders = false;

  // Downloads
  List<Map<String, dynamic>> _downloads = [];
  bool _isLoadingDownloads = false;

  // Save state
  bool _isSaving = false;

  // Account edit controllers
  bool _isEditingAccount = false;
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  // Shipping edit state — all required WooCommerce fields
  bool _isEditingShipping = false;
  final _shipFirstNameCtrl = TextEditingController();
  final _shipLastNameCtrl = TextEditingController();
  final _shipCompanyCtrl = TextEditingController();
  final _shipAddress1Ctrl = TextEditingController();
  final _shipAddress2Ctrl = TextEditingController();
  final _shipCityCtrl = TextEditingController();
  final _shipStateCtrl = TextEditingController();
  final _shipPostcodeCtrl = TextEditingController();
  final _shipCountryCtrl = TextEditingController();

  // Billing edit state — all required WooCommerce fields
  bool _isEditingBilling = false;
  final _billFirstNameCtrl = TextEditingController();
  final _billLastNameCtrl = TextEditingController();
  final _billCompanyCtrl = TextEditingController();
  final _billAddress1Ctrl = TextEditingController();
  final _billAddress2Ctrl = TextEditingController();
  final _billCityCtrl = TextEditingController();
  final _billStateCtrl = TextEditingController();
  final _billPostcodeCtrl = TextEditingController();
  final _billCountryCtrl = TextEditingController();
  final _billPhoneCtrl = TextEditingController();
  final _billEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadCustomerData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _firstNameCtrl, _lastNameCtrl, _emailCtrl, _oldPasswordCtrl, _newPasswordCtrl,
      _shipFirstNameCtrl, _shipLastNameCtrl, _shipCompanyCtrl,
      _shipAddress1Ctrl, _shipAddress2Ctrl, _shipCityCtrl,
      _shipStateCtrl, _shipPostcodeCtrl, _shipCountryCtrl,
      _billFirstNameCtrl, _billLastNameCtrl, _billCompanyCtrl,
      _billAddress1Ctrl, _billAddress2Ctrl, _billCityCtrl,
      _billStateCtrl, _billPostcodeCtrl, _billCountryCtrl,
      _billPhoneCtrl, _billEmailCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadCustomerData() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated || auth.user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please sign in to view your account.';
        });
      }
      return;
    }

    try {
      final api = auth.apiService;
      final fallback = _buildFallbackUserData(auth);

      // ── Step 1: Get WordPress user data ──
      Map<String, dynamic>? wpUser;
      try {
        wpUser = await api.getCurrentWPUser();
      } catch (e) {
        debugPrint('[MyAccount] getCurrentWPUser failed: $e');
      }
      wpUser ??= await api.getVendorApiUser().catchError((e) {
        debugPrint('[MyAccount] getVendorApiUser failed: $e');
        return null;
      });
      wpUser ??= fallback;

      // ── Step 2: Get WC customer data (billing/shipping only available here) ──
      Map<String, dynamic>? wcCustomer;
      try {
        // Prefer lookup by WordPress user ID (most reliable)
        if (wpUser != null) {
          final wpUserId = (wpUser['id'] as int?) ?? auth.user?.id;
          if (wpUserId != null && wpUserId > 0) {
            wcCustomer = await api.getWCCustomerById(wpUserId.toString());
            if (wcCustomer != null) {
              debugPrint('[MyAccount] getWCCustomerById succeeded for userId=$wpUserId');
            }
          }
        }
        // Fall back to email lookup
        if (wcCustomer == null) {
          final email = wpUser?['email']?.toString() ?? '';
          if (email.isNotEmpty) {
            wcCustomer = await api.getWCCustomerByEmail(email);
            if (wcCustomer != null) {
              debugPrint('[MyAccount] getWCCustomerByEmail succeeded for $email');
            }
          }
        }
      } catch (e) {
        debugPrint('[MyAccount] WC customer lookup failed: $e');
      }
      if (wcCustomer == null) {
        try {
          wcCustomer = await api.getVendorApiCustomer().catchError((_) => null);
          if (wcCustomer != null) debugPrint('[MyAccount] getVendorApiCustomer succeeded');
        } catch (_) {}
      }

      // ── Step 3: Merge billing/shipping into wpUser ──
      // CRITICAL: Never clear _wcCustomerData with null — keep the previous data if the re-fetch fails.
      final oldWcData = _wcCustomerData;

      // If WC returned billing/shipping, inject them into wpUser so _populateControllers sees them
      if (wcCustomer != null && wpUser != null) {
        if (wcCustomer!['billing'] != null &&
            (wpUser!['billing'] == null || wpUser['billing'] is! Map || (wpUser['billing'] as Map).isEmpty)) {
          wpUser['billing'] = wcCustomer['billing'];
        }
        if (wcCustomer!['shipping'] != null &&
            (wpUser!['shipping'] == null || wpUser['shipping'] is! Map || (wpUser['shipping'] as Map).isEmpty)) {
          wpUser['shipping'] = wcCustomer['shipping'];
        }
      } else if (oldWcData != null && wpUser != null) {
        // WC re-fetch failed — restore billing/shipping from the previous successful fetch
        // so the user doesn't see their address data vanish after a save.
        debugPrint('[MyAccount] WC re-fetch failed — restoring previous billing/shipping from cache');
        if (oldWcData['billing'] != null && (wpUser['billing'] == null || wpUser['billing'] is! Map || (wpUser['billing'] as Map).isEmpty)) {
          wpUser['billing'] = oldWcData['billing'];
        }
        if (oldWcData['shipping'] != null && (wpUser['shipping'] == null || wpUser['shipping'] is! Map || (wpUser['shipping'] as Map).isEmpty)) {
          wpUser['shipping'] = oldWcData['shipping'];
        }
      }

      if (mounted) {
        setState(() {
          _wpUserData = wpUser;
          // NEVER overwrite _wcCustomerData with null — keep the last successful fetch
          if (wcCustomer != null) {
            _wcCustomerData = wcCustomer;
          }
          _wcCustomerId = (_wcCustomerData?['id'] as int?) ?? auth.user?.id;
          _isLoading = false;
          _populateControllers(wpUser!, _wcCustomerData);
        });
        _loadOrders();
        _loadDownloads();
      }
    } catch (e) {
      debugPrint('[MyAccount] _loadCustomerData fatal error: $e');
      if (mounted) {
        setState(() {
          // Preserve whatever billing/shipping we had from a previous successful fetch
          _wpUserData = _buildFallbackUserData(auth);
          _isLoading = false;
          if (_wpUserData != null) _populateControllers(_wpUserData!, _wcCustomerData);
        });
      }
    }
  }

  Map<String, dynamic> _buildFallbackUserData(AuthProvider auth) {
    final user = auth.user;
    return {
      'id': user?.id ?? 0,
      'first_name': user?.firstName ?? '',
      'last_name': user?.lastName ?? '',
      'email': user?.email ?? '',
      'username': user?.username ?? user?.email ?? '',
      'display_name': user?.fullName.isNotEmpty == true ? user!.fullName : (user?.username ?? user?.email ?? ''),
      'billing': _wcCustomerData?['billing'] as Map<String, dynamic>? ?? _wpUserData?['billing'] as Map<String, dynamic>? ?? {},
      'shipping': _wcCustomerData?['shipping'] as Map<String, dynamic>? ?? _wpUserData?['shipping'] as Map<String, dynamic>? ?? {},
    };
  }

  /// Populate all controllers from loaded data.
  void _populateControllers(Map<String, dynamic> wpUser, Map<String, dynamic>? wcCustomer) {
    _firstNameCtrl.text = wpUser['first_name']?.toString() ?? '';
    _lastNameCtrl.text = wpUser['last_name']?.toString() ?? '';
    _emailCtrl.text = wpUser['email']?.toString() ?? '';

    void fillCtrl(TextEditingController ctrl, Map<String, dynamic>? map, String key) {
      ctrl.text = map?[key]?.toString() ?? '';
    }

    final billing = (wcCustomer?['billing'] as Map<String, dynamic>?)
        ?? (wpUser['billing'] as Map<String, dynamic>?);
    if (billing != null) {
      fillCtrl(_billFirstNameCtrl, billing, 'first_name');
      fillCtrl(_billLastNameCtrl, billing, 'last_name');
      fillCtrl(_billCompanyCtrl, billing, 'company');
      fillCtrl(_billAddress1Ctrl, billing, 'address_1');
      fillCtrl(_billAddress2Ctrl, billing, 'address_2');
      fillCtrl(_billCityCtrl, billing, 'city');
      fillCtrl(_billStateCtrl, billing, 'state');
      fillCtrl(_billPostcodeCtrl, billing, 'postcode');
      fillCtrl(_billCountryCtrl, billing, 'country');
      fillCtrl(_billPhoneCtrl, billing, 'phone');
      fillCtrl(_billEmailCtrl, billing, 'email');
    }

    final shipping = (wcCustomer?['shipping'] as Map<String, dynamic>?)
        ?? (wpUser['shipping'] as Map<String, dynamic>?);
    if (shipping != null) {
      fillCtrl(_shipFirstNameCtrl, shipping, 'first_name');
      fillCtrl(_shipLastNameCtrl, shipping, 'last_name');
      fillCtrl(_shipCompanyCtrl, shipping, 'company');
      fillCtrl(_shipAddress1Ctrl, shipping, 'address_1');
      fillCtrl(_shipAddress2Ctrl, shipping, 'address_2');
      fillCtrl(_shipCityCtrl, shipping, 'city');
      fillCtrl(_shipStateCtrl, shipping, 'state');
      fillCtrl(_shipPostcodeCtrl, shipping, 'postcode');
      fillCtrl(_shipCountryCtrl, shipping, 'country');
    }
  }

  Future<void> _loadOrders() async {
    final auth = context.read<AuthProvider>();
    if (_wcCustomerId == null && auth.user?.id == null) return;

    setState(() => _isLoadingOrders = true);
    try {
      _orders = await auth.apiService.getVendorApiUserOrders(perPage: 50);
      if (_orders.isEmpty) {
        _orders = await auth.apiService.getUserOrders(_wcCustomerId ?? auth.user!.id);
      }
    } catch (_) {
      _orders = [];
    }
    if (mounted) setState(() => _isLoadingOrders = false);
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoadingDownloads = true);
    try {
      final api = context.read<AuthProvider>().apiService;
      // Fetch orders and extract downloadable items
      final orders = _orders.isEmpty
          ? await api.getVendorApiUserOrders(perPage: 50)
          : _orders;
      final downloads = <Map<String, dynamic>>[];
      for (final order in orders) {
        final items = order['line_items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final meta = item['meta_data'] as List<dynamic>? ?? [];
          bool isDownloadable = false;
          for (final m in meta) {
            if (m is Map && (m['key'] == '_downloadable' || m['key'] == 'is_downloadable')) {
              isDownloadable = m['value'] == 'yes' || m['value'] == true;
            }
          }
          if (isDownloadable || item['downloadable'] == true) {
            downloads.add({
              'product_name': item['name']?.toString() ?? 'Download',
              'product_id': item['product_id'],
              'order_id': order['id'],
              'order_date': order['date_created'],
              'download_url': item['download_url'] ?? '',
              'downloads_remaining': item['downloads_remaining'] ?? 'unlimited',
            });
          }
        }
      }
      if (mounted) _downloads = downloads;
    } catch (_) {
      _downloads = [];
    }
    if (mounted) setState(() => _isLoadingDownloads = false);
  }

  // ═══════════════════════════════════════════════════════════
  // SAVE METHODS
  // ═══════════════════════════════════════════════════════════

  Future<void> _saveAccountDetails() async {
    final auth = context.read<AuthProvider>();
    final userId = _wpUserData?['id'] as int? ?? auth.user?.id;
    if (userId == null || userId == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot identify your account. Please sign out and back in.'),
            backgroundColor: AppColors.coralColor),
        );
      }
      return;
    }

    // Capture before async gap
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final oldPassword = _oldPasswordCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text.trim();

    // If new password provided, old password is mandatory
    if (newPassword.isNotEmpty && oldPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your current password to set a new one.'),
            backgroundColor: AppColors.coralColor),
      );
      return;
    }

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
    };
    if (newPassword.isNotEmpty) {
      data['password'] = newPassword;
      data['old_password'] = oldPassword;
    }

    bool success = false;
    String? errorMsg;
    final api = auth.apiService;
    try {
      final response = await api.updateVendorApiUserRaw(data);
      if (response.containsKey('success') && response['success'] == true) {
        success = true;
      } else {
        errorMsg = response['error']?.toString();
      }
    } catch (_) {
      errorMsg = 'Server unreachable.';
    }

    if (!mounted) return;

    if (success) {
      final wpData = _wpUserData ?? <String, dynamic>{};
      wpData['first_name'] = firstName;
      wpData['last_name'] = lastName;
      wpData['email'] = email;
      _wpUserData = wpData;
      _oldPasswordCtrl.clear();
      _newPasswordCtrl.clear();
    }

    setState(() { _isSaving = false; _isEditingAccount = false; });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Profile updated' : (errorMsg ?? 'Update failed')),
        backgroundColor: success ? AppColors.goldColor : AppColors.coralColor,
        duration: const Duration(seconds: 3),
      ),
    );

    if (success) _loadCustomerData();
  }

  Future<void> _saveBillingAddress() async {
    setState(() => _isSaving = true);

    // Capture all values before async gap
    final billing = <String, String>{
      'first_name': _billFirstNameCtrl.text.trim(),
      'last_name': _billLastNameCtrl.text.trim(),
      'company': _billCompanyCtrl.text.trim(),
      'address_1': _billAddress1Ctrl.text.trim(),
      'address_2': _billAddress2Ctrl.text.trim(),
      'city': _billCityCtrl.text.trim(),
      'state': _billStateCtrl.text.trim(),
      'postcode': _billPostcodeCtrl.text.trim(),
      'country': _billCountryCtrl.text.trim(),
      'phone': _billPhoneCtrl.text.trim(),
      'email': _billEmailCtrl.text.trim(),
    };

    final api = context.read<AuthProvider>().apiService;
    final data = {'billing': billing};

    bool success = false;
    if (_wcCustomerId != null) {
      success = await api.updateCustomer(_wcCustomerId!, data);
    }
    if (!success) {
      success = await api.updateVendorApiCustomer(data);
    }

    if (!mounted) return;

    if (success) _updateLocalBilling(billing);

    setState(() { _isSaving = false; _isEditingBilling = false; });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Billing address updated' : 'Update failed'),
        backgroundColor: success ? AppColors.goldColor : AppColors.coralColor,
      ),
    );

    if (success) _loadCustomerData();
  }

  Future<void> _saveShippingAddress() async {
    setState(() => _isSaving = true);

    // Capture all values before async gap
    final shipping = <String, String>{
      'first_name': _shipFirstNameCtrl.text.trim(),
      'last_name': _shipLastNameCtrl.text.trim(),
      'company': _shipCompanyCtrl.text.trim(),
      'address_1': _shipAddress1Ctrl.text.trim(),
      'address_2': _shipAddress2Ctrl.text.trim(),
      'city': _shipCityCtrl.text.trim(),
      'state': _shipStateCtrl.text.trim(),
      'postcode': _shipPostcodeCtrl.text.trim(),
      'country': _shipCountryCtrl.text.trim(),
    };

    final api = context.read<AuthProvider>().apiService;
    final data = {'shipping': shipping};

    bool success = false;
    if (_wcCustomerId != null) {
      success = await api.updateCustomer(_wcCustomerId!, data);
    }
    if (!success) {
      success = await api.updateVendorApiCustomer(data);
    }

    if (!mounted) return;

    if (success) _updateLocalShipping(shipping);

    setState(() { _isSaving = false; _isEditingShipping = false; });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Shipping address updated' : 'Update failed'),
        backgroundColor: success ? AppColors.goldColor : AppColors.coralColor,
      ),
    );

    if (success) _loadCustomerData();
  }

  // ═══════════════════════════════════════════════════════════
  // OPTIMISTIC LOCAL UPDATES
  // ═══════════════════════════════════════════════════════════

  void _updateLocalBilling(Map<String, String> billing) {
    final wcData = _wcCustomerData ?? <String, dynamic>{};
    wcData['billing'] = billing;
    _wcCustomerData = wcData;

    final wpData = _wpUserData ?? <String, dynamic>{};
    wpData['billing'] = billing;
    _wpUserData = wpData;
  }

  void _updateLocalShipping(Map<String, String> shipping) {
    final wcData = _wcCustomerData ?? <String, dynamic>{};
    wcData['shipping'] = shipping;
    _wcCustomerData = wcData;

    final wpData = _wpUserData ?? <String, dynamic>{};
    wpData['shipping'] = shipping;
    _wpUserData = wpData;
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

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
          style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : _errorMessage != null
              ? _buildErrorView()
              : Column(
                  children: [
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDashboardTab(),
                          _buildOrdersTab(),
                          _buildDownloadsTab(),
                          _buildAddressesTab(),
                          _buildAccountDetailsTab(),
                        ],
                      ),
                    ),
                    _buildLogoutButton(),
                  ],
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_circle_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
        ],
      ),
    );
  }

  // ─── Tab Bar ───

  Widget _buildTabBar() {
    return Container(
      color: AppColors.whiteColor,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.goldColor,
        unselectedLabelColor: AppColors.inkSoftColor,
        indicatorColor: AppColors.goldColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Dashboard'),
          Tab(text: 'Orders'),
          Tab(text: 'Downloads'),
          Tab(text: 'Addresses'),
          Tab(text: 'Account Details'),
        ],
      ),
    );
  }

  // ─── Dashboard Tab ───

  Widget _buildDashboardTab() {
    final displayName = _wpUserData?['display_name']?.toString() ??
        _wpUserData?['username']?.toString() ?? 'Valued Customer';
    final firstName = _wpUserData?['first_name']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.indigoColor, AppColors.indigoDeepColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello ${firstName.isNotEmpty ? firstName : displayName.split(' ').first}',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Fraunces'),
                ),
                const SizedBox(height: 8),
                Text(
                  'From your account dashboard you can view recent orders, manage your addresses, and edit your account details.',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Quick links
          Row(
            children: [
              Expanded(child: _buildQuickLink(Icons.receipt_long_outlined, 'Orders', () => _tabController.animateTo(1))),
              const SizedBox(width: 12),
              Expanded(child: _buildQuickLink(Icons.location_on_outlined, 'Addresses', () => _tabController.animateTo(3))),
              const SizedBox(width: 12),
              Expanded(child: _buildQuickLink(Icons.person_outline, 'Account', () => _tabController.animateTo(4))),
            ],
          ),
          const SizedBox(height: 24),
          // Recent Orders
          const Text('Recent Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Fraunces', color: AppColors.inkColor)),
          const SizedBox(height: 12),
          if (_isLoadingOrders)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.goldColor)))
          else if (_orders.isEmpty)
            _buildEmptyCard('No orders yet', 'When you place an order, it will appear here.')
          else
            ..._orders.take(3).map((order) => _buildOrderCard(order)),
        ],
      ),
    );
  }

  Widget _buildQuickLink(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.indigoPaleColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.goldColor, size: 22),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: AppColors.goldColor.withOpacity(0.4)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
        ],
      ),
    );
  }

  // ─── Orders Tab ───

  Widget _buildOrdersTab() {
    if (_isLoadingOrders) {
      return const Center(child: CircularProgressIndicator(color: AppColors.goldColor));
    }
    if (_orders.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: _buildEmptyCard('No orders yet', 'Your order history will appear here.')));
    }
    return RefreshIndicator(
      color: AppColors.goldColor,
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildOrderCard(_orders[i]),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final id = order['id']?.toString() ?? '';
    final status = order['status']?.toString() ?? 'unknown';
    final date = order['date_created']?.toString() ?? '';
    final total = order['total']?.toString() ?? '0';
    final itemsCount = (order['line_items'] as List<dynamic>?)?.length ?? 0;

    String displayDate = date;
    if (date.length >= 10) displayDate = date.substring(0, 10);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.whiteColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.indigoPaleColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Order #$id', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inkColor)),
                    const SizedBox(width: 8),
                    _buildStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(displayDate, style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
                const SizedBox(height: 2),
                Text('$itemsCount item${itemsCount != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
              ],
            ),
          ),
          Text('£$total', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.goldColor)),
        ],
      ),
    );
  }

  // ─── Downloads Tab ───

  Widget _buildDownloadsTab() {
    if (_isLoadingDownloads) {
      return const Center(child: CircularProgressIndicator(color: AppColors.goldColor));
    }
    if (_downloads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildEmptyCard('No downloads available', 'Digital downloads from your purchases will appear here.'),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.goldColor,
      onRefresh: _loadDownloads,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _downloads.length,
        itemBuilder: (_, i) {
          final d = _downloads[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.download_outlined, color: AppColors.goldColor),
              title: Text(d['product_name']?.toString() ?? 'Download', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('Order #${d['order_id']}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoftColor)),
              trailing: Chip(
                label: Text(d['downloads_remaining']?.toString() ?? 'unlimited', style: const TextStyle(fontSize: 10)),
                backgroundColor: AppColors.indigoPaleColor,
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Addresses Tab ───

  Widget _buildAddressesTab() {
    final billing = (_wcCustomerData?['billing'] ?? _wpUserData?['billing']) as Map<String, dynamic>?;
    final shipping = (_wcCustomerData?['shipping'] ?? _wpUserData?['shipping']) as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildBillingCard(billing),
          const SizedBox(height: 16),
          _buildShippingCard(shipping),
        ],
      ),
    );
  }

  // ─── Billing Address Card ───

  Widget _buildBillingCard(Map<String, dynamic>? billing) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.goldColor, size: 20),
              const SizedBox(width: 10),
              const Text('Billing Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces', color: AppColors.inkColor)),
            ],
          ),
          const SizedBox(height: 12),
          if (!_isEditingBilling) ...[
            if (billing == null || (billing['address_1']?.toString().isEmpty == true && billing['city']?.toString().isEmpty == true))
              const Text('No billing address set.', style: TextStyle(fontSize: 14, color: AppColors.inkColor))
            else
              _buildAddressDisplay(billing),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isEditingBilling = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.goldColor, side: const BorderSide(color: AppColors.goldColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ] else ...[
            _buildTextField(controller: _billFirstNameCtrl, label: 'First Name'),
            _buildTextField(controller: _billLastNameCtrl, label: 'Last Name'),
            _buildTextField(controller: _billCompanyCtrl, label: 'Company (optional)'),
            _buildTextField(controller: _billAddress1Ctrl, label: 'Address Line 1'),
            _buildTextField(controller: _billAddress2Ctrl, label: 'Address Line 2 (optional)'),
            _buildTextField(controller: _billCityCtrl, label: 'City'),
            _buildTextField(controller: _billStateCtrl, label: 'State / County'),
            _buildTextField(controller: _billPostcodeCtrl, label: 'Postcode / ZIP'),
            _buildTextField(controller: _billCountryCtrl, label: 'Country'),
            _buildTextField(controller: _billPhoneCtrl, label: 'Phone', keyboardType: TextInputType.phone),
            _buildTextField(controller: _billEmailCtrl, label: 'Email', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _isSaving ? null : () => setState(() => _isEditingBilling = false), style: OutlinedButton.styleFrom(foregroundColor: AppColors.inkSoftColor, side: const BorderSide(color: AppColors.inkSoftColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: _isSaving ? null : _saveBillingAddress, style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldColor, foregroundColor: AppColors.whiteColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0), child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Shipping Address Card ───

  Widget _buildShippingCard(Map<String, dynamic>? shipping) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: AppColors.goldColor, size: 20),
              const SizedBox(width: 10),
              const Text('Shipping Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces', color: AppColors.inkColor)),
            ],
          ),
          const SizedBox(height: 12),
          if (!_isEditingShipping) ...[
            if (shipping == null || (shipping['address_1']?.toString().isEmpty == true && shipping['city']?.toString().isEmpty == true))
              const Text('No shipping address set.', style: TextStyle(fontSize: 14, color: AppColors.inkColor))
            else
              _buildAddressDisplay(shipping),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isEditingShipping = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.goldColor, side: const BorderSide(color: AppColors.goldColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ] else ...[
            _buildTextField(controller: _shipFirstNameCtrl, label: 'First Name'),
            _buildTextField(controller: _shipLastNameCtrl, label: 'Last Name'),
            _buildTextField(controller: _shipCompanyCtrl, label: 'Company (optional)'),
            _buildTextField(controller: _shipAddress1Ctrl, label: 'Address Line 1'),
            _buildTextField(controller: _shipAddress2Ctrl, label: 'Address Line 2 (optional)'),
            _buildTextField(controller: _shipCityCtrl, label: 'City'),
            _buildTextField(controller: _shipStateCtrl, label: 'State / County'),
            _buildTextField(controller: _shipPostcodeCtrl, label: 'Postcode / ZIP'),
            _buildTextField(controller: _shipCountryCtrl, label: 'Country'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _isSaving ? null : () => setState(() => _isEditingShipping = false), style: OutlinedButton.styleFrom(foregroundColor: AppColors.inkSoftColor, side: const BorderSide(color: AppColors.inkSoftColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: _isSaving ? null : _saveShippingAddress, style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldColor, foregroundColor: AppColors.whiteColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0), child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Display a non-editable address summary.
  Widget _buildAddressDisplay(Map<String, dynamic> addr) {
    final lines = <String>[];
    final company = addr['company']?.toString();
    if (company != null && company.isNotEmpty) lines.add(company);
    final fn = addr['first_name']?.toString();
    final ln = addr['last_name']?.toString();
    if (fn != null && fn.isNotEmpty || ln != null && ln.isNotEmpty) {
      lines.add('${fn ?? ''} ${ln ?? ''}'.trim());
    }
    final a1 = addr['address_1']?.toString();
    final a2 = addr['address_2']?.toString();
    if (a1 != null && a1.isNotEmpty) lines.add(a1);
    if (a2 != null && a2.isNotEmpty) lines.add(a2);
    final city = addr['city']?.toString();
    final state = addr['state']?.toString();
    final postcode = addr['postcode']?.toString();
    final loc = [city, state, postcode].where((e) => e != null && e.isNotEmpty).join(', ');
    if (loc.isNotEmpty) lines.add(loc);
    final country = addr['country']?.toString();
    if (country != null && country.isNotEmpty) lines.add(country);
    final phone = addr['phone']?.toString();
    if (phone != null && phone.isNotEmpty) lines.add('Phone: $phone');
    if (lines.isEmpty) return const Text('No details.', style: TextStyle(fontSize: 14, color: AppColors.inkSoftColor));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((l) => Text(l, style: const TextStyle(fontSize: 14, color: AppColors.inkColor, height: 1.5))).toList(),
    );
  }

  // ─── Account Details Tab ───

  Widget _buildAccountDetailsTab() {
    final data = _wpUserData;
    final displayName = data?['username']?.toString() ?? data?['display_name']?.toString() ?? '';
    final email = data?['email']?.toString() ?? '';
    final firstName = data?['first_name']?.toString() ?? '';
    final lastName = data?['last_name']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.whiteColor, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, color: AppColors.goldColor, size: 20),
                const SizedBox(width: 10),
                const Text('Account Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Fraunces', color: AppColors.inkColor)),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isEditingAccount) ...[
              _buildInfoRow('Username', displayName.isNotEmpty ? displayName : 'N/A'),
              _buildInfoRow('Email', email.isNotEmpty ? email : 'N/A'),
              _buildInfoRow('Display Name', (firstName.isNotEmpty || lastName.isNotEmpty) ? '$firstName $lastName'.trim() : 'N/A'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isEditingAccount = true),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Account Details'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.goldColor, side: const BorderSide(color: AppColors.goldColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ] else ...[
              _buildTextField(controller: _firstNameCtrl, label: 'First Name'),
              const SizedBox(height: 12),
              _buildTextField(controller: _lastNameCtrl, label: 'Last Name'),
              const SizedBox(height: 12),
              _buildTextField(controller: _emailCtrl, label: 'Email', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Change Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkColor)),
              ),
              _buildTextField(controller: _oldPasswordCtrl, label: 'Current Password', obscure: true),
              const SizedBox(height: 8),
              _buildTextField(controller: _newPasswordCtrl, label: 'New Password (leave blank to keep)', obscure: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: _isSaving ? null : () { setState(() => _isEditingAccount = false); _oldPasswordCtrl.clear(); _newPasswordCtrl.clear(); }, style: OutlinedButton.styleFrom(foregroundColor: AppColors.inkSoftColor, side: const BorderSide(color: AppColors.inkSoftColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _isSaving ? null : _saveAccountDetails, style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldColor, foregroundColor: AppColors.whiteColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0), child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Logout ───

  Widget _buildLogoutButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.creamColor,
        border: Border(top: BorderSide(color: AppColors.indigoPaleColor.withOpacity(0.5))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            context.read<AuthProvider>().logout();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
            Navigator.pop(context);
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Logout'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigoPaleColor, foregroundColor: AppColors.indigoColor, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: _orderStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _orderStatusColor(status))),
    );
  }

  Color _orderStatusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'processing': return Colors.blue;
      case 'pending': return Colors.orange;
      case 'on-hold': return Colors.amber;
      case 'cancelled': return Colors.red;
      case 'refunded': return Colors.grey;
      case 'failed': return Colors.red.shade900;
      default: return Colors.grey;
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 13, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.inkColor, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkSoftColor)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscure,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.creamColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.indigoPaleColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.goldColor, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
