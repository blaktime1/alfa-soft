import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/core/licensing/license_service.dart';

void main() {
  group('Phase 8: Offline Ed25519 Cryptographic Licensing & Hardware Fingerprinting', () {
    late LicenseService licenseService;

    setUp(() async {
      licenseService = LicenseService();
    });

    test('1. Generates deterministic Hardware ID in ALFA-XXXX-XXXX-XXXX-XXXX format', () {
      final hwid1 = licenseService.getMachineHardwareId();
      final hwid2 = licenseService.getMachineHardwareId();

      expect(hwid1, equals(hwid2));
      expect(hwid1.startsWith('ALFA-'), isTrue);
      final parts = hwid1.split('-');
      expect(parts.length, equals(5));
      expect(parts[1].length, equals(4));
      expect(parts[2].length, equals(4));
      expect(parts[3].length, equals(4));
      expect(parts[4].length, equals(4));
    });

    test('2. Successfully issues and validates genuine lifetime Enterprise license', () async {
      final hwid = licenseService.getMachineHardwareId();

      final licensePackage = await licenseService.issueLicense(
        licenseeName: 'شركة الفا للتجارة الدولية',
        hardwareId: hwid,
        taxNumber: '310998877600003',
        tier: LicenseTier.enterprise,
        expiresAt: null, // Lifetime
        modules: const ['POS', 'INVENTORY', 'ACCOUNTING', 'PURCHASING', 'SYNC', 'MIGRATION'],
      );

      expect(licensePackage, isNotEmpty);

      // Validate with client service using default master public key
      final info = await licenseService.validateLicense(
        rawLicensePackage: licensePackage,
        localHardwareId: hwid,
      );

      expect(info.isValid, isTrue);
      expect(info.validationError, isNull);
      expect(info.licenseeName, equals('شركة الفا للتجارة الدولية'));
      expect(info.hardwareId, equals(hwid));
      expect(info.taxNumber, equals('310998877600003'));
      expect(info.tier, equals(LicenseTier.enterprise));
      expect(info.maxBranches, equals(99));
      expect(info.maxTerminals, equals(99));
      expect(info.isLifetime, isTrue);
      expect(info.isExpired, isFalse);
      expect(info.modules.contains('ACCOUNTING'), isTrue);
    });

    test('3. Rejects license when Hardware ID does not match local machine', () async {
      final targetHwid = 'ALFA-AAAA-BBBB-CCCC-DDDD';
      final actualMachineHwid = 'ALFA-1111-2222-3333-4444';

      final licensePackage = await licenseService.issueLicense(
        licenseeName: 'متجر الرياض',
        hardwareId: targetHwid,
        taxNumber: '310000000000003',
        tier: LicenseTier.starter,
      );

      final info = await licenseService.validateLicense(
        rawLicensePackage: licensePackage,
        localHardwareId: actualMachineHwid,
      );

      expect(info.isValid, isFalse);
      expect(info.validationError, contains('الترخيص غير مخصص لهذا الجهاز'));
    });

    test('4. Cryptographic tampering detection: Rejects forged/modified payload', () async {
      final hwid = licenseService.getMachineHardwareId();

      final genuinePackage = await licenseService.issueLicense(
        licenseeName: 'مؤسسة النور',
        hardwareId: hwid,
        taxNumber: '310111111100003',
        tier: LicenseTier.starter,
      );

      // Remove prefix and tamper with tier from STARTER to ENTERPRISE
      var clean = genuinePackage.replaceAll('ALFALIC-', '');
      final decodedJson = utf8.decode(base64Decode(clean));
      final map = jsonDecode(decodedJson) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>;
      data['tier'] = 'ENTERPRISE';
      data['max_branches'] = 99;

      final tamperedPackage = 'ALFALIC-${base64Encode(utf8.encode(jsonEncode(map)))}';

      final info = await licenseService.validateLicense(
        rawLicensePackage: tamperedPackage,
        localHardwareId: hwid,
      );

      expect(info.isValid, isFalse);
      expect(info.validationError, contains('فشل التحقق الرقمي'));
    });

    test('5. Expired license transitions safely into Read-Only Archive mode', () async {
      final hwid = licenseService.getMachineHardwareId();
      final expiredDate = DateTime.now().subtract(const Duration(days: 10));

      final licensePackage = await licenseService.issueLicense(
        licenseeName: 'شركة منتهية الصلاحية',
        hardwareId: hwid,
        taxNumber: '310222222200003',
        tier: LicenseTier.professional,
        expiresAt: expiredDate,
      );

      final info = await licenseService.validateLicense(
        rawLicensePackage: licensePackage,
        localHardwareId: hwid,
      );

      expect(info.isExpired, isTrue);
      expect(info.isReadOnlyArchive, isTrue);
      expect(info.validationError, contains('انتهت فترة الترخيص'));
    });
  });
}
