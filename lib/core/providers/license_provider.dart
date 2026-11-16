import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database_service.dart';
import '../licensing/license_service.dart';
import 'app_state_provider.dart';

class LicenseNotifier extends StateNotifier<LicenseInfo> {
  final DatabaseService _dbService;
  final LicenseService _service;

  LicenseNotifier({
    required DatabaseService dbService,
    required LicenseService service,
  })  : _dbService = dbService,
        _service = service,
        super(LicenseInfo.unactivated(service.getMachineHardwareId())) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final info = await _service.getInstalledLicense(_dbService.rawDb);
      state = info;
    } catch (_) {
      state = LicenseInfo.unactivated(_service.getMachineHardwareId());
    }
  }

  Future<LicenseInfo> activate(String rawPackage) async {
    final info = await _service.installLicense(
      db: _dbService.rawDb,
      rawLicensePackage: rawPackage,
    );
    state = info;
    return info;
  }
}

final licenseServiceProvider = Provider<LicenseService>((ref) {
  return LicenseService();
});

final licenseInfoProvider = StateNotifierProvider<LicenseNotifier, LicenseInfo>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final licenseService = ref.watch(licenseServiceProvider);
  return LicenseNotifier(dbService: dbService, service: licenseService);
});
