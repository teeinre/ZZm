import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
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

  // Initialize Firebase (required for push notifications)
  // Requires google-services.json from Firebase Console placed at:
  //   android/app/google-services.json
  try {
    await Firebase.initializeApp();
    // Initialize push notifications (non-blocking)
    NotificationService().initialize();
  } catch (e) {
    // Firebase not configured — push notifications disabled
    debugPrint('Firebase not configured. Push notifications disabled.');
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
            title: 'ZZmore Store',
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
            home: const MainScreen(),
          );
        },
      ),
    );
  }
}
