import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

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
      orElse: () => LicenseTier.professional,
    );
  }
}

class LicenseInfo {
  final String licenseeName;
  final String hardwareId;
  final String taxNumber;
  final LicenseTier tier;
  final int maxBranches;
  final int maxTerminals;
  final List<String> modules;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final bool isLifetime;
  final bool isValid;
  final String? validationError;

  const LicenseInfo({
    required this.licenseeName,
    required this.hardwareId,
    required this.taxNumber,
    required this.tier,
    required this.maxBranches,
    required this.maxTerminals,
    required this.modules,
    required this.issuedAt,
    this.expiresAt,
    required this.isLifetime,
    required this.isValid,
    this.validationError,
  });

  bool get isExpired {
    if (isLifetime || expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}

/// Offline Hardware Fingerprinting and Cryptographic Ed25519 Licensing Service
class LicenseService {
  final Ed25519 _algorithm = Ed25519();

  // ALFA SOFT Master Root Public Key (32 bytes raw, Hex encoded)
  // Public key used by clients to verify authenticity without cloud/server contact
  static const String masterPublicKeyHex =
      'c8c887decae449a071d054e83f2a893db605ffec1bfa7a7b8e1f57b6863c0ab8';

  /// Generates a deterministic Hardware Fingerprint for this Windows computer
  String getMachineHardwareId() {
    final env = Platform.environment;
    final compName = env['COMPUTERNAME'] ?? 'ALFA_WORKSTATION';
    final user = env['USERNAME'] ?? 'ADMIN';
    final procArch = env['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    final procId = env['PROCESSOR_IDENTIFIER'] ?? 'GENERIC_CPU';
    final os = Platform.operatingSystemVersion;

    final rawSeed = '$compName|$user|$procArch|$procId|$os|ALFA_SALT_2026';
    final hash = sha256.convert(utf8.encode(rawSeed)).toString().toUpperCase();

    // Format as 4 blocks of 4 chars: ALFA-XXXX-XXXX-XXXX
    return 'ALFA-${hash.substring(0, 4)}-${hash.substring(4, 8)}-${hash.substring(8, 12)}';
  }

  /// Encodes canonical payload for signing
  String createCanonicalString(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    final parts = <String>[];
    for (final k in sortedKeys) {
      parts.add('$k=${data[k]}');
    }
    return parts.join('|');
  }

  /// Developer / Vendor Utility: Signs and generates an offline license payload
  Future<String> issueLicense({
    required SimpleKeyPair vendorKeyPair,
    required String licenseeName,
    required String hardwareId,
    required String taxNumber,
    required LicenseTier tier,
    DateTime? expiresAt,
    List<String> modules = const ['POS', 'INVENTORY', 'ACCOUNTING', 'PURCHASING', 'SYNC', 'MIGRATION'],
  }) async {
    final issuedAt = DateTime.now().toUtc();
    final canonicalMap = <String, dynamic>{
      'licensee': licenseeName.trim(),
      'hwid': hardwareId.trim().toUpperCase(),
      'tax_no': taxNumber.trim(),
      'tier': tier.code,
      'max_branches': tier.maxBranches,
      'max_terminals': tier.maxTerminals,
      'modules': modules.join(','),
      'issued_at': issuedAt.toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String() ?? 'LIFETIME',
    };

    final canonicalStr = createCanonicalString(canonicalMap);
    final signature = await _algorithm.sign(
      utf8.encode(canonicalStr),
      keyPair: vendorKeyPair,
    );

    final licensePackage = {
      'data': canonicalMap,
      'signature': base64Encode(signature.bytes),
    };

    // Return as compact base64 package
    return base64Encode(utf8.encode(jsonEncode(licensePackage)));
  }

  /// Client Validation: Verifies license cryptographic signature, hardware ID, and expiry
  Future<LicenseInfo> validateLicense({
    required String rawLicensePackage,
    required String localHardwareId,
    String? trustedPublicKeyHex,
  }) async {
    try {
      final jsonStr = utf8.decode(base64Decode(rawLicensePackage.trim()));
      final package = jsonDecode(jsonStr) as Map<String, dynamic>;

      final data = package['data'] as Map<String, dynamic>;
      final signatureBytes = base64Decode(package['signature'] as String);

      final canonicalStr = createCanonicalString(data);
      final messageBytes = utf8.encode(canonicalStr);

      final pubKeyHex = trustedPublicKeyHex ?? masterPublicKeyHex;
      final pubKeyBytes = _hexDecode(pubKeyHex);
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);

      final signature = Signature(signatureBytes, publicKey: publicKey);

      // 1. Verify Cryptographic Signature
      final isSignatureValid = await _algorithm.verify(messageBytes, signature: signature);
      if (!isSignatureValid) {
        return _invalidResult(
          data: data,
          error: 'فشل التحقق الرقمي: التوقيع الإلكتروني غير صالح أو تم التلاعب بمحتوى الترخيص.',
        );
      }

      // 2. Verify Hardware ID
      final licenseHwid = (data['hwid'] as String).toUpperCase();
      if (licenseHwid != localHardwareId.trim().toUpperCase()) {
        return _invalidResult(
          data: data,
          error: 'الترخيص غير مخصص لهذا الجهاز! معرّف الجهاز المسجل: $licenseHwid، معرّف هذا الجهاز: $localHardwareId',
        );
      }

      // 3. Verify Expiry Date
      final expiresStr = data['expires_at'] as String;
      final isLifetime = expiresStr == 'LIFETIME';
      DateTime? expiresAt;
      if (!isLifetime) {
        expiresAt = DateTime.tryParse(expiresStr);
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          return _invalidResult(
            data: data,
            error: 'انتهت صلاحية هذا الترخيص بتاريخ ${expiresAt.toIso8601String().substring(0, 10)}. يرجى تجديد الاشتراك.',
          );
        }
      }

      final tier = LicenseTier.fromString(data['tier'] as String);
      final modules = (data['modules'] as String).split(',');

      return LicenseInfo(
        licenseeName: data['licensee'] as String,
        hardwareId: licenseHwid,
        taxNumber: data['tax_no'] as String,
        tier: tier,
        maxBranches: data['max_branches'] as int,
        maxTerminals: data['max_terminals'] as int,
        modules: modules,
        issuedAt: DateTime.parse(data['issued_at'] as String),
        expiresAt: expiresAt,
        isLifetime: isLifetime,
        isValid: true,
      );
    } catch (e) {
      return LicenseInfo(
        licenseeName: 'غير معروف',
        hardwareId: localHardwareId,
        taxNumber: '',
        tier: LicenseTier.starter,
        maxBranches: 1,
        maxTerminals: 1,
        modules: [],
        issuedAt: DateTime.now(),
        isLifetime: false,
        isValid: false,
        validationError: 'تنسيق مفتاح الترخيص غير صالح: $e',
      );
    }
  }

  LicenseInfo _invalidResult({required Map<String, dynamic> data, required String error}) {
    return LicenseInfo(
      licenseeName: data['licensee']?.toString() ?? 'غير معروف',
      hardwareId: data['hwid']?.toString() ?? '',
      taxNumber: data['tax_no']?.toString() ?? '',
      tier: LicenseTier.fromString(data['tier']?.toString() ?? 'STARTER'),
      maxBranches: data['max_branches'] as int? ?? 1,
      maxTerminals: data['max_terminals'] as int? ?? 1,
      modules: (data['modules']?.toString() ?? '').split(','),
      issuedAt: DateTime.tryParse(data['issued_at']?.toString() ?? '') ?? DateTime.now(),
      isLifetime: data['expires_at'] == 'LIFETIME',
      isValid: false,
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
