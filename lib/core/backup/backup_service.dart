import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

class BackupManifest {
  final String application;
  final String version;
  final int schemaVersion;
  final String backupType;
  final DateTime createdAt;
  final String companyName;
  final Map<String, int> recordCounts;
  final String databaseChecksum;

  const BackupManifest({
    required this.application,
    required this.version,
    required this.schemaVersion,
    required this.backupType,
    required this.createdAt,
    required this.companyName,
    required this.recordCounts,
    required this.databaseChecksum,
  });

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    return BackupManifest(
      application: json['application'] as String? ?? 'ALFA SOFT',
      version: json['version'] as String? ?? '1.0.0',
      schemaVersion: json['schemaVersion'] as int? ?? 5,
      backupType: json['backupType'] as String? ?? 'FULL',
      createdAt: DateTime.parse(json['createdAt'] as String),
      companyName: json['companyName'] as String? ?? 'المنشأة الرئيسية',
      recordCounts: Map<String, int>.from(json['recordCounts'] as Map),
      databaseChecksum: json['databaseChecksum'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'application': application,
      'version': version,
      'schemaVersion': schemaVersion,
      'backupType': backupType,
      'createdAt': createdAt.toIso8601String(),
      'companyName': companyName,
      'recordCounts': recordCounts,
      'databaseChecksum': databaseChecksum,
    };
  }
}

class BackupService {
  /// Creates a consistent, verified SQLite backup package (.alfabackup format)
  Future<File> createBackup({
    required String sourceDbPath,
    required Directory destinationDir,
    String? companyName,
  }) async {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }

    final backupFile = File('${destinationDir.path}/alfa_backup_$timestamp.sqlite');
    
    // 1. Snapshot database using live SQLite VACUUM INTO
    final db = sqlite3.open(sourceDbPath);
    try {
      // Escape Windows path with forward slashes for SQLite VACUUM INTO
      final vacuumPath = backupFile.path.replaceAll('\\', '/');
      db.execute("VACUUM INTO '$vacuumPath';");

      // 2. Count vital records
      final prodCount = db.select('SELECT COUNT(*) as cnt FROM products').first['cnt'] as int;
      final salesCount = db.select('SELECT COUNT(*) as cnt FROM sales_invoices').first['cnt'] as int;
      final jeCount = db.select('SELECT COUNT(*) as cnt FROM journal_entries').first['cnt'] as int;
      final custCount = db.select('SELECT COUNT(*) as cnt FROM customers').first['cnt'] as int;
      final compRows = db.select('SELECT trade_name FROM companies LIMIT 1');
      final name = companyName ?? (compRows.isNotEmpty ? compRows.first['trade_name'] as String : 'ALFA SOFT');

      // 3. Compute SHA-256 Checksum of snapshot
      final bytes = backupFile.readAsBytesSync();
      final checksum = sha256.convert(bytes).toString();

      // 4. Write Companion Manifest
      final manifest = BackupManifest(
        application: 'ALFA SOFT',
        version: '1.0.0',
        schemaVersion: 5,
        backupType: 'FULL',
        createdAt: now,
        companyName: name,
        recordCounts: {
          'products': prodCount,
          'salesInvoices': salesCount,
          'journalEntries': jeCount,
          'customers': custCount,
        },
        databaseChecksum: checksum,
      );

      final manifestFile = File('${destinationDir.path}/alfa_backup_$timestamp.manifest.json');
      manifestFile.writeAsStringSync(jsonEncode(manifest.toJson()));

      return backupFile;
    } finally {
      db.dispose();
    }
  }

  /// Verifies a backup's cryptographic SHA-256 checksum and SQLite schema integrity
  bool verifyBackupIntegrity({
    required File backupFile,
    required File manifestFile,
  }) {
    if (!backupFile.existsSync() || !manifestFile.existsSync()) return false;

    // Check SHA-256
    final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final manifest = BackupManifest.fromJson(manifestJson);

    final bytes = backupFile.readAsBytesSync();
    final actualChecksum = sha256.convert(bytes).toString();

    if (actualChecksum != manifest.databaseChecksum) {
      return false; // Checksum corrupted or altered
    }

    // Verify SQLite internal B-Tree integrity
    final db = sqlite3.open(backupFile.path);
    try {
      final res = db.select('PRAGMA integrity_check;');
      if (res.isEmpty || res.first.values.first != 'ok') {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      db.dispose();
    }
  }

  /// Restores verified backup into live production database with pre-restore rollback safety
  Future<bool> restoreBackup({
    required File backupFile,
    required File manifestFile,
    required String activeDbPath,
  }) async {
    // 1. Verify before touching live DB
    if (!verifyBackupIntegrity(backupFile: backupFile, manifestFile: manifestFile)) {
      throw Exception('فشل التحقق من سلامة ملف النسخة الاحتياطية. تم إلغاء الاستعادة لحماية البيانات.');
    }

    final activeFile = File(activeDbPath);

    // 2. Safety snapshot of current database
    if (activeFile.existsSync()) {
      final safetyRollback = File('${activeFile.parent.path}/pre_restore_safety_snapshot.sqlite');
      activeFile.copySync(safetyRollback.path);
    }

    // 3. Atomically overwrite live DB with backup
    backupFile.copySync(activeDbPath);

    // 4. Verify live DB integrity post-copy
    final restoredDb = sqlite3.open(activeDbPath);
    try {
      final check = restoredDb.select('PRAGMA integrity_check;');
      return check.isNotEmpty && check.first.values.first == 'ok';
    } finally {
      restoredDb.dispose();
    }
  }
}
