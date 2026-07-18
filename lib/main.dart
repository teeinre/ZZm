import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'constants/app_colors.dart';
import 'services/api_service.dart';
import 'cache/hive_service.dart';
import 'services/storage_service.dart';
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
  final hiveService = HiveService();
  await hiveService.init();
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
          create: (_) => CartProvider(
            hiveService: hiveService,
          )..loadCart(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocationProvider(
            storage: storageService,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => VendorProvider(apiService: apiService),
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
