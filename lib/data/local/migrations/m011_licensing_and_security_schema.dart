import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M011LicensingAndSecuritySchema extends Migration {
  const M011LicensingAndSecuritySchema()
      : super(version: 11, name: 'Offline Ed25519 Cryptographic Licensing & Clock Tamper Detection');

  @override
  void up(Database db) {
    db.execute('''
      -- Dedicated Cryptographic License Store Table
      CREATE TABLE IF NOT EXISTS system_licenses (
        id TEXT PRIMARY KEY,
        licensee TEXT NOT NULL,
        hardware_id TEXT NOT NULL,
        tier TEXT NOT NULL DEFAULT 'ENTERPRISE',
        plan_type TEXT NOT NULL DEFAULT 'LIFETIME',
        issued_at TEXT NOT NULL,
        expires_at TEXT NOT NULL DEFAULT 'LIFETIME',
        modules TEXT NOT NULL,
        raw_package TEXT NOT NULL,
        signature TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        installed_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      -- System Clock Tamper Guard Table
      CREATE TABLE IF NOT EXISTS system_security_clocks (
        key TEXT PRIMARY KEY,
        last_recorded_utc TEXT NOT NULL,
        tamper_flags INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      INSERT OR IGNORE INTO system_security_clocks (key, last_recorded_utc, tamper_flags)
      VALUES ('MASTER_CLOCK', datetime('now'), 0);
    ''');
  }

  @override
  void down(Database db) {
    db.execute('DROP TABLE IF EXISTS system_licenses;');
    db.execute('DROP TABLE IF EXISTS system_security_clocks;');
  }
}
