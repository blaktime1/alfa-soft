import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M006SystemSettingsAndBackupSchema extends Migration {
  const M006SystemSettingsAndBackupSchema()
      : super(version: 6, name: 'System Settings, Auto-Backup Configuration and User Permissions');

  @override
  void up(Database db) {
    db.execute('''
      -- Key-Value System Settings Table
      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      -- Seed Default System Preferences
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('auto_backup_on_close', '1');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('backup_directory', 'D:\\AlfaSoft_Backups');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('printer_paper_size', '80mm');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('printer_auto_print', '1');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('printer_auto_cut', '1');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('printer_drawer_kick', '1');
      INSERT OR IGNORE INTO system_settings (key, value) VALUES ('zatca_qr_enabled', '1');
    ''');
  }

  @override
  void down(Database db) {
    db.execute('DROP TABLE IF EXISTS system_settings;');
  }
}
