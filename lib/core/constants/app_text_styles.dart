import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Large, accessible text styles for visually impaired users
class AppTextStyles {
  AppTextStyles._();
  
  // Headings
  static const TextStyle heading1 = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  
  static const TextStyle heading2 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  
  static const TextStyle heading3 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );
  
  // Body text
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  // Button text
  static const TextStyle buttonText = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );
  
  // Product info
  static const TextStyle productName = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle productPrice = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppColors.accent,
  );
  
  static const TextStyle expiryStatus = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );
  
  // Text theme for MaterialApp
  static const TextTheme textTheme = TextTheme(
    displayLarge: heading1,
    displayMedium: heading2,
    displaySmall: heading3,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
  );
}
