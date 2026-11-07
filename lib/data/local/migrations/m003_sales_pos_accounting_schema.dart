import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M003SalesPosAccountingSchema extends Migration {
  const M003SalesPosAccountingSchema()
      : super(version: 3, name: 'Sales, POS Shifts, General Ledger and Outbox Schema');

  @override
  void up(Database db) {
    db.execute('''
      -- Customers Table
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        tax_number TEXT,
        credit_limit INTEGER NOT NULL DEFAULT 0,
        current_balance INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, code)
      );

      -- Suppliers Table
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        tax_number TEXT,
        current_balance INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, code)
      );

      -- POS Shifts Table
      CREATE TABLE IF NOT EXISTS pos_shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        opened_at TEXT NOT NULL DEFAULT (datetime('now')),
        closed_at TEXT,
        starting_cash INTEGER NOT NULL DEFAULT 0,
        expected_cash INTEGER NOT NULL DEFAULT 0,
        actual_cash INTEGER,
        difference INTEGER,
        status TEXT NOT NULL DEFAULT 'OPEN',
        notes TEXT
      );

      -- Sales Invoices Table
      CREATE TABLE IF NOT EXISTS sales_invoices (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        pos_shift_id TEXT REFERENCES pos_shifts(id) ON DELETE SET NULL,
        customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
        invoice_number TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        subtotal INTEGER NOT NULL DEFAULT 0,
        tax_total INTEGER NOT NULL DEFAULT 0,
        discount_total INTEGER NOT NULL DEFAULT 0,
        grand_total INTEGER NOT NULL DEFAULT 0,
        paid_total INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'POSTED',
        payment_status TEXT NOT NULL DEFAULT 'PAID',
        qr_code_payload TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, invoice_number)
      );

      -- Sales Invoice Items Table
      CREATE TABLE IF NOT EXISTS sales_invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL,
        unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
        unit_price INTEGER NOT NULL,
        cost_price INTEGER NOT NULL,
        discount_amount INTEGER NOT NULL DEFAULT 0,
        tax_rate INTEGER NOT NULL DEFAULT 0,
        tax_amount INTEGER NOT NULL DEFAULT 0,
        line_total INTEGER NOT NULL
      );

      -- Payments Table
      CREATE TABLE IF NOT EXISTS payments (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        amount INTEGER NOT NULL,
        reference_number TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
      );

      -- Chart of Accounts Table
      CREATE TABLE IF NOT EXISTS chart_of_accounts (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        account_type TEXT NOT NULL,
        parent_id TEXT REFERENCES chart_of_accounts(id) ON DELETE RESTRICT,
        is_leaf INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        current_balance INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, code)
      );

      -- Journal Entries Table (Header)
      CREATE TABLE IF NOT EXISTS journal_entries (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        entry_number TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT,
        narration TEXT NOT NULL,
        total_debit INTEGER NOT NULL,
        total_credit INTEGER NOT NULL,
        is_balanced INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'POSTED',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        CHECK(total_debit = total_credit),
        UNIQUE(company_id, entry_number)
      );

      -- Journal Lines Table
      CREATE TABLE IF NOT EXISTS journal_lines (
        id TEXT PRIMARY KEY,
        journal_entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
        account_id TEXT NOT NULL REFERENCES chart_of_accounts(id) ON DELETE RESTRICT,
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        memo TEXT,
        CHECK((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
      );
      CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);

      -- Sync Outbox Table
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        sequence_number INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_outbox_status ON sync_outbox(sync_status);
    ''');
  }

  @override
  void down(Database db) {
    db.execute('''
      DROP TABLE IF EXISTS sync_outbox;
      DROP TABLE IF EXISTS journal_lines;
      DROP TABLE IF EXISTS journal_entries;
      DROP TABLE IF EXISTS chart_of_accounts;
      DROP TABLE IF EXISTS payments;
      DROP TABLE IF EXISTS sales_invoice_items;
      DROP TABLE IF EXISTS sales_invoices;
      DROP TABLE IF EXISTS pos_shifts;
      DROP TABLE IF EXISTS suppliers;
      DROP TABLE IF EXISTS customers;
    ''');
  }
}
