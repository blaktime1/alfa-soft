# ALFA SOFT — UI DESIGN SYSTEM & VISUAL DIRECTIVE (FLUTTER DESKTOP)

## 1. Visual Direction: Premium Layered Enterprise

ALFA SOFT implements a **Premium Layered Enterprise UI** direction within the Flutter rendering engine. It provides a tactile, executive aesthetic with subtle depth, refined borders, restrained glassmorphism, and clear data hierarchy suited for intensive daily retail and corporate accounting workloads.

---

## 2. Design Tokens & Theme Foundations

### 2.1 Theme Data (`AppTheme` in Flutter)

```dart
class AlfaColors {
  // Brand Core
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

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF0284C7);
}
```

---

## 3. Typography & Dual-Script Localization

### 3.1 Font Families
- **Arabic Script**: `IBM Plex Sans Arabic`, `Cairo`.
- **Latin Script**: `Inter`.
- **Tabular Figures & Currency**: Monospaced font features enabled (`fontFeatures: [FontFeature.tabularFigures()]`).

### 3.2 Directionality (RTL / LTR)
- Dynamic `Directionality` widget wraps the app root based on active language (`Locale('ar')` $\to$ `TextDirection.rtl`, `Locale('en')` $\to$ `TextDirection.ltr`).
- Navigation rails, sidebars, data grid columns, and back/forward icons automatically mirror symmetrically.

---

## 4. High-Performance Enterprise Data Tables

- Implemented using Flutter's virtualized `ListView.builder` or `DataTable` virtualizers.
- Sustains locked 60-120 FPS scrolling over 50,000+ item inventories.
- Numeric columns are right-aligned (LTR) or left-aligned (RTL) with monospaced digit alignment to prevent visual jitter.

---

## 5. POS Fullscreen Ergonomics & Keyboard Accelerators

Utilizes Flutter's `Shortcuts` and `Actions` architecture:
- `LogicalKeyboardKey.f1`: Focus Barcode / Search Input.
- `LogicalKeyboardKey.f2`: Customer Account Selector.
- `LogicalKeyboardKey.f3`: Apply Cart Discount Dialog.
- `LogicalKeyboardKey.f4`: Suspend / Hold Active Cart.
- `LogicalKeyboardKey.f9`: Quick Cash Checkout & Instant Receipt Print.
- `LogicalKeyboardKey.f10`: Split / Multi-Payment Dialog.
- `LogicalKeyboardKey.escape`: Clear active field / Cancel.
