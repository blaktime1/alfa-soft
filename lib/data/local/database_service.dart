import 'package:sqlite3/sqlite3.dart';
import 'migrations/migration.dart';
import 'migrations/m001_initial_schema.dart';
import 'migrations/m002_catalog_inventory_schema.dart';
import 'migrations/m003_sales_pos_accounting_schema.dart';
import 'migrations/m004_purchasing_transfers_schema.dart';
import 'migrations/m005_enterprise_features_schema.dart';
import 'migrations/m006_system_settings_and_backup_schema.dart';

class DatabaseService {
  final Database _db;
  final bool _isInMemory;

  DatabaseService._(this._db, this._isInMemory);

  Database get rawDb => _db;

  /// Creates an in-memory SQLite database instance (primarily for testing)
  factory DatabaseService.inMemory() {
    final db = sqlite3.openInMemory();
    final service = DatabaseService._(db, true);
    service._configurePragmas();
    service._runMigrations();
    return service;
  }

  /// Opens a persistent SQLite database file on disk with WAL mode
  factory DatabaseService.openFile(String path) {
    final db = sqlite3.open(path);
    final service = DatabaseService._(db, false);
    service._configurePragmas();
    service._runMigrations();
    return service;
  }

  void _configurePragmas() {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA busy_timeout = 5000;');
    if (!_isInMemory) {
      _db.execute('PRAGMA journal_mode = WAL;');
      _db.execute('PRAGMA synchronous = NORMAL;');
      _db.execute('PRAGMA cache_size = -64000;'); // ~64MB cache
    }
  }

  void _runMigrations() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');

    final appliedVersions = <int>{};
    final result = _db.select('SELECT version FROM schema_migrations ORDER BY version ASC');
    for (final row in result) {
      appliedVersions.add(row['version'] as int);
    }

    final availableMigrations = <Migration>[
      const M001InitialSchema(),
      const M002CatalogInventorySchema(),
      const M003SalesPosAccountingSchema(),
      const M004PurchasingTransfersSchema(),
      const M005EnterpriseFeaturesSchema(),
      const M006SystemSettingsAndBackupSchema(),
    ]..sort((a, b) => a.version.compareTo(b.version));

    for (final migration in availableMigrations) {
      if (!appliedVersions.contains(migration.version)) {
        transaction((db) {
          migration.up(db);
          db.execute(
            'INSERT INTO schema_migrations (version, name) VALUES (?, ?)',
            [migration.version, migration.name],
          );
        });
      }
    }
  }

  /// Executes an atomic database transaction. If an exception occurs, changes are rolled back.
  T transaction<T>(T Function(Database db) action) {
    _db.execute('BEGIN TRANSACTION');
    try {
      final result = action(_db);
      _db.execute('COMMIT');
      return result;
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Executes a parameterized query and returns rows
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    return _db.select(sql, parameters);
  }

  /// Executes a statement (INSERT, UPDATE, DELETE)
  void execute(String sql, [List<Object?> parameters = const []]) {
    _db.execute(sql, parameters);
  }

  /// Performs integrity check on the database
  bool checkIntegrity() {
    final result = _db.select('PRAGMA integrity_check;');
    if (result.isNotEmpty && result.first.values.first == 'ok') {
      return true;
    }
    return false;
  }

  void dispose() {
    _db.dispose();
  }
}
