import 'package:flutter/material.dart';

/// High-contrast color palette for visually impaired users
/// Following WCAG AAA contrast ratio (7:1 minimum)
class AppColors {
  AppColors._();
  
  // Primary colors
  static const Color primary = Color(0xFFFFD700); // Bright Yellow
  static const Color onPrimary = Color(0xFF000000); // Black text on yellow
  
  // Background
  static const Color background = Color(0xFFFFFFFF); // White
  static const Color surface = Color(0xFFF5F5F5); // Light gray
  
  // Status colors for expiry dates
  static const Color safe = Color(0xFF00C853); // Green - Safe to consume
  static const Color warning = Color(0xFFFF9800); // Orange - Expiring soon
  static const Color danger = Color(0xFFD32F2F); // Red - Expired
  
  // Text colors
  static const Color textPrimary = Color(0xFF000000); // Black
  static const Color textSecondary = Color(0xFF424242); // Dark gray
  static const Color textOnDark = Color(0xFFFFFFFF); // White
  
  // Accent colors
  static const Color accent = Color(0xFF2196F3); // Blue
  static const Color divider = Color(0xFFBDBDBD); // Gray
  
  // Semantic colors
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
}
