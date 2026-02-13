import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Global theme configuration for MarketGöz
/// Provides consistent styling, padding, and High Contrast mode support
class AppTheme {
  AppTheme._();

  // Global padding constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Touch target sizes (accessibility)
  static const double minTouchTarget = 48.0;
  static const double buttonHeight = 56.0;

  // Border radius
  static const double borderRadius = 12.0;
  static const double smallBorderRadius = 8.0;

  // Object box default colors
  static const Color defaultBoxColorUnknown = Color(0xFFFF9800); // Orange
  static const Color defaultBoxColorKnown = Color(0xFF4CAF50); // Green
  static const Color defaultBoxColorLinked = Color(0xFF2196F3); // Blue

  // High Contrast Mode colors
  static const Color hcBackground = Color(0xFF000000); // Pure black
  static const Color hcText = Color(0xFFFFFF00); // Bright yellow
  static const Color hcTextSecondary = Color(0xFFFFFFFF); // White
  static const Color hcBorder = Color(0xFFFFFFFF); // White
  static const Color hcBoxColor = Color(0xFF00FF00); // Neon green
  static const Color hcAccent = Color(0xFF00FFFF); // Cyan

  /// Standard Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: defaultPadding,
            vertical: smallPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        ),
        margin: EdgeInsets.symmetric(
          horizontal: defaultPadding,
          vertical: smallPadding,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(smallBorderRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: defaultPadding,
          vertical: smallPadding,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: defaultPadding,
      ),
    );
  }

  /// High Contrast Theme for accessibility
  /// Uses copyWith to ensure TextStyles are compatible for smooth transitions
  static ThemeData get highContrastTheme {
    // Start from a dark theme base to ensure all TextStyles have matching structure
    final base = ThemeData.dark(useMaterial3: true);
    
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: hcAccent,
        onPrimary: hcBackground,
        surface: hcBackground,
        onSurface: hcText,
        error: Color(0xFFFF0000),
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
          minimumSize: const Size(double.infinity, buttonHeight),
          backgroundColor: hcBackground,
          foregroundColor: hcText,
          side: const BorderSide(color: hcBorder, width: 3),
          padding: const EdgeInsets.symmetric(
            horizontal: defaultPadding,
            vertical: smallPadding,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: hcBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: const BorderSide(color: hcBorder, width: 2),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: defaultPadding,
          vertical: smallPadding,
        ),
      ),
      // Use copyWith on base text theme to maintain inherit structure
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: hcText, fontSize: 18),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: hcText, fontSize: 16),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: hcText),
        titleLarge: base.textTheme.titleLarge?.copyWith(color: hcText, fontSize: 22, fontWeight: FontWeight.bold),
        titleMedium: base.textTheme.titleMedium?.copyWith(color: hcText),
        titleSmall: base.textTheme.titleSmall?.copyWith(color: hcText),
        labelLarge: base.textTheme.labelLarge?.copyWith(color: hcText),
        labelMedium: base.textTheme.labelMedium?.copyWith(color: hcText),
        labelSmall: base.textTheme.labelSmall?.copyWith(color: hcText),
      ),
      iconTheme: const IconThemeData(color: hcText, size: 28),
      dividerTheme: const DividerThemeData(
        color: hcBorder,
        thickness: 2,
        space: defaultPadding,
      ),
    );
  }
}
