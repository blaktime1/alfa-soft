import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/core/licensing/license_service.dart';
import 'package:alfa_soft/data/local/database_service.dart';

void main() {
  group('Enterprise Offline Ed25519 Licensing & Hardware Fingerprinting Tests', () {
    late LicenseService service;
    late DatabaseService dbService;

    setUp(() {
      service = LicenseService();
      dbService = DatabaseService.inMemory();
    });

    tearDown(() {
      dbService.dispose();
    });

    test('1. Hardware Fingerprint is deterministic and follows ALFA-XXXX-XXXX-XXXX-XXXX format', () {
      final hwid1 = service.getMachineHardwareId();
      final hwid2 = service.getMachineHardwareId();

      expect(hwid1, equals(hwid2));
      expect(hwid1.startsWith('ALFA-'), isTrue);
      final parts = hwid1.split('-');
      expect(parts.length, equals(5));
      for (int i = 1; i < parts.length; i++) {
        expect(parts[i].length, equals(4));
      }
    });

    test('2. Issues authentic offline Ed25519 license and verifies strictly without internet', () async {
      final hwid = service.getMachineHardwareId();
      final token = await service.issueLicense(
        licenseeName: 'شركة النجوم للتجارة',
        hardwareId: hwid,
        taxNumber: '310987654300003',
        tier: LicenseTier.enterprise,
        planType: 'LIFETIME',
      );

      expect(token.startsWith('ALFALIC-'), isTrue);

      final info = await service.validateLicense(
        rawLicensePackage: token,
        localHardwareId: hwid,
        db: dbService.rawDb,
      );

      expect(info.isValid, isTrue);
      expect(info.isExpired, isFalse);
      expect(info.isReadOnlyArchive, isFalse);
      expect(info.licenseeName, equals('شركة النجوم للتجارة'));
      expect(info.hardwareId, equals(hwid));
      expect(info.tier, equals(LicenseTier.enterprise));
      expect(info.isLifetime, isTrue);
      expect(info.hasModule('POS'), isTrue);
      expect(info.hasModule('ACCOUNTING'), isTrue);
    });

    test('3. Anti-Tamper: Modifying 1 byte in the license invalidates digital signature', () async {
      final hwid = service.getMachineHardwareId();
      final token = await service.issueLicense(
        licenseeName: 'مؤسسة الوفاء',
        hardwareId: hwid,
        taxNumber: '300000000000003',
        tier: LicenseTier.professional,
      );

      // Tamper with data without re-signing
      final clean = token.substring(8);
      final map = jsonDecode(utf8.decode(base64Decode(clean))) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(map['data'] as Map);
      data['licensee'] = 'مخترق مزور'; // Alter licensee without valid signature
      final tamperedToken = 'ALFALIC-${base64Encode(utf8.encode(jsonEncode({'version': '1.0', 'data': data, 'signature': map['signature']})))}';

      final info = await service.validateLicense(
        rawLicensePackage: tamperedToken,
        localHardwareId: hwid,
        db: dbService.rawDb,
      );

      expect(info.isValid, isFalse);
      expect(info.validationError, contains('فشل التحقق الرقمي'));
    });

    test('4. Machine Binding: Transferring license to another device is blocked', () async {
      const originalHwid = 'ALFA-1111-2222-3333-4444';
      const foreignHwid = 'ALFA-9999-8888-7777-6666';

      final token = await service.issueLicense(
        licenseeName: 'شركة التجارة الحديثة',
        hardwareId: originalHwid,
        taxNumber: '300000000000003',
        tier: LicenseTier.enterprise,
      );

      // Attempt validation on a different hardware ID
      final info = await service.validateLicense(
        rawLicensePackage: token,
        localHardwareId: foreignHwid,
        db: dbService.rawDb,
      );

      expect(info.isValid, isFalse);
      expect(info.validationError, contains('الترخيص غير مخصص لهذا الجهاز'));
    });

    test('5. Graceful Expiry: Expired license enables Read-Only Archive mode without wiping data', () async {
      final hwid = service.getMachineHardwareId();
      final expiredDate = DateTime.now().subtract(const Duration(days: 10));

      final token = await service.issueLicense(
        licenseeName: 'شركة سابقة الترخيص',
        hardwareId: hwid,
        taxNumber: '300000000000003',
        tier: LicenseTier.starter,
        planType: 'MONTHLY',
        expiresAt: expiredDate,
      );

      final info = await service.validateLicense(
        rawLicensePackage: token,
        localHardwareId: hwid,
        db: dbService.rawDb,
      );

      expect(info.isValid, isTrue); // Cryptographically valid and authentic
      expect(info.isExpired, isTrue);
      expect(info.isReadOnlyArchive, isTrue);
      expect(info.validationError, contains('انتهت فترة الترخيص'));
    });

    test('6. Database Persistence: Installs and loads active license from SQLite', () async {
      final hwid = service.getMachineHardwareId();
      final token = await service.issueLicense(
        licenseeName: 'مركز البركة التجاري',
        hardwareId: hwid,
        taxNumber: '310111222300003',
        tier: LicenseTier.enterprise,
      );

      // Initially no license in clean DB
      final initialInfo = await service.getInstalledLicense(dbService.rawDb);
      expect(initialInfo.isValid, isFalse);

      // Install license
      final installedInfo = await service.installLicense(
        db: dbService.rawDb,
        rawLicensePackage: token,
      );
      expect(installedInfo.isValid, isTrue);
      expect(installedInfo.licenseeName, equals('مركز البركة التجاري'));

      // Retrieve license from SQLite on next boot
      final loadedInfo = await service.getInstalledLicense(dbService.rawDb);
      expect(loadedInfo.isValid, isTrue);
      expect(loadedInfo.licenseeName, equals('مركز البركة التجاري'));
      expect(loadedInfo.hardwareId, equals(hwid));
      expect(loadedInfo.tier, equals(LicenseTier.enterprise));
    });
  });
}
