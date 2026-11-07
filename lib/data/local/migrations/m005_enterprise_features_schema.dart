import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M005EnterpriseFeaturesSchema extends Migration {
  const M005EnterpriseFeaturesSchema()
      : super(version: 5, name: 'Enterprise Features: Cost Centers, HR Payroll, and Multi-Tier Approvals');

  @override
  void up(Database db) {
    db.execute('''
      -- Cost Centers Table
      CREATE TABLE IF NOT EXISTS cost_centers (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, code)
      );

      -- Employees Table
      CREATE TABLE IF NOT EXISTS employees (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        employee_code TEXT NOT NULL,
        full_name TEXT NOT NULL,
        national_id TEXT NOT NULL,
        job_title TEXT NOT NULL,
        department TEXT NOT NULL,
        hire_date TEXT NOT NULL DEFAULT (date('now')),
        basic_salary INTEGER NOT NULL DEFAULT 0, -- Stored in minor currency units (cents/halalas)
        housing_allowance INTEGER NOT NULL DEFAULT 0,
        transport_allowance INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'ON_LEAVE', 'TERMINATED'
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, employee_code)
      );

      -- Employee Attendance Records
      CREATE TABLE IF NOT EXISTS employee_attendance (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
        attendance_date TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        status TEXT NOT NULL DEFAULT 'PRESENT', -- 'PRESENT', 'ABSENT', 'LATE', 'LEAVE'
        overtime_hours REAL NOT NULL DEFAULT 0.0,
        notes TEXT,
        UNIQUE(employee_id, attendance_date)
      );

      -- Payroll Runs Table
      CREATE TABLE IF NOT EXISTS payroll_runs (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        period_month TEXT NOT NULL, -- Format: 'YYYY-MM'
        total_gross INTEGER NOT NULL DEFAULT 0,
        total_deductions INTEGER NOT NULL DEFAULT 0,
        total_net INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'DRAFT', -- 'DRAFT', 'APPROVED', 'POSTED_TO_JOURNAL'
        approved_by_user_id TEXT REFERENCES users(id) ON DELETE RESTRICT,
        posted_journal_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, period_month)
      );

      -- Salary Slips Table
      CREATE TABLE IF NOT EXISTS salary_slips (
        id TEXT PRIMARY KEY,
        payroll_run_id TEXT NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
        employee_id TEXT NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
        basic_salary INTEGER NOT NULL,
        allowances INTEGER NOT NULL DEFAULT 0,
        deductions INTEGER NOT NULL DEFAULT 0,
        net_salary INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'BANK_TRANSFER', -- 'BANK_TRANSFER', 'CASH'
        notes TEXT
      );

      -- Approval Requests Table
      CREATE TABLE IF NOT EXISTS approval_requests (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        document_type TEXT NOT NULL, -- 'PURCHASE_ORDER', 'STOCK_ADJUSTMENT', 'PAYROLL'
        document_id TEXT NOT NULL,
        request_number TEXT NOT NULL,
        amount INTEGER NOT NULL DEFAULT 0, -- Value of document in cents
        status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'APPROVED', 'REJECTED'
        current_step_level INTEGER NOT NULL DEFAULT 1,
        required_step_levels INTEGER NOT NULL DEFAULT 1,
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, request_number)
      );

      -- Approval Steps History Table
      CREATE TABLE IF NOT EXISTS approval_steps (
        id TEXT PRIMARY KEY,
        approval_request_id TEXT NOT NULL REFERENCES approval_requests(id) ON DELETE CASCADE,
        step_level INTEGER NOT NULL,
        approver_user_id TEXT REFERENCES users(id) ON DELETE RESTRICT,
        role_required TEXT NOT NULL, -- 'MANAGER', 'FINANCE', 'DIRECTOR'
        decision TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'APPROVED', 'REJECTED'
        decision_date TEXT,
        comments TEXT
      );

      -- Custom Entity Metadata Fields
      CREATE TABLE IF NOT EXISTS custom_fields_metadata (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        target_entity TEXT NOT NULL, -- 'PRODUCT', 'CUSTOMER', 'SUPPLIER', 'EMPLOYEE'
        field_name TEXT NOT NULL,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL DEFAULT 'TEXT', -- 'TEXT', 'NUMBER', 'BOOLEAN', 'DATE'
        is_required INTEGER NOT NULL DEFAULT 0,
        UNIQUE(company_id, target_entity, field_name)
      );
    ''');
  }

  @override
  void down(Database db) {
    db.execute('''
      DROP TABLE IF EXISTS custom_fields_metadata;
      DROP TABLE IF EXISTS approval_steps;
      DROP TABLE IF EXISTS approval_requests;
      DROP TABLE IF EXISTS salary_slips;
      DROP TABLE IF EXISTS payroll_runs;
      DROP TABLE IF EXISTS employee_attendance;
      DROP TABLE IF EXISTS employees;
      DROP TABLE IF EXISTS cost_centers;
    ''');
  }
}
