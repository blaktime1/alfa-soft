import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M008InvoiceManagementAndPosPreferencesSchema extends Migration {
  const M008InvoiceManagementAndPosPreferencesSchema()
      : super(version: 8, name: 'Invoice Management, POS Policy, and Multi-Style POS Schema');

  @override
  void up(Database db) {
    // 1. Extend sales_invoices table
    final salesInvoiceColumns = [
      "ALTER TABLE sales_invoices ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'YER';",
      "ALTER TABLE sales_invoices ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0;",
      "ALTER TABLE sales_invoices ADD COLUMN price_level TEXT NOT NULL DEFAULT 'RETAIL';",
      "ALTER TABLE sales_invoices ADD COLUMN salesman_id TEXT REFERENCES users(id);",
      "ALTER TABLE sales_invoices ADD COLUMN reference_note TEXT;",
      "ALTER TABLE sales_invoices ADD COLUMN notes TEXT;",
      "ALTER TABLE sales_invoices ADD COLUMN bonus_total INTEGER NOT NULL DEFAULT 0;",
      "ALTER TABLE sales_invoices ADD COLUMN voided_at TEXT;",
      "ALTER TABLE sales_invoices ADD COLUMN voided_by_user_id TEXT REFERENCES users(id);",
      "ALTER TABLE sales_invoices ADD COLUMN void_reason TEXT;",
      "ALTER TABLE sales_invoices ADD COLUMN is_posted INTEGER NOT NULL DEFAULT 1;",
    ];

    for (final col in salesInvoiceColumns) {
      try {
        db.execute(col);
      } catch (_) {}
    }

    // 2. Extend sales_invoice_items table
    final salesItemColumns = [
      "ALTER TABLE sales_invoice_items ADD COLUMN bonus_quantity INTEGER NOT NULL DEFAULT 0;",
      "ALTER TABLE sales_invoice_items ADD COLUMN batch_number TEXT;",
      "ALTER TABLE sales_invoice_items ADD COLUMN expiry_date TEXT;",
      "ALTER TABLE sales_invoice_items ADD COLUMN unit_name TEXT;",
    ];

    for (final col in salesItemColumns) {
      try {
        db.execute(col);
      } catch (_) {}
    }

    // 3. System settings defaults for POS interface and edit/void policies
    final defaultSettings = [
      ("pos_interface_style", "QUICK"), // 'QUICK' or 'STANDARD'
      ("pos_edit_policy", "TODAY"), // 'TODAY', 'TIMED', 'COUNT', 'ADMIN_ONLY'
      ("pos_edit_window_minutes", "30"),
      ("pos_edit_max_invoices", "5"),
    ];

    for (final setting in defaultSettings) {
      db.execute('''
        INSERT OR IGNORE INTO system_settings (key, value, updated_at)
        VALUES (?, ?, datetime('now'))
      ''', [setting.$1, setting.$2]);
    }
  }

  @override
  void down(Database db) {
    // SQLite alter column drop is not natively needed in migrations
  }
}
