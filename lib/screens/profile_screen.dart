import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'main_screen.dart';
import 'vendor/vendor_dashboard_screen.dart';
import 'auth/vendor_register_screen.dart';
import 'auth/forgot_password_screen.dart';
import 'my_account_screen.dart';
import 'order_detail_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(context, authProvider),
                    const SizedBox(height: 24),
                    ...[
                      {'icon': Icons.inventory_2_outlined, 'label': 'Your orders', 'route': 'orders'},
                      {'icon': Icons.favorite_border, 'label': 'Saved vendors', 'route': 'saved'},
                      {'icon': Icons.credit_card_outlined, 'label': 'Payment methods', 'route': 'payment'},
                      {'icon': Icons.person_outline, 'label': 'My Account', 'route': 'my_account'},
                      {'icon': Icons.settings_outlined, 'label': 'Settings', 'route': 'settings'},
                      // Vendor Dashboard for verified vendor accounts
                      if (authProvider.isVendor)
                        {'icon': Icons.dashboard_outlined, 'label': 'Vendor Dashboard', 'route': 'vendor_dashboard'},
                    ].map((item) => _buildMenuItem(context, item)),
                    const SizedBox(height: 24),
                    if (authProvider.isAuthenticated)
                      _buildLogoutButton(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AuthProvider authProvider) {
    final displayName = authProvider.isAuthenticated && authProvider.user != null
        ? (authProvider.user!.username ?? (authProvider.user!.fullName.isNotEmpty ? authProvider.user!.fullName : authProvider.user!.email))
        : null;
    final email = authProvider.isAuthenticated
        ? authProvider.user!.email
        : null;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.indigoColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              displayName != null && displayName.isNotEmpty
                  ? displayName[0].toUpperCase()
                  : 'G',
              style: const TextStyle(color: AppColors.goldColor, fontSize: 20, fontWeight: FontWeight.w600, fontFamily: 'Fraunces'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName != null && displayName.isNotEmpty ? displayName : 'Guest Shopper',
                style: const TextStyle(color: AppColors.inkColor, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'Fraunces'),
              ),
              const SizedBox(height: 4),
              Text(
                email ?? 'Sign in to see your profile',
                style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 11),
              ),
            ],
          ),
        ),
        if (!authProvider.isAuthenticated)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                child: Text('Register', style: TextStyle(color: AppColors.indigoColor, fontWeight: FontWeight.w500, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                child: Text('Sign In', style: TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMenuItem(BuildContext context, Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () => _handleMenuTap(context, item['route'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(item['icon'] as IconData, color: AppColors.indigoColor, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item['label'] as String,
                  style: const TextStyle(color: AppColors.inkColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.inkSoftColor, size: 18),
          ],
        ),
      ),
    );
  }

  void _handleMenuTap(BuildContext context, String route) {
    final auth = context.read<AuthProvider>();
    switch (route) {
      case 'settings':
        MainScreen.innerNavigatorOf(context, 3)?.push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
      case 'orders':
        if (auth.isAuthenticated && auth.user != null) {
          MainScreen.innerNavigatorOf(context, 3)?.push(
            MaterialPageRoute(builder: (_) => OrdersPage(userId: auth.user!.id)),
          );
        } else {
          _showInfoSheet(context, 'Sign In Required', 'Please sign in to view your orders.');
        }
        break;
      case 'saved':
        if (auth.isAuthenticated) {
          MainScreen.innerNavigatorOf(context, 3)?.push(
            MaterialPageRoute(builder: (_) => const SavedVendorsPage()),
          );
        } else {
          _showInfoSheet(context, 'Sign In Required', 'Please sign in to save your favorite vendors.');
        }
        break;
      case 'payment':
        MainScreen.innerNavigatorOf(context, 3)?.push(
          MaterialPageRoute(builder: (_) => const PaymentMethodsPage()),
        );
        break;
      case 'my_account':
        if (auth.isAuthenticated) {
          MainScreen.innerNavigatorOf(context, 3)?.push(
            MaterialPageRoute(builder: (_) => const MyAccountScreen()),
          );
        } else {
          _showInfoSheet(context, 'Sign In Required', 'Please sign in to manage your account.');
        }
        break;
      case 'vendor_dashboard':
        if (!auth.isVendor) {
          _showInfoSheet(context, 'Access Denied', 'You are not a vendor. Only vendor accounts should have access to the vendor dashboard.');
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VendorDashboardScreen()),
          );
        }
        break;
    }
  }

  void _showInfoSheet(BuildContext context, String title, String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.goldColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.info_outline, color: AppColors.goldColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.inkColor)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoftColor)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldColor,
                foregroundColor: AppColors.whiteColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('Got it'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Login and Register are now full-screen pages, not popups

  Widget _buildLogoutButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        context.read<AuthProvider>().logout();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out')),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.indigoPaleColor,
        foregroundColor: AppColors.indigoColor,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
      ),
      child: const Text('Logout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Settings Page ───
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _emailOffers = true;

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
        title: const Text('Settings', style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildSectionTitle('Notifications'),
          SwitchListTile(
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
            title: const Text('Push Notifications'),
            activeColor: AppColors.goldColor,
          ),
          SwitchListTile(
            value: _emailOffers,
            onChanged: (val) => setState(() => _emailOffers = val),
            title: const Text('Email Offers'),
            activeColor: AppColors.goldColor,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: const TextStyle(
        color: AppColors.inkSoftColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      )),
    );
  }
}

// ─── Orders Page ───
class OrdersPage extends StatefulWidget {
  final int userId;
  const OrdersPage({super.key, required this.userId});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final api = ApiService();
      final orders = await api.getUserOrders(widget.userId);
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'processing': return AppColors.goldColor;
      case 'cancelled': return AppColors.coralColor;
      case 'pending': return AppColors.indigoLightColor;
      default: return AppColors.inkSoftColor;
    }
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
        title: const Text('Your Orders', style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text('No orders yet', style: TextStyle(color: AppColors.inkSoftColor)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    final status = order['status']?.toString() ?? 'unknown';
                    final total = order['total']?.toString() ?? '0.00';
                    final date = order['date_created']?.toString()?.substring(0, 10) ?? '';
                    final orderNum = order['number']?.toString() ?? '#${order['id']}';
                    final orderId = order['id'] as int?;
                    return GestureDetector(
                      onTap: orderId != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailScreen(orderId: orderId),
                                ),
                              );
                            }
                          : null,
                      child: Card(
                        color: AppColors.whiteColor,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text('Order $orderNum',
                                        style: const TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(status,
                                        style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('Date: $date', style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('Total: £${double.tryParse(total)?.toStringAsFixed(2) ?? total}',
                                      style: const TextStyle(color: AppColors.goldColor, fontSize: 14, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  const Icon(Icons.chevron_right, color: AppColors.inkSoftColor, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Saved Vendors Page ───
class SavedVendorsPage extends StatefulWidget {
  const SavedVendorsPage({super.key});

  @override
  State<SavedVendorsPage> createState() => _SavedVendorsPageState();
}

class _SavedVendorsPageState extends State<SavedVendorsPage> {
  List<Map<String, dynamic>> _vendors = [];
  bool _isLoading = true;

  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadSavedVendors();
  }

  Future<void> _loadSavedVendors() async {
    try {
      final savedIds = await _storage.getSavedVendorIds();
      if (savedIds.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final api = ApiService();
      final List<Map<String, dynamic>> vendors = [];
      for (final id in savedIds) {
        try {
          final store = await api.getDokanStore(id);
          if (store != null) vendors.add(store);
        } catch (_) {
          // Skip vendors that fail to load (store may have been deleted)
        }
      }

      if (mounted) {
        setState(() {
          _vendors = vendors;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[SavedVendors] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
        title: const Text('Saved Vendors', style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldColor))
          : _vendors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text('No saved vendors yet', style: TextStyle(color: AppColors.inkSoftColor)),
                      const SizedBox(height: 8),
                      const Text('Vendors you follow will appear here', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _vendors.length,
                  itemBuilder: (context, index) {
                    final vendor = _vendors[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.whiteColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.goldColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.store, color: AppColors.goldColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(vendor['store_name']?.toString() ?? 'Vendor',
                                    style: const TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(vendor['address']?['city']?.toString() ?? '',
                                    style: const TextStyle(color: AppColors.inkSoftColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.inkSoftColor),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Payment Methods Page ───
class PaymentMethodsPage extends StatelessWidget {
  const PaymentMethodsPage({super.key});

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
        title: const Text('Payment Methods', style: TextStyle(color: AppColors.inkColor, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.credit_card_outlined, size: 64, color: AppColors.goldColor.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('No saved payment methods', style: TextStyle(color: AppColors.inkSoftColor)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment method linking coming soon. Pay at checkout.')),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Payment Method'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldColor,
                foregroundColor: AppColors.whiteColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Login Page (Full Screen) ───
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isVendorLogin = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.inkColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.goldColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_outline, color: AppColors.goldColor, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              Text('Welcome back',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.inkColor, fontFamily: 'Fraunces')),
              const SizedBox(height: 8),
              Text(_isVendorLogin ? 'Sign in to your Vendor Dashboard' : 'Sign in to your ZZmore Store account',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
              const SizedBox(height: 32),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Username or Email',
                        prefixIcon: const Icon(Icons.email_outlined,
                            color: AppColors.inkSoftColor),
                        filled: true,
                        fillColor: AppColors.whiteColor,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) {
                        TextInput.finishAutofillContext();
                        _handleLogin();
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined,
                            color: AppColors.inkSoftColor),
                        filled: true,
                        fillColor: AppColors.whiteColor,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text('Forgot Password?',
                      style: TextStyle(
                          color: AppColors.goldColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ),
              if (auth.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(auth.errorMessage!, style: const TextStyle(color: AppColors.coralColor, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              // Vendor toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _isVendorLogin
                      ? AppColors.goldColor.withOpacity(0.08)
                      : AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _isVendorLogin
                          ? AppColors.goldColor.withOpacity(0.3)
                          : AppColors.sandColor),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('I am a vendor',
                      style: TextStyle(fontSize: 13, color: AppColors.inkColor)),
                  subtitle: const Text('Access your vendor dashboard',
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoftColor)),
                  value: _isVendorLogin,
                  activeColor: AppColors.goldColor,
                  onChanged: (v) => setState(() => _isVendorLogin = v),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account?", style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
                    },
                    child: Text('Create one', style: TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const VendorRegisterScreen()));
                  },
                  icon: const Icon(Icons.storefront, color: AppColors.goldColor, size: 18),
                  label: const Text('Become a Vendor',
                      style: TextStyle(
                          color: AppColors.goldColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your username/email and password')),
      );
      return;
    }
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    auth.clearError();

    final success = _isVendorLogin
        ? await auth.loginAsVendor(_emailCtrl.text.trim(), _passCtrl.text)
        : await auth.login(_emailCtrl.text.trim(), _passCtrl.text);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully!'), backgroundColor: AppColors.goldColor),
        );
        Navigator.pop(context);
        if (_isVendorLogin) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const VendorDashboardScreen()));
        }
      }
    }
  }
}

// ─── Register Page (Full Screen) ───
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.indigoColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_outlined, color: AppColors.indigoColor, size: 36),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.inkColor, fontFamily: 'Fraunces')),
                const SizedBox(height: 8),
                Text('Join ZZmore Store and start shopping',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoftColor, fontSize: 14)),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline, color: AppColors.inkSoftColor),
                    filled: true,
                    fillColor: AppColors.whiteColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Please choose a username' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, color: AppColors.inkSoftColor),
                    filled: true,
                    fillColor: AppColors.whiteColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleRegister(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined, color: AppColors.inkSoftColor),
                    filled: true,
                    fillColor: AppColors.whiteColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldColor,
                    foregroundColor: AppColors.whiteColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account?', style: TextStyle(color: AppColors.inkSoftColor, fontSize: 13)),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
                      },
                      child: Text('Sign In', style: TextStyle(color: AppColors.goldColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.registerUser(
        _usernameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account created! Logging you in...')),
        );
        final auth = context.read<AuthProvider>();
        final success = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
        if (mounted) {
          setState(() => _isLoading = false);
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Welcome to ZZmore Store!'), backgroundColor: AppColors.goldColor),
            );
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${e.toString()}'), backgroundColor: AppColors.coralColor),
        );
      }
    }
  }
}
