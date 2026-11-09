import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Brand Palette - Premium Executive Enterprise
  static const Color brandPrimary = Color(0xFF0F172A); // Slate 900 Luxury Navy
  static const Color brandSecondary = Color(0xFF1E293B); // Slate 800
  static const Color brandAccent = Color(0xFF2563EB); // Executive Royal Blue
  static const Color brandAccentHover = Color(0xFF1D4ED8);
  static const Color brandGold = Color(0xFFD97706); // Luxury Amber Gold
  static const Color brandGoldLight = Color(0xFFFEF3C7);
  static const Color brandGoldDark = Color(0xFFB45309);

  // Premium Layered Light Palette
  static const Color lightBgCanvas = Color(0xFFF8FAFC); // Clean Canvas Background
  static const Color lightBgSurface = Color(0xFFFFFFFF); // Card & Modal Pure White
  static const Color lightBgSubtle = Color(0xFFF1F5F9); // Layered Panel / Well (Slate 100)
  static const Color lightBgElevated = Color(0xFFFFFFFF);
  
  static const Color lightBorderSubtle = Color(0xFFE2E8F0); // Delicate Slate 200
  static const Color lightBorderMedium = Color(0xFFCBD5E1); // Defined Slate 300
  static const Color lightBorderFocus = Color(0xFF3B82F6);

  static const Color lightTextPrimary = Color(0xFF0F172A); // High Contrast Slate 900
  static const Color lightTextSecondary = Color(0xFF475569); // Slate 600
  static const Color lightTextMuted = Color(0xFF94A3B8); // Slate 400

  // Semantic Status Colors (Layered Light Tint & Rich Accent)
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successText = Color(0xFF065F46);

  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFF92400E);

  static const Color danger = Color(0xFFEF4444); // Rose 500
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerText = Color(0xFF991B1B);
  static const Color error = danger;

  static const Color info = Color(0xFF0284C7); // Sky 600
  static const Color infoBg = Color(0xFFF0F9FF);
  static const Color infoText = Color(0xFF075985);

  // Dark Palette (Preserved for dark toggle)
  static const Color darkBgCanvas = Color(0xFF0B0F19);
  static const Color darkBgSurface = Color(0xFF111827);
  static const Color darkBgElevated = Color(0xFF1F2937);
  static const Color darkBorderSubtle = Color(0xFF1F2937);
  static const Color darkBorderMedium = Color(0xFF374151);
  static const Color darkTextPrimary = Color(0xFFF9FAFB);
  static const Color darkTextSecondary = Color(0xFFD1D5DB);
  static const Color darkTextMuted = Color(0xFF6B7280);
}
