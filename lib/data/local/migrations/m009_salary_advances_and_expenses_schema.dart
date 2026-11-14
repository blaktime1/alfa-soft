import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M009SalaryAdvancesAndExpensesSchema extends Migration {
  const M009SalaryAdvancesAndExpensesSchema()
      : super(version: 9, name: 'Salary Advances and Direct Expense Vouchers');

  @override
  void up(Database db) {
    db.execute('''
      -- Salary Advances Table
      CREATE TABLE IF NOT EXISTS salary_advances (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
        advance_number TEXT NOT NULL UNIQUE,
        amount_cents INTEGER NOT NULL,
        payment_account_id TEXT REFERENCES chart_of_accounts(id) ON DELETE SET NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        request_date TEXT NOT NULL,
        repayment_month TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        notes TEXT,
        payroll_run_id TEXT REFERENCES payroll_runs(id) ON DELETE SET NULL,
        journal_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL,
        created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      -- Direct Expense Vouchers Table
      CREATE TABLE IF NOT EXISTS expense_vouchers (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT REFERENCES branches(id) ON DELETE SET NULL,
        voucher_number TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL,
        expense_account_id TEXT REFERENCES chart_of_accounts(id) ON DELETE SET NULL,
        payment_account_id TEXT REFERENCES chart_of_accounts(id) ON DELETE SET NULL,
        amount_cents INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        reference_no TEXT,
        description TEXT NOT NULL,
        voucher_date TEXT NOT NULL,
        journal_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL,
        cost_center_id TEXT REFERENCES cost_centers(id) ON DELETE SET NULL,
        created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');
  }

  @override
  void down(Database db) {
    db.execute('DROP TABLE IF EXISTS salary_advances;');
    db.execute('DROP TABLE IF EXISTS expense_vouchers;');
  }
}
