import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/licensing/license_service.dart';

void main() async {
  final dbPath = r'C:\Users\MAX\AppData\Roaming\com.alfasoft\desktop_app\data\alfa_soft.db';
  print('Opening live database at: $dbPath');

  final dbService = DatabaseService.openFile(dbPath);
  final licenseService = LicenseService();
  final hwid = licenseService.getMachineHardwareId();
  print('Hardware ID: $hwid');

  final rawPackage = await licenseService.issueLicense(
    licenseeName: 'شركة ألفا للتجارة والخدمات',
    hardwareId: hwid,
    taxNumber: '300012345600003',
    tier: LicenseTier.enterprise,
    planType: 'LIFETIME',
    maxBranches: 99,
    maxTerminals: 99,
    modules: const [
      'POS',
      'INVENTORY',
      'PURCHASES',
      'ACCOUNTING',
      'CRM',
      'REPORTS',
      'ENTERPRISE',
      'SYNC',
      'SETTINGS',
    ],
    notes: 'ترخيص رسمي دائم للنظام المركزي',
  );

  print('Installing signed license...');
  final result = await licenseService.installLicense(
    db: dbService.rawDb,
    rawLicensePackage: rawPackage,
  );

  print('Installation result:');
  print('  Licensee: ${result.licenseeName}');
  print('  Tier: ${result.tier.labelAr}');
  print('  Plan: ${result.planType}');
  print('  IsValid: ${result.isValid}');
  print('  IsLifetime: ${result.isLifetime}');
  print('  IsClockTampered: ${result.isClockTampered}');
  print('  Error: ${result.validationError}');

  dbService.dispose();
  print('DONE!');
}
