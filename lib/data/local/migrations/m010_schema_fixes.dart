import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M010SchemaFixes extends Migration {
  const M010SchemaFixes()
      : super(version: 10, name: 'Expense Vouchers Status and Branch Warehouses Fix');

  @override
  void up(Database db) {
    // 1. Ensure expense_vouchers table has status column
    final cols = db.select('PRAGMA table_info(expense_vouchers)');
    final hasStatus = cols.any((c) => c['name'] == 'status');
    if (!hasStatus) {
      db.execute("ALTER TABLE expense_vouchers ADD COLUMN status TEXT NOT NULL DEFAULT 'POSTED';");
    }

    // 2. Mark any expense_vouchers whose journal entry is reversed as CANCELLED
    try {
      db.execute('''
        UPDATE expense_vouchers 
        SET status = 'CANCELLED' 
        WHERE journal_entry_id IN (
          SELECT id FROM journal_entries WHERE status = 'REVERSED'
        );
      ''');
    } catch (_) {}

    // 3. Ensure every active branch has at least one warehouse
    try {
      final branches = db.select('SELECT id, name FROM branches WHERE is_active = 1');
      for (final b in branches) {
        final bId = b['id'] as String;
        final bName = b['name'] as String;
        final whs = db.select('SELECT id FROM warehouses WHERE branch_id = ? AND is_active = 1', [bId]);
        if (whs.isEmpty) {
          final prefix = bId.length >= 8 ? bId.substring(0, 8) : bId;
          final newWhId = 'wh_auto_$prefix';
          db.execute('''
            INSERT OR IGNORE INTO warehouses (id, branch_id, code, name, is_active, created_at, updated_at, version)
            VALUES (?, ?, ?, ?, 1, datetime('now'), datetime('now'), 1)
          ''', [newWhId, bId, 'WH-${prefix.substring(0, 4).toUpperCase()}', 'المستودع الرئيسي ($bName)']);
        }
      }
    } catch (_) {}
  }

  @override
  void down(Database db) {
    // SQLite does not support DROP COLUMN cleanly in older versions, nothing to revert
  }
}
