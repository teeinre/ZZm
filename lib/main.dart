import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'constants/app_colors.dart';
import 'services/api_service.dart';
import 'cache/hive_service.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/products_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/location_provider.dart';
import 'providers/vendor_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/currency_provider.dart';
import 'screens/main_screen.dart';
import 'screens/auth/forgot_password_screen.dart';

final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

/// Routes a `zzmore://reset-password?key=...&login=...` deep link to the
/// in-app "set new password" screen.
void _handleResetUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'zzmore') return;
  if (uri.host.toLowerCase() != 'reset-password') return;
  final key = uri.queryParameters['key'] ?? '';
  final login = uri.queryParameters['login'] ?? '';
  if (key.isEmpty || login.isEmpty) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _appNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(initialKey: key, initialLogin: login),
      ),
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15+ edge-to-edge: system bars are transparent by default
  // when using SystemUiMode.edgeToEdge. Only set icon brightness to ensure
  // visibility against the app's background. Avoid deprecated color properties
  // (statusBarColor, systemNavigationBarColor, systemNavigationBarDividerColor)
  // which trigger the deprecated setStatusBarColor / setNavigationBarColor APIs.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Allow content to draw edge-to-edge behind system bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final hiveService = HiveService();
  await hiveService.init();

  // Initialize Firebase (required for push notifications on Android only).
  // Requires google-services.json from Firebase Console placed at:
  //   android/app/google-services.json
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      // Initialize push notifications (non-blocking)
      NotificationService().initialize();
    } catch (e) {
      // Firebase not configured — push notifications disabled
      debugPrint('Firebase not configured. Push notifications disabled.');
    }
  }

  runApp(ZZmoreStoreApp(hiveService: hiveService));
}

class ZZmoreStoreApp extends StatelessWidget {
  final HiveService hiveService;
  const ZZmoreStoreApp({super.key, required this.hiveService});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    final storageService = StorageService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            apiService: apiService,
            storageService: storageService,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductsProvider(
            apiService: apiService,
            hiveService: hiveService,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => CartProvider(
            hiveService: hiveService,
            apiService: context.read<AuthProvider>().apiService,
          )..loadCart(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocationProvider(
            storage: storageService,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => VendorProvider(apiService: apiService, hiveService: hiveService),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => CurrencyProvider()..loadCurrency(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'ZZmore.store',
            navigatorKey: _appNavigatorKey,
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.goldColor,
                primary: AppColors.goldColor,
                secondary: AppColors.blackSoftColor,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              textTheme: GoogleFonts.manropeTextTheme(),
              scaffoldBackgroundColor: AppColors.creamColor,
              appBarTheme: const AppBarTheme(
                backgroundColor: AppColors.creamColor,
                elevation: 0,
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.goldColor,
                primary: AppColors.goldColor,
                secondary: AppColors.whiteColor,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              textTheme: GoogleFonts.manropeTextTheme(
                ThemeData.dark().textTheme,
              ),
              scaffoldBackgroundColor: const Color(0xFF121212),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1E1E1E),
                elevation: 0,
              ),
            ),
            home: const _AppRoot(),
          );
        },
      ),
    );
  }
}

/// Wraps [MainScreen] and wires up incoming deep links (e.g. the password
/// reset link) so they route to the correct in-app screen.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Link that launched the app (cold start).
    try {
      final initialLink = await _appLinks!.getInitialLink();
      if (initialLink != null) _handleResetUri(initialLink);
    } catch (_) {
      // Ignore — deep linking is optional.
    }

    // Links that arrive while the app is running.
    _subscription = _appLinks!.uriLinkStream.listen(_handleResetUri);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MainScreen();
}
