import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants/app_colors.dart';
import 'constants/api_constants.dart';
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
import 'screens/profile_screen.dart' show RegisterPage;

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

/// Shown instead of a blank white screen if something fails while the app
/// is starting, so the real cause is visible (and can be reported).
class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  const Text('ZZmore could not start',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  const SizedBox(height: 12),
                  const Text(
                      'Please send a screenshot of this screen to support.',
                      style: TextStyle(fontSize: 14, color: Colors.black87)),
                  const SizedBox(height: 20),
                  SelectableText(message,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  // Any error that escapes — including async ones — is caught here instead of
  // leaving the user on a blank white screen.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    try {
      await _startApp();
    } catch (e, st) {
      debugPrint('Startup failed: $e\n$st');
      runApp(_StartupErrorApp('$e\n\n$st'));
    }
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

Future<void> _startApp() async {
  // Android 15+ edge-to-edge: system bars are transparent by default
  // when using SystemUiMode.edgeToEdge. Only set icon brightness to ensure
  // visibility against the app's background. Avoid deprecated color properties
  // (statusBarColor, systemNavigationBarColor, systemNavigationBarDividerColor)
  // which trigger the deprecated setStatusBarColor / setNavigationBarColor APIs.
  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    // Allow content to draw edge-to-edge behind system bars
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('System UI setup skipped: $e');
  }

  final hiveService = HiveService();
  try {
    await hiveService.init().timeout(const Duration(seconds: 15));
  } catch (e) {
    // A damaged local cache (for example after updating over an old install)
    // must never stop the app from opening: wipe the cache and try again.
    debugPrint('Hive init failed ($e) — resetting local cache and retrying.');
    for (final box in const [
      HiveService.productsBox,
      HiveService.categoriesBox,
      HiveService.cartBox,
      HiveService.settingsBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    await hiveService.init().timeout(const Duration(seconds: 15));
  }

  // Single shared ApiService instance for the whole app (providers +
  // NotificationService). Previously NotificationService created its own
  // throwaway ApiService that never carried the user's JWT, so device-token
  // registration silently 401'd and push notifications never worked — see
  // notification_service.dart for the full explanation.
  final apiService = ApiService();
  NotificationService().attachApiService(apiService);

  // Initialize Firebase (required for push notifications). Requires
  // google-services.json (Android) at android/app/google-services.json and
  // GoogleService-Info.plist (iOS) at ios/Runner/GoogleService-Info.plist.
  // Wrapped in try/catch (with a timeout) so a platform missing its config
  // file, or a device without Google Play services, just disables push
  // instead of blocking or crashing startup.
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    // Initialize push notifications (non-blocking)
    NotificationService().initialize();
  } catch (e) {
    // Firebase not configured for this platform — push notifications disabled
    debugPrint('Firebase not configured. Push notifications disabled: $e');
  }

  runApp(ZZmoreStoreApp(hiveService: hiveService, apiService: apiService));
}

class ZZmoreStoreApp extends StatelessWidget {
  final HiveService hiveService;
  final ApiService apiService;
  const ZZmoreStoreApp({
    super.key,
    required this.hiveService,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
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
    _runStartupPrompts();
  }

  /// Shown at most once per app launch, one after another (never stacked):
  ///   1. "Update available" (throttled — see [_checkForUpdate])
  ///   2. A friendly invitation for guests to create an account.
  /// Neither one blocks the app; the user can always dismiss and carry on.
  Future<void> _runStartupPrompts() async {
    // Let the home screen paint before anything pops up.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _checkForUpdate();
    if (!mounted) return;
    await _promptGuestToSignUp();
  }

  /// Gently invites visitors who are not logged in to sign up for member
  /// discounts. Only a small dismissible bar: ignoring it just continues browsing.
  Future<void> _promptGuestToSignUp() async {
    try {
      final auth = context.read<AuthProvider>();
      // Wait (briefly) for the saved session to be restored so a returning,
      // logged-in user never sees the invitation.
      var waited = 0;
      while (mounted && auth.isLoading && waited < 10000) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }
      if (!mounted || auth.isAuthenticated) return;

      // A slim, dismissible bar — deliberately minimal. It does not cover
      // the screen and disappears on its own.
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.inkColor,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 10),
          showCloseIcon: true,
          closeIconColor: Colors.white60,
          content: const Text(
            'Sign up for member discounts',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          action: SnackBarAction(
            label: 'SIGN UP',
            textColor: AppColors.goldColor,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Sign-up prompt skipped: $e');
    }
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

  /// Best-effort check for a newer app build. NEVER blocks the user:
  ///  * An older app keeps working exactly as before.
  ///  * The reminder is dismissible ("Later") and is shown at most once every
  ///    3 days for the same new version (so it never nags).
  ///  * Only if the server explicitly sets a minimum supported build, and this
  ///    install is below it, is the prompt non-dismissible (reserved for the
  ///    rare case where an old build can no longer work with the server).
  /// Silently no-ops on any failure.
  Future<void> _checkForUpdate() async {
    try {
      final info = await ApiService().getLatestAppVersion();
      if (info == null) return;

      final latestCode = (info['latest_version_code'] as num?)?.toInt() ?? 0;
      final minCode =
          (info['min_supported_version_code'] as num?)?.toInt() ?? 0;
      if (latestCode <= ApiConstants.appVersionCode) return;

      final mustUpdate = minCode > 0 && ApiConstants.appVersionCode < minCode;

      // Pick the right store link for this platform. iOS has no default link,
      // so without one configured on the server we simply don't prompt there.
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      final updateUrl = isIos
          ? info['update_url_ios']?.toString() ?? ''
          : info['update_url']?.toString() ?? ApiConstants.appUpdateUrl;
      if (updateUrl.isEmpty) return;

      // Throttle the optional reminder (not the mandatory one).
      final hive = HiveService();
      final key = 'update_prompt_$latestCode';
      if (!mustUpdate) {
        try {
          final last = int.tryParse(hive.getString(key) ?? '') ?? 0;
          final age = DateTime.now().millisecondsSinceEpoch - last;
          if (last > 0 && age < const Duration(days: 3).inMilliseconds) return;
        } catch (_) {}
      }
      if (!mounted) return;

      final latestName = info['latest_version_name']?.toString();
      final custom = info['update_message']?.toString() ?? '';
      final message = custom.isNotEmpty
          ? custom
          : (latestName != null && latestName.isNotEmpty)
              ? 'A newer version ($latestName) of ZZmore is available with '
                  'the latest features and fixes. You can keep using the app '
                  'and update whenever you like.'
              : 'A newer version of ZZmore is available with the latest '
                  'features and fixes. You can keep using the app and update '
                  'whenever you like.';

      try {
        await hive.saveString(
            key, DateTime.now().millisecondsSinceEpoch.toString());
      } catch (_) {}

      await showDialog<void>(
        context: context,
        barrierDismissible: !mustUpdate,
        builder: (ctx) => PopScope(
          canPop: !mustUpdate,
          child: AlertDialog(
            title: const Text('Update available'),
            content: Text(message),
            actions: [
              if (!mustUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Later'),
                ),
              ElevatedButton(
                onPressed: () async {
                  if (!mustUpdate) Navigator.pop(ctx);
                  try {
                    await launchUrl(
                      Uri.parse(updateUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                },
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MainScreen();
}
