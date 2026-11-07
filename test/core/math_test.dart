import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/core/math/bankers_rounding.dart';
import 'package:alfa_soft/core/math/vat_calculator.dart';

void main() {
  group('Bankers Rounding Tests', () {
    test('Half rounds to nearest even integer', () {
      // 2.5 rounds to 2 (even)
      expect(BankersRounding.round(2.5, decimals: 0), equals(2.0));
      // 3.5 rounds to 4 (even)
      expect(BankersRounding.round(3.5, decimals: 0), equals(4.0));
      // 4.5 rounds to 4 (even)
      expect(BankersRounding.round(4.5, decimals: 0), equals(4.0));
      // 1.25 with 1 decimal rounds to 1.2 (2 is even)
      expect(BankersRounding.round(1.25, decimals: 1), equals(1.2));
      // 1.35 with 1 decimal rounds to 1.4 (4 is even)
      expect(BankersRounding.round(1.35, decimals: 1), equals(1.4));
    });

    test('Minor units conversion preserves exact scale', () {
      expect(BankersRounding.toMinorUnits(150.75, scale: 2), equals(15075));
      expect(BankersRounding.fromMinorUnits(15075, scale: 2), equals(150.75));
      expect(BankersRounding.toMinorUnits(10.005, scale: 2), equals(1000)); // .005 rounds to even 0
      expect(BankersRounding.toMinorUnits(10.015, scale: 2), equals(1002)); // .015 rounds to even 2
    });
  });

  group('VAT Calculator Tests', () {
    test('Tax-exclusive calculation (15% VAT on 100.00)', () {
      final result = VatCalculator.calculateExclusive(
        netAmount: 100.0,
        taxRateBps: 1500, // 15%
      );
      expect(result.taxableAmount, equals(100.0));
      expect(result.taxAmount, equals(15.0));
      expect(result.grossAmount, equals(115.0));
      expect(result.grossMinorUnits, equals(11500));
    });

    test('Tax-inclusive calculation (15% VAT on 115.00)', () {
      final result = VatCalculator.calculateInclusive(
        grossAmount: 115.0,
        taxRateBps: 1500,
      );
      expect(result.taxableAmount, equals(100.0));
      expect(result.taxAmount, equals(15.0));
      expect(result.grossAmount, equals(115.0));
    });

    test('Fractional tax inclusive rounding consistency', () {
      final result = VatCalculator.calculateInclusive(
        grossAmount: 10.0,
        taxRateBps: 1500,
      );
      // 10 / 1.15 = 8.69565... -> rounds to 8.70
      expect(result.taxableAmount, equals(8.70));
      // 10.00 - 8.70 = 1.30
      expect(result.taxAmount, equals(1.30));
      expect(result.taxableAmount + result.taxAmount, equals(10.0));
    });
  });
}
