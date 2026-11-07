import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Brand Palette
  static const Color brandPrimary = Color(0xFF0F172A); // Slate 900
  static const Color brandAccent = Color(0xFF2563EB);  // Royal Blue 600
  static const Color brandAccentHover = Color(0xFF1D4ED8);

  // Light Palette
  static const Color lightBgCanvas = Color(0xFFF8FAFC);
  static const Color lightBgSurface = Color(0xFFFFFFFF);
  static const Color lightBgElevated = Color(0xFFFFFFFF);
  static const Color lightBorderSubtle = Color(0xFFE2E8F0);
  static const Color lightBorderMedium = Color(0xFFCBD5E1);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // Dark Palette
  static const Color darkBgCanvas = Color(0xFF0B0F19);
  static const Color darkBgSurface = Color(0xFF111827);
  static const Color darkBgElevated = Color(0xFF1F2937);
  static const Color darkBorderSubtle = Color(0xFF1F2937);
  static const Color darkBorderMedium = Color(0xFF374151);
  static const Color darkTextPrimary = Color(0xFFF9FAFB);
  static const Color darkTextSecondary = Color(0xFFD1D5DB);
  static const Color darkTextMuted = Color(0xFF6B7280);

  // Semantic Status Colors
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color danger = Color(0xFFEF4444);  // Rose 500
  static const Color info = Color(0xFF0284C7);    // Sky 600
}
