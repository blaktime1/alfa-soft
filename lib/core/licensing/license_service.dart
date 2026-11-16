import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

enum LicenseTier {
  starter('STARTER', 'النسخة الأساسية — Starter', 1, 2),
  professional('PROFESSIONAL', 'النسخة المتقدمة — Pro', 3, 5),
  enterprise('ENTERPRISE', 'النسخة المؤسسية الشاملة — Enterprise', 99, 99);

  final String code;
  final String labelAr;
  final int maxBranches;
  final int maxTerminals;

  const LicenseTier(this.code, this.labelAr, this.maxBranches, this.maxTerminals);

  static LicenseTier fromString(String val) {
    return LicenseTier.values.firstWhere(
      (e) => e.code.toUpperCase() == val.toUpperCase(),
      orElse: () => LicenseTier.enterprise,
    );
  }
}

class LicenseInfo {
  final String licenseeName;
  final String hardwareId;
  final String taxNumber;
  final LicenseTier tier;
  final String planType; // 'LIFETIME', 'ANNUAL', 'SEMI_ANNUAL', 'MONTHLY', 'CUSTOM'
  final int maxBranches;
  final int maxTerminals;
  final List<String> modules;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final bool isLifetime;
  final bool isValid;
  final bool isClockTampered;
  final String? validationError;
  final String rawPackage;
  final String? notes;

  const LicenseInfo({
    required this.licenseeName,
    required this.hardwareId,
    required this.taxNumber,
    required this.tier,
    this.planType = 'LIFETIME',
    required this.maxBranches,
    required this.maxTerminals,
    required this.modules,
    required this.issuedAt,
    this.expiresAt,
    required this.isLifetime,
    required this.isValid,
    this.isClockTampered = false,
    this.validationError,
    this.rawPackage = '',
    this.notes,
  });

  /// Whether the license period has passed
  bool get isExpired {
    if (isLifetime || expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Whether the system should run in graceful Read-Only Archive mode
  /// Allows viewing historical data, calculating audits, and printing/exporting,
  /// but blocks adding new sales, purchases, vouchers, and payroll runs.
  bool get isReadOnlyArchive => isValid && (isExpired || isClockTampered);

  /// Remaining days of license (null if lifetime)
  int? get remainingDays {
    if (isLifetime || expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Checks if a particular module is enabled
  bool hasModule(String moduleCode) {
    if (!isValid) return false;
    if (isLifetime && tier == LicenseTier.enterprise) return true;
    return modules.contains(moduleCode) || modules.contains('ALL');
  }

  static LicenseInfo unactivated(String hardwareId) {
    return LicenseInfo(
      licenseeName: 'نسخة غير مرخصة',
      hardwareId: hardwareId,
      taxNumber: '',
      tier: LicenseTier.starter,
      planType: 'NONE',
      maxBranches: 1,
      maxTerminals: 1,
      modules: const [],
      issuedAt: DateTime.now(),
      isLifetime: false,
      isValid: false,
      validationError: 'لم يتم تنشيط النظام بعد على هذا الجهاز. يرجى إدخال أو استيراد ملف ترخيص معتمد.',
    );
  }
}

/// Offline Hardware Fingerprinting and Cryptographic Ed25519 Licensing Service
class LicenseService {
  final Ed25519 _algorithm = Ed25519();

  // ALFA SOFT Master Ed25519 Root Public Key (32 bytes raw, Hex encoded)
  // Embedded into the client binary to verify authenticity strictly offline
  static const String masterPublicKeyHex =
      '619881234e86c6a4fed591cd3544634ee6f0635ac68b6a2ca79d4429ad4336bc';

  // Master Private Key (Held by Developer / Vendor for issuing authentic licenses)
  static const String masterPrivateKeyHex =
      'befb92426cf7706ef0e6397daa4c616730e45bf5e38ae9b7f066c7f93db045eb';

  /// Generates a tamper-resistant Hardware Fingerprint for this Windows computer
  /// Combines Windows MachineGuid (Registry), Motherboard info, and CPU signature
  String getMachineHardwareId() {
    String? machineGuid;
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('powershell', [
          '-NoProfile',
          '-Command',
          "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Cryptography').MachineGuid",
        ]);
        if (result.exitCode == 0) {
          final out = (result.stdout as String).trim();
          if (out.isNotEmpty && out.length >= 8) {
            machineGuid = out;
          }
        }
      }
    } catch (_) {}

    final env = Platform.environment;
    final compName = env['COMPUTERNAME'] ?? 'ALFA_WORKSTATION';
    final procArch = env['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    final procId = env['PROCESSOR_IDENTIFIER'] ?? 'GENERIC_CPU';
    final os = Platform.operatingSystemVersion;

    final rawSeed = '${machineGuid ?? "ALFA_SYS_FALLBACK"}|$compName|$procArch|$procId|$os|ALFA_SALT_2026';
    final hash = sha256.convert(utf8.encode(rawSeed)).toString().toUpperCase();

    // Format as 4 blocks of 4 chars: ALFA-XXXX-XXXX-XXXX-XXXX
    return 'ALFA-${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}-${hash.substring(12, 16)}';
  }

  /// Encodes canonical payload for signing to prevent JSON key order discrepancies
  String createCanonicalString(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final parts = <String>[];
    for (final k in sortedKeys) {
      parts.add('$k=${data[k]}');
    }
    return parts.join('|');
  }

  /// Developer / Vendor Utility: Signs and generates an offline signed license package
  Future<String> issueLicense({
    required String licenseeName,
    required String hardwareId,
    required String taxNumber,
    required LicenseTier tier,
    String planType = 'LIFETIME',
    DateTime? expiresAt,
    int? maxBranches,
    int? maxTerminals,
    List<String> modules = const ['POS', 'INVENTORY', 'ACCOUNTING', 'PURCHASING', 'ENTERPRISE', 'REPORTS', 'SYNC'],
    String? notes,
    String? customPrivateKeyHex,
  }) async {
    final issuedAt = DateTime.now().toUtc();
    final resolvedBranches = maxBranches ?? tier.maxBranches;
    final resolvedTerminals = maxTerminals ?? tier.maxTerminals;

    final canonicalMap = <String, dynamic>{
      'licensee': licenseeName.trim(),
      'hwid': hardwareId.trim().toUpperCase(),
      'tax_no': taxNumber.trim(),
      'tier': tier.code,
      'plan_type': planType.toUpperCase(),
      'max_branches': resolvedBranches,
      'max_terminals': resolvedTerminals,
      'modules': modules.join(','),
      'issued_at': issuedAt.toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String() ?? 'LIFETIME',
      'notes': notes?.trim() ?? 'ترخيص نظام ألفا سوفت معتمد',
    };

    final canonicalStr = createCanonicalString(canonicalMap);

    final privHex = customPrivateKeyHex ?? masterPrivateKeyHex;
    final privBytes = _hexDecode(privHex);
    final pubBytes = _hexDecode(masterPublicKeyHex);

    final keyPair = SimpleKeyPairData(
      privBytes,
      publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    final signature = await _algorithm.sign(
      utf8.encode(canonicalStr),
      keyPair: keyPair,
    );

    final licensePackage = {
      'version': '1.0',
      'data': canonicalMap,
      'signature': base64Encode(signature.bytes),
    };

    // Return as compact base64 package prefixed with ALFALIC-
    return 'ALFALIC-${base64Encode(utf8.encode(jsonEncode(licensePackage)))}';
  }

  /// Client Validation: Verifies license cryptographic signature, hardware ID, clock tamper, and expiry
  Future<LicenseInfo> validateLicense({
    required String rawLicensePackage,
    required String localHardwareId,
    Database? db,
    String? trustedPublicKeyHex,
  }) async {
    try {
      var clean = rawLicensePackage.trim();
      if (clean.startsWith('ALFALIC-')) {
        clean = clean.substring(8);
      }

      final jsonStr = utf8.decode(base64Decode(clean));
      final package = jsonDecode(jsonStr) as Map<String, dynamic>;

      final data = package['data'] as Map<String, dynamic>;
      final signatureBytes = base64Decode(package['signature'] as String);

      final canonicalStr = createCanonicalString(data);
      final messageBytes = utf8.encode(canonicalStr);

      final pubKeyHex = trustedPublicKeyHex ?? masterPublicKeyHex;
      final pubKeyBytes = _hexDecode(pubKeyHex);
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);

      final signature = Signature(signatureBytes, publicKey: publicKey);

      // 1. Cryptographic Ed25519 Verification (Strict tamper detection)
      final isSignatureValid = await _algorithm.verify(messageBytes, signature: signature);
      if (!isSignatureValid) {
        return _invalidResult(
          data: data,
          rawPackage: rawLicensePackage,
          error: 'فشل التحقق الرقمي: التوقيع الإلكتروني غير مطابق أو تم التلاعب بملف وبيانات الترخيص!',
        );
      }

      // 2. Hardware ID Binding (Prevents transferring license to another machine)
      final licenseHwid = (data['hwid'] as String).toUpperCase().trim();
      final localHwid = localHardwareId.toUpperCase().trim();
      if (licenseHwid != localHwid) {
        return _invalidResult(
          data: data,
          rawPackage: rawLicensePackage,
          error: 'الترخيص غير مخصص لهذا الجهاز!\nكود الترخيص مسجل للجهاز: $licenseHwid\nكود هذا الجهاز الحالي: $localHwid',
        );
      }

      // 3. Expiry Date Verification
      final expiresStr = data['expires_at'] as String;
      final isLifetime = expiresStr == 'LIFETIME';
      DateTime? expiresAt;
      bool isExpired = false;
      if (!isLifetime) {
        expiresAt = DateTime.tryParse(expiresStr);
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          isExpired = true;
        }
      }

      // 4. Clock Rollback & Anti-Tamper Guard
      bool isClockTampered = false;
      if (db != null) {
        isClockTampered = _checkAndRecordClock(db);
      }

      final tier = LicenseTier.fromString(data['tier']?.toString() ?? 'ENTERPRISE');
      final planType = data['plan_type']?.toString() ?? (isLifetime ? 'LIFETIME' : 'CUSTOM');
      final modules = (data['modules']?.toString() ?? 'ALL').split(',');

      return LicenseInfo(
        licenseeName: data['licensee'] as String,
        hardwareId: licenseHwid,
        taxNumber: data['tax_no']?.toString() ?? '',
        tier: tier,
        planType: planType,
        maxBranches: (data['max_branches'] as num?)?.toInt() ?? tier.maxBranches,
        maxTerminals: (data['max_terminals'] as num?)?.toInt() ?? tier.maxTerminals,
        modules: modules,
        issuedAt: DateTime.tryParse(data['issued_at']?.toString() ?? '') ?? DateTime.now(),
        expiresAt: expiresAt,
        isLifetime: isLifetime,
        isValid: true,
        isClockTampered: isClockTampered,
        validationError: isExpired
            ? 'انتهت فترة الترخيص بتاريخ ${expiresAt?.toIso8601String().substring(0, 10)}. النظام يعمل في وضع الأرشفة والمطالعة.'
            : (isClockTampered ? 'تم رصد تلاعب بساعة وتاريخ النظام إلى الخلف! النظام في وضع الأرشفة لحماية البيانات.' : null),
        rawPackage: rawLicensePackage,
        notes: data['notes'] as String?,
      );
    } catch (e) {
      return LicenseInfo(
        licenseeName: 'غير معروف',
        hardwareId: localHardwareId,
        taxNumber: '',
        tier: LicenseTier.starter,
        maxBranches: 1,
        maxTerminals: 1,
        modules: const [],
        issuedAt: DateTime.now(),
        isLifetime: false,
        isValid: false,
        rawPackage: rawLicensePackage,
        validationError: 'تنسيق مفتاح الترخيص غير صالح: $e',
      );
    }
  }

  /// Clock Rollback Protection: Checks current system clock against previous recorded clock
  bool _checkAndRecordClock(Database db) {
    try {
      final nowUtc = DateTime.now().toUtc();
      final rows = db.select("SELECT last_recorded_utc, tamper_flags FROM system_security_clocks WHERE key = 'MASTER_CLOCK' LIMIT 1");
      if (rows.isNotEmpty) {
        final lastRecordedStr = rows.first['last_recorded_utc'] as String;
        final lastRecorded = DateTime.tryParse(lastRecordedStr);
        if (lastRecorded != null) {
          // If clock was rolled backwards by more than 2 hours
          if (nowUtc.isBefore(lastRecorded.subtract(const Duration(hours: 2)))) {
            db.execute("UPDATE system_security_clocks SET tamper_flags = tamper_flags + 1 WHERE key = 'MASTER_CLOCK'");
            return true;
          }
        }
      }

      // Update recorded clock to current time
      db.execute(
        "INSERT INTO system_security_clocks (key, last_recorded_utc, tamper_flags, updated_at) VALUES ('MASTER_CLOCK', ?, 0, datetime('now')) ON CONFLICT(key) DO UPDATE SET last_recorded_utc = excluded.last_recorded_utc, updated_at = datetime('now')",
        [nowUtc.toIso8601String()],
      );
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Reads and validates the active license stored in the database
  Future<LicenseInfo> getInstalledLicense(Database db) async {
    final localHwid = getMachineHardwareId();
    try {
      final rows = db.select('''
        SELECT raw_package FROM system_licenses 
        WHERE is_active = 1 
        ORDER BY installed_at DESC LIMIT 1
      ''');

      if (rows.isEmpty) {
        // Check system_settings fallback
        final setRows = db.select("SELECT value FROM system_settings WHERE key = 'installed_license' LIMIT 1");
        if (setRows.isNotEmpty) {
          final raw = setRows.first['value'] as String;
          return validateLicense(rawLicensePackage: raw, localHardwareId: localHwid, db: db);
        }
        return LicenseInfo.unactivated(localHwid);
      }

      final rawPackage = rows.first['raw_package'] as String;
      return validateLicense(rawLicensePackage: rawPackage, localHardwareId: localHwid, db: db);
    } catch (_) {
      return LicenseInfo.unactivated(localHwid);
    }
  }

  /// Installs and saves an active verified license package into the database
  Future<LicenseInfo> installLicense({
    required Database db,
    required String rawLicensePackage,
  }) async {
    final localHwid = getMachineHardwareId();
    final info = await validateLicense(
      rawLicensePackage: rawLicensePackage,
      localHardwareId: localHwid,
      db: db,
    );

    if (!info.isValid) {
      return info;
    }

    try {
      db.execute('BEGIN TRANSACTION');
      db.execute("UPDATE system_licenses SET is_active = 0 WHERE is_active = 1");
      db.execute('''
        INSERT INTO system_licenses (
          id, licensee, hardware_id, tier, plan_type,
          issued_at, expires_at, modules, raw_package, signature, is_active, installed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))
      ''', [
        'lic_${DateTime.now().millisecondsSinceEpoch}',
        info.licenseeName,
        info.hardwareId,
        info.tier.code,
        info.planType,
        info.issuedAt.toIso8601String(),
        info.expiresAt?.toIso8601String() ?? 'LIFETIME',
        info.modules.join(','),
        info.rawPackage,
        'SIG_VERIFIED_ED25519',
      ]);

      db.execute('''
        INSERT INTO system_settings (key, value, updated_at) 
        VALUES ('installed_license', ?, datetime('now'))
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
      ''', [info.rawPackage]);
      db.execute('COMMIT');
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      return LicenseInfo(
        licenseeName: info.licenseeName,
        hardwareId: info.hardwareId,
        taxNumber: info.taxNumber,
        tier: info.tier,
        maxBranches: info.maxBranches,
        maxTerminals: info.maxTerminals,
        modules: info.modules,
        issuedAt: info.issuedAt,
        isLifetime: info.isLifetime,
        isValid: false,
        rawPackage: rawLicensePackage,
        validationError: 'فشل حفظ الترخيص في قاعدة البيانات: $e',
      );
    }

    return info;
  }

  LicenseInfo _invalidResult({
    required Map<String, dynamic> data,
    required String rawPackage,
    required String error,
  }) {
    return LicenseInfo(
      licenseeName: data['licensee']?.toString() ?? 'غير معروف',
      hardwareId: data['hwid']?.toString() ?? '',
      taxNumber: data['tax_no']?.toString() ?? '',
      tier: LicenseTier.fromString(data['tier']?.toString() ?? 'STARTER'),
      planType: data['plan_type']?.toString() ?? 'NONE',
      maxBranches: (data['max_branches'] as num?)?.toInt() ?? 1,
      maxTerminals: (data['max_terminals'] as num?)?.toInt() ?? 1,
      modules: (data['modules']?.toString() ?? '').split(','),
      issuedAt: DateTime.tryParse(data['issued_at']?.toString() ?? '') ?? DateTime.now(),
      isLifetime: data['expires_at'] == 'LIFETIME',
      isValid: false,
      rawPackage: rawPackage,
      validationError: error,
    );
  }

  List<int> _hexDecode(String hex) {
    final clean = hex.replaceAll(' ', '');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
