import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/cart_provider.dart';
import 'home_screen.dart';
import 'explore_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// Returns the inner [NavigatorState] for the tab at [tabIndex], looked up
  /// from anywhere in the widget tree.  Use this before calling
  /// `Navigator.push()` so the pushed route stays inside the tab and the
  /// bottom navigation bar remains visible.
  ///
  /// ```dart
  /// // Push a product-detail page inside the Explore tab (index 1):
  /// MainScreen.innerNavigatorOf(context, 1)
  ///     ?.push(MaterialPageRoute(builder: (_) => const ProductDetailPage()));
  /// ```
  static NavigatorState? innerNavigatorOf(BuildContext context, int tabIndex) {
    final state = context.findAncestorStateOfType<_MainScreenState>();
    if (state == null ||
        tabIndex < 0 ||
        tabIndex >= state._navigatorKeys.length) {
      return null;
    }
    return state._navigatorKeys[tabIndex].currentState;
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screenBuilders;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    _screenBuilders = [
      HomeScreen(
          onTabSwitch: (index) => setState(() => _currentIndex = index)),
      const ExploreScreen(),
      const CartScreen(),
      const ProfileScreen(),
    ];
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) {
      // Tap on the active tab → pop to root so the user starts fresh.
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      // Pop the *leaving* tab back to its root before switching.
      _navigatorKeys[_currentIndex]
          .currentState
          ?.popUntil((route) => route.isFirst);
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop) return;
        final innerNavigator = _navigatorKeys[_currentIndex].currentState;
        if (innerNavigator != null && innerNavigator.canPop()) {
          innerNavigator.pop();
        } else {
          // At root of all tabs – exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(_screenBuilders.length, (i) {
            return Navigator(
              key: _navigatorKeys[i],
              onGenerateRoute: (settings) {
                return MaterialPageRoute(
                  builder: (_) => _screenBuilders[i],
                );
              },
            );
          }),
        ),
        bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.whiteColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view,
                  label: 'Explore',
                ),
                Consumer<CartProvider>(
                  builder: (context, cartProvider, child) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildNavItem(
                          index: 2,
                          icon: Icons.shopping_bag_outlined,
                          activeIcon: Icons.shopping_bag,
                          label: 'Cart',
                        ),
                        if (cartProvider.itemCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.coralColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${cartProvider.itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = _currentIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.goldColor : AppColors.inkSoftColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.goldColor : AppColors.inkSoftColor,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
