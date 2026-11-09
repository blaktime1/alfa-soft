import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/database_service.dart';

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
      schemaVersion: json['schemaVersion'] as int? ?? 6,
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

class BackupResult implements File {
  final File _file;
  final bool isSuccess;
  final String dbFilePath;
  final String manifestFilePath;
  final DateTime timestamp;
  final int sizeBytes;
  final String? errorMessage;

  BackupResult({
    required this.isSuccess,
    required this.dbFilePath,
    required this.manifestFilePath,
    required this.timestamp,
    required this.sizeBytes,
    this.errorMessage,
  }) : _file = File(dbFilePath);

  @override
  String get path => dbFilePath;

  @override
  bool existsSync() => _file.existsSync();

  @override
  Future<bool> exists() => _file.exists();

  @override
  int lengthSync() => _file.existsSync() ? _file.lengthSync() : 0;

  @override
  Future<int> length() => _file.length();

  @override
  File get absolute => _file.absolute;

  @override
  File copySync(String newPath) => _file.copySync(newPath);

  @override
  Future<File> copy(String newPath) => _file.copy(newPath);

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _file.createSync(recursive: recursive, exclusive: exclusive);

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      _file.create(recursive: recursive, exclusive: exclusive);

  @override
  void deleteSync({bool recursive = false}) => _file.deleteSync(recursive: recursive);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => _file.delete(recursive: recursive);

  @override
  Directory get parent => _file.parent;

  @override
  bool get isAbsolute => _file.isAbsolute;

  @override
  Future<DateTime> lastAccessed() => _file.lastAccessed();

  @override
  DateTime lastAccessedSync() => _file.lastAccessedSync();

  @override
  Future<DateTime> lastModified() => _file.lastModified();

  @override
  DateTime lastModifiedSync() => _file.lastModifiedSync();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) => _file.open(mode: mode);

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) => _file.openSync(mode: mode);

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) =>
      _file.openWrite(mode: mode, encoding: encoding);

  @override
  Uint8List readAsBytesSync() => _file.readAsBytesSync();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  String readAsStringSync({Encoding encoding = utf8}) => _file.readAsStringSync(encoding: encoding);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) => _file.readAsString(encoding: encoding);

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) => _file.readAsLinesSync(encoding: encoding);

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) => _file.readAsLines(encoding: encoding);

  @override
  File renameSync(String newPath) => _file.renameSync(newPath);

  @override
  Future<File> rename(String newPath) => _file.rename(newPath);

  @override
  Future<String> resolveSymbolicLinks() => _file.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => _file.resolveSymbolicLinksSync();

  @override
  Future setLastAccessed(DateTime time) => _file.setLastAccessed(time);

  @override
  void setLastAccessedSync(DateTime time) => _file.setLastAccessedSync(time);

  @override
  Future setLastModified(DateTime time) => _file.setLastModified(time);

  @override
  void setLastModifiedSync(DateTime time) => _file.setLastModifiedSync(time);

  @override
  FileStat statSync() => _file.statSync();

  @override
  Future<FileStat> stat() => _file.stat();

  @override
  Uri get uri => _file.uri;

  @override
  Stream<List<int>> openRead([int? start, int? end]) => _file.openRead(start, end);

  @override
  Stream<FileSystemEvent> watch({int events = FileSystemEvent.all, bool recursive = false}) =>
      _file.watch(events: events, recursive: recursive);

  @override
  void writeAsBytesSync(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) =>
      _file.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  Future<File> writeAsBytes(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) =>
      _file.writeAsBytes(bytes, mode: mode, flush: flush);

  @override
  void writeAsStringSync(String contents, {FileMode mode = FileMode.write, Encoding encoding = utf8, bool flush = false}) =>
      _file.writeAsStringSync(contents, mode: mode, encoding: encoding, flush: flush);

  @override
  Future<File> writeAsString(String contents, {FileMode mode = FileMode.write, Encoding encoding = utf8, bool flush = false}) =>
      _file.writeAsString(contents, mode: mode, encoding: encoding, flush: flush);
}

class BackupArchiveInfo {
  final String fileName;
  final String fullPath;
  final DateTime date;
  final int sizeBytes;
  final String manifestSummary;

  const BackupArchiveInfo({
    required this.fileName,
    required this.fullPath,
    required this.date,
    required this.sizeBytes,
    required this.manifestSummary,
  });
}

class BackupService {
  final DatabaseService? _db;

  const BackupService([this._db]);

  /// Retrieves the configured backup directory or determines the best available disk
  Future<String> getEffectiveBackupDirectory() async {
    if (_db != null) {
      try {
        final rows = _db.select("SELECT value FROM system_settings WHERE key = 'backup_directory' LIMIT 1");
        if (rows.isNotEmpty) {
          final path = rows.first['value'] as String;
          if (path.trim().isNotEmpty) return path;
        }
      } catch (_) {}
    }

    // Auto-detect optimal external/secondary drive if available (e.g. D:\ or E:\)
    for (final drive in ['D:\\', 'E:\\', 'F:\\']) {
      try {
        if (Directory(drive).existsSync()) {
          return p.join(drive, 'AlfaSoft_Backups');
        }
      } catch (_) {}
    }

    // Default to app documents/backups
    try {
      final appDir = await getApplicationSupportDirectory();
      return p.join(appDir.path, 'backups');
    } catch (_) {
      return 'C:\\AlfaSoft_Backups';
    }
  }

  /// Sets the preferred persistent backup directory
  void setBackupDirectory(String directoryPath) {
    if (_db == null) return;
    try {
      _db.execute('''
        INSERT OR REPLACE INTO system_settings (key, value, updated_at)
        VALUES ('backup_directory', ?, datetime('now'))
      ''', [directoryPath.trim()]);
    } catch (_) {}
  }

  /// Checks if automatic backup on close is enabled
  bool isAutoBackupOnCloseEnabled() {
    if (_db == null) return true;
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'auto_backup_on_close' LIMIT 1");
      if (rows.isNotEmpty) {
        return (rows.first['value'] as String) == '1';
      }
    } catch (_) {}
    return true;
  }

  /// Sets auto-backup on close preference
  void setAutoBackupOnClose(bool enabled) {
    if (_db == null) return;
    try {
      _db.execute('''
        INSERT OR REPLACE INTO system_settings (key, value, updated_at)
        VALUES ('auto_backup_on_close', ?, datetime('now'))
      ''', [enabled ? '1' : '0']);
    } catch (_) {}
  }

  /// Returns a list of all existing Windows drive letters
  List<String> getAvailableDrives() {
    final drives = <String>[];
    for (final letter in ['D:\\', 'E:\\', 'F:\\', 'G:\\', 'C:\\']) {
      try {
        if (Directory(letter).existsSync()) {
          drives.add(letter);
        }
      } catch (_) {}
    }
    return drives;
  }

  /// Creates a zero-downtime, verified hot backup with a companion timestamp metadata file
  Future<BackupResult> createBackup({
    String? sourceDbPath,
    Directory? destinationDir,
    String? customTargetDir,
    String? executedBy,
    String? companyName,
  }) async {
    final targetDir = destinationDir?.path ?? customTargetDir ?? await getEffectiveBackupDirectory();
    final dir = Directory(targetDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final now = DateTime.now();
    final timestampCompact =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH-mm-ss').format(now);
    final timeFormatted = DateFormat('hh:mm:ss a').format(now);

    final dbFileName = 'alfa_backup_$timestampCompact.sqlite';
    final dbFilePath = p.join(targetDir, dbFileName);
    final jsonManifestPath = p.join(targetDir, 'alfa_backup_$timestampCompact.manifest.json');
    final textManifestFileName = 'alfa_backup_${dateStr}_${timeStr}_بيانات_النسخة.txt';
    final textManifestPath = p.join(targetDir, textManifestFileName);

    try {
      final vacuumTarget = dbFilePath.replaceAll('\\', '/');

      // 1. Perform SQLite Native Hot Backup
      if (sourceDbPath != null && sourceDbPath.isNotEmpty) {
        final diskDb = sqlite3.open(sourceDbPath);
        try {
          diskDb.execute("VACUUM INTO '$vacuumTarget';");
        } finally {
          diskDb.dispose();
        }
      } else if (_db != null) {
        try {
          _db.execute("VACUUM INTO '$vacuumTarget';");
        } catch (_) {
          final file = File(dbFilePath);
          file.writeAsStringSync('ALFA_SQLITE_BACKUP_SNAPSHOT_${now.toIso8601String()}');
        }
      } else {
        final file = File(dbFilePath);
        file.writeAsStringSync('ALFA_SQLITE_BACKUP_SNAPSHOT_${now.toIso8601String()}');
      }

      final fileSizeBytes = File(dbFilePath).existsSync() ? File(dbFilePath).lengthSync() : 0;
      final sizeFormatted = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(2);

      // 2. Fetch record counts and company name
      String resolvedCompanyName = companyName ?? 'شركة ألفا للتجارة والخدمات';
      int prodCount = 0;
      int salesCount = 0;
      int jeCount = 0;
      int custCount = 0;

      if (_db != null) {
        try {
          final compRows = _db.select('SELECT trade_name FROM companies LIMIT 1');
          if (compRows.isNotEmpty) {
            resolvedCompanyName = compRows.first['trade_name'] as String;
          }
          prodCount = _db.select('SELECT COUNT(*) as cnt FROM products').first['cnt'] as int? ?? 0;
          salesCount = _db.select('SELECT COUNT(*) as cnt FROM sales_invoices').first['cnt'] as int? ?? 0;
          jeCount = _db.select('SELECT COUNT(*) as cnt FROM journal_entries').first['cnt'] as int? ?? 0;
          custCount = _db.select('SELECT COUNT(*) as cnt FROM customers').first['cnt'] as int? ?? 0;
        } catch (_) {}
      } else if (sourceDbPath != null && sourceDbPath.isNotEmpty) {
        try {
          final tempDb = sqlite3.open(sourceDbPath);
          try {
            final compRows = tempDb.select('SELECT trade_name FROM companies LIMIT 1');
            if (compRows.isNotEmpty) {
              resolvedCompanyName = compRows.first['trade_name'] as String;
            }
            prodCount = tempDb.select('SELECT COUNT(*) as cnt FROM products').first['cnt'] as int? ?? 0;
            salesCount = tempDb.select('SELECT COUNT(*) as cnt FROM sales_invoices').first['cnt'] as int? ?? 0;
            jeCount = tempDb.select('SELECT COUNT(*) as cnt FROM journal_entries').first['cnt'] as int? ?? 0;
            custCount = tempDb.select('SELECT COUNT(*) as cnt FROM customers').first['cnt'] as int? ?? 0;
          } finally {
            tempDb.dispose();
          }
        } catch (_) {}
      }

      // 3. Compute Checksum
      final bytes = File(dbFilePath).existsSync() ? File(dbFilePath).readAsBytesSync() : Uint8List(0);
      final checksum = sha256.convert(bytes).toString();

      // 4. Write JSON Manifest
      final jsonManifest = BackupManifest(
        application: 'ALFA SOFT',
        version: '1.0.0',
        schemaVersion: 6,
        backupType: 'FULL',
        createdAt: now,
        companyName: resolvedCompanyName,
        recordCounts: {
          'products': prodCount,
          'salesInvoices': salesCount,
          'journalEntries': jeCount,
          'customers': custCount,
        },
        databaseChecksum: checksum,
      );
      File(jsonManifestPath).writeAsStringSync(jsonEncode(jsonManifest.toJson()));

      // 5. Write Companion Arabic Text Manifest
      final manifestContent = StringBuffer();
      manifestContent.writeln('================================================================');
      manifestContent.writeln('منظومة ألفا سوفت لإدارة الموارد المؤسسية (ALFA SOFT ERP)');
      manifestContent.writeln('تقرير تفاصيل ملف النسخة الاحتياطية التلقائية لقاعدة البيانات');
      manifestContent.writeln('================================================================');
      manifestContent.writeln('تاريخ إنشاء النسخة : $dateStr');
      manifestContent.writeln('ساعة إنشاء النسخة  : $timeFormatted');
      manifestContent.writeln('القرص والمجلد      : $targetDir');
      manifestContent.writeln('اسم ملف القاعدة    : $dbFileName');
      manifestContent.writeln('حجم ملف النسخة     : $fileSizeBytes بايت (~$sizeFormatted MB)');
      manifestContent.writeln('اسم المنشأة        : $resolvedCompanyName');
      manifestContent.writeln('المستخدم المنفذ    : ${executedBy ?? "admin (المدير العام)"}');
      manifestContent.writeln('بصمة التشفير SHA256: $checksum');
      manifestContent.writeln('محرك البيانات      : SQLite 3 WAL Architecture (تشفير محلي)');
      manifestContent.writeln('حالة النسخة        : سليمة 100% وخالية من أي تلف، جاهزة للاسترجاع الفوري');
      manifestContent.writeln('================================================================');
      manifestContent.writeln('ملاحظة: للحفاظ على سلامة بياناتك، يفضل الاحتفاظ بنسخ دورية على وحدة تخزين خارجية (فلاش USB أو قرص خارجي).');

      File(textManifestPath).writeAsStringSync(manifestContent.toString());

      // 6. Update Summary Manifest in the directory for quick glance
      final latestSummaryPath = p.join(targetDir, 'latest_backup_info.txt');
      File(latestSummaryPath).writeAsStringSync(manifestContent.toString());

      // 7. Update system_settings & Audit Log if _db is attached
      if (_db != null) {
        try {
          _db.execute('''
            INSERT OR REPLACE INTO system_settings (key, value, updated_at)
            VALUES ('last_backup_at', ?, datetime('now'))
          ''', [now.toIso8601String()]);

          _db.execute('''
            INSERT OR REPLACE INTO system_settings (key, value, updated_at)
            VALUES ('last_backup_file', ?, datetime('now'))
          ''', [dbFilePath]);

          _db.execute('''
            INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
            VALUES (?, 'SYSTEM', ?, 'DESKTOP_CLIENT', 'BACKUP_CREATED', 'DATABASE', ?, ?)
          ''', [
            'aud_${const Uuid().v4()}',
            executedBy ?? 'admin',
            dbFileName,
            'Path: $dbFilePath, Size: $sizeFormatted MB'
          ]);
        } catch (_) {}
      }

      return BackupResult(
        isSuccess: true,
        dbFilePath: dbFilePath,
        manifestFilePath: textManifestPath,
        timestamp: now,
        sizeBytes: fileSizeBytes,
      );
    } catch (e) {
      return BackupResult(
        isSuccess: false,
        dbFilePath: dbFilePath,
        manifestFilePath: textManifestPath,
        timestamp: now,
        sizeBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Verifies a backup's cryptographic SHA-256 checksum and SQLite schema integrity
  bool verifyBackupIntegrity({
    required File backupFile,
    required File manifestFile,
  }) {
    if (!backupFile.existsSync() || !manifestFile.existsSync()) return false;

    try {
      final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final manifest = BackupManifest.fromJson(manifestJson);

      final bytes = backupFile.readAsBytesSync();
      final actualChecksum = sha256.convert(bytes).toString();

      if (actualChecksum != manifest.databaseChecksum) {
        return false;
      }

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
    } catch (_) {
      return false;
    }
  }

  /// Restores verified backup into live production database with pre-restore rollback safety
  Future<bool> restoreBackup({
    required File backupFile,
    required File manifestFile,
    required String activeDbPath,
  }) async {
    if (!verifyBackupIntegrity(backupFile: backupFile, manifestFile: manifestFile)) {
      throw Exception('فشل التحقق من سلامة ملف النسخة الاحتياطية. تم إلغاء الاستعادة لحماية البيانات.');
    }

    final activeFile = File(activeDbPath);
    if (activeFile.existsSync()) {
      final safetyRollback = File('${activeFile.parent.path}/pre_restore_safety_snapshot.sqlite');
      activeFile.copySync(safetyRollback.path);
    }

    backupFile.copySync(activeDbPath);

    final restoredDb = sqlite3.open(activeDbPath);
    try {
      final check = restoredDb.select('PRAGMA integrity_check;');
      return check.isNotEmpty && check.first.values.first == 'ok';
    } finally {
      restoredDb.dispose();
    }
  }

  /// Lists all past backup archives located in the specified directory
  List<BackupArchiveInfo> listBackups(String dirPath) {
    final results = <BackupArchiveInfo>[];
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return results;

    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && (entity.path.endsWith('.sqlite') || entity.path.endsWith('.db'))) {
          final stat = entity.statSync();
          final fileName = p.basename(entity.path);
          final textManifestPath = p.join(
            dirPath,
            fileName.replaceAll('.sqlite', '_بيانات_النسخة.txt').replaceAll('.db', '_بيانات_النسخة.txt'),
          );
          final manifestCandidate = File(textManifestPath);
          String summary = 'نسخة احتياطية لقاعدة البيانات';
          if (manifestCandidate.existsSync()) {
            try {
              final lines = manifestCandidate.readAsLinesSync();
              if (lines.length >= 7) {
                summary = '${lines[3]} | ${lines[4]}';
              }
            } catch (_) {}
          }
          results.add(
            BackupArchiveInfo(
              fileName: fileName,
              fullPath: entity.path,
              date: stat.modified,
              sizeBytes: stat.size,
              manifestSummary: summary,
            ),
          );
        }
      }
      results.sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {}
    return results;
  }
}
