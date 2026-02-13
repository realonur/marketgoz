import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/home/presentation/home_screen.dart';

/// MarketGöz App - Accessibility-focused with yellow/black theme
class MarketGozApp extends StatelessWidget {
  const MarketGozApp({super.key});

  // High contrast yellow/black colors for accessibility
  static const Color hcBackground = Color(0xFF000000); // Pure black
  static const Color hcText = Color(0xFFFFFF00); // Bright yellow
  static const Color hcAccent = Color(0xFF00FFFF); // Cyan

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketGöz',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Yellow/Black high contrast theme for visually impaired users
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: hcText,
          onPrimary: hcBackground,
          secondary: hcAccent,
          onSecondary: hcBackground,
          surface: hcBackground,
          onSurface: hcText,
        ),
        scaffoldBackgroundColor: hcBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: hcBackground,
          foregroundColor: hcText,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 80),
            backgroundColor: hcBackground,
            foregroundColor: hcText,
            side: const BorderSide(color: hcText, width: 3),
            textStyle: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: hcText, fontSize: 32, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(color: hcText, fontSize: 28, fontWeight: FontWeight.bold),
          headlineLarge: TextStyle(color: hcText, fontSize: 24, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(color: hcText, fontSize: 20, fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: hcText, fontSize: 22, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: hcText, fontSize: 18, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: hcText, fontSize: 18),
          bodyMedium: TextStyle(color: hcText, fontSize: 16),
          labelLarge: TextStyle(color: hcText, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: hcText, size: 32),
        cardTheme: CardThemeData(
          color: hcBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: hcText, width: 2),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: hcText,
          thickness: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
