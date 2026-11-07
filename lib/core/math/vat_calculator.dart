import 'bankers_rounding.dart';

/// Result of VAT Tax Computation
class TaxCalculationResult {
  final double taxableAmount;
  final double taxAmount;
  final double grossAmount;
  final int taxableMinorUnits;
  final int taxMinorUnits;
  final int grossMinorUnits;

  const TaxCalculationResult({
    required this.taxableAmount,
    required this.taxAmount,
    required this.grossAmount,
    required this.taxableMinorUnits,
    required this.taxMinorUnits,
    required this.grossMinorUnits,
  });

  @override
  String toString() =>
      'TaxCalculationResult(taxable: $taxableAmount, tax: $taxAmount, gross: $grossAmount)';
}

/// VAT Tax Calculator enforcing Banker's Rounding and fixed minor unit precision
class VatCalculator {
  const VatCalculator._();

  /// Calculates exclusive tax (Base price does not include VAT).
  /// [taxRateBps] is in basis points (e.g. 1500 for 15.00%).
  static TaxCalculationResult calculateExclusive({
    required double netAmount,
    required int taxRateBps,
    int decimals = 2,
  }) {
    final rate = taxRateBps / 10000.0;
    final taxAmount = BankersRounding.round(netAmount * rate, decimals: decimals);
    final grossAmount = BankersRounding.round(netAmount + taxAmount, decimals: decimals);

    return TaxCalculationResult(
      taxableAmount: netAmount,
      taxAmount: taxAmount,
      grossAmount: grossAmount,
      taxableMinorUnits: BankersRounding.toMinorUnits(netAmount, scale: decimals),
      taxMinorUnits: BankersRounding.toMinorUnits(taxAmount, scale: decimals),
      grossMinorUnits: BankersRounding.toMinorUnits(grossAmount, scale: decimals),
    );
  }

  /// Calculates inclusive tax (Gross price already includes VAT).
  /// [taxRateBps] is in basis points (e.g. 1500 for 15.00%).
  static TaxCalculationResult calculateInclusive({
    required double grossAmount,
    required int taxRateBps,
    int decimals = 2,
  }) {
    final rate = taxRateBps / 10000.0;
    final taxableAmount = BankersRounding.round(grossAmount / (1.0 + rate), decimals: decimals);
    final taxAmount = BankersRounding.round(grossAmount - taxableAmount, decimals: decimals);

    return TaxCalculationResult(
      taxableAmount: taxableAmount,
      taxAmount: taxAmount,
      grossAmount: grossAmount,
      taxableMinorUnits: BankersRounding.toMinorUnits(taxableAmount, scale: decimals),
      taxMinorUnits: BankersRounding.toMinorUnits(taxAmount, scale: decimals),
      grossMinorUnits: BankersRounding.toMinorUnits(grossAmount, scale: decimals),
    );
  }
}
