import 'dart:math' as math;

/// Implementation of Banker's Rounding (Round Half to Even)
///
/// Ensures unbiased rounding for financial and tax calculations:
/// If the fractional part is exactly halfway between two integers,
/// it rounds to the nearest even integer.
class BankersRounding {
  const BankersRounding._();

  static double round(double value, {int decimals = 2}) {
    if (value.isNaN || value.isInfinite) return value;

    final factor = math.pow(10, decimals).toDouble();
    // Normalize to handle potential IEEE 754 precision artifacts
    final scaled = double.parse((value * factor).toStringAsFixed(8));
    final floorVal = scaled.floor();
    final remainder = scaled - floorVal;
    const epsilon = 1e-7;

    if ((remainder - 0.5).abs() < epsilon) {
      // Exactly half: round to nearest even integer
      final isEven = floorVal % 2 == 0;
      final roundedInteger = isEven ? floorVal : floorVal + 1;
      return roundedInteger / factor;
    }

    return scaled.round() / factor;
  }

  /// Converts standard currency amount to minor integer units (e.g. 10.50 SAR -> 1050 Halalas)
  static int toMinorUnits(double amount, {int scale = 2}) {
    final factor = math.pow(10, scale).toDouble();
    return (round(amount, decimals: scale) * factor).round();
  }

  /// Converts minor integer units back to standard currency amount
  static double fromMinorUnits(int minorUnits, {int scale = 2}) {
    final factor = math.pow(10, scale).toDouble();
    return minorUnits / factor;
  }
}
