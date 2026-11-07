import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M001InitialSchema extends Migration {
  const M001InitialSchema()
      : super(version: 1, name: 'Initial Organization, Identity and Audit Schema');

  @override
  void up(Database db) {
    db.execute('''
      -- Companies Table
      CREATE TABLE IF NOT EXISTS companies (
        id TEXT PRIMARY KEY,
        legal_name TEXT NOT NULL,
        trade_name TEXT NOT NULL,
        tax_number TEXT,
        commercial_registration TEXT,
        currency_code TEXT NOT NULL DEFAULT 'SAR',
        logo_path TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1
      );

      -- Branches Table
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        is_main INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, code)
      );

      -- Warehouses Table
      CREATE TABLE IF NOT EXISTS warehouses (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(branch_id, code)
      );

      -- Users Table
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        username TEXT NOT NULL,
        email TEXT,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        phone TEXT,
        is_admin INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, username)
      );

      -- Roles Table
      CREATE TABLE IF NOT EXISTS roles (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, name)
      );

      -- Role Permissions Table
      CREATE TABLE IF NOT EXISTS role_permissions (
        role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        permission_key TEXT NOT NULL,
        PRIMARY KEY(role_id, permission_key)
      );

      -- User Roles Table
      CREATE TABLE IF NOT EXISTS user_roles (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        branch_id TEXT REFERENCES branches(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, role_id)
      );

      -- Immutable Audit Logs Table
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        branch_id TEXT,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_name TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        previous_state TEXT,
        new_state TEXT,
        timestamp TEXT NOT NULL DEFAULT (datetime('now')),
        ip_address TEXT,
        reason TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_name, entity_id);
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);

      -- System Settings Table
      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        description TEXT,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      -- Document Sequences Table
      CREATE TABLE IF NOT EXISTS document_sequences (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        branch_id TEXT,
        document_type TEXT NOT NULL,
        prefix TEXT NOT NULL,
        current_number INTEGER NOT NULL DEFAULT 0,
        padding INTEGER NOT NULL DEFAULT 6,
        reset_period TEXT NOT NULL DEFAULT 'YEARLY',
        last_reset_year INTEGER NOT NULL DEFAULT 2026,
        UNIQUE(company_id, branch_id, document_type)
      );
    ''');
  }

  @override
  void down(Database db) {
    db.execute('''
      DROP TABLE IF EXISTS document_sequences;
      DROP TABLE IF EXISTS system_settings;
      DROP TABLE IF EXISTS audit_logs;
      DROP TABLE IF EXISTS user_roles;
      DROP TABLE IF EXISTS role_permissions;
      DROP TABLE IF EXISTS roles;
      DROP TABLE IF EXISTS users;
      DROP TABLE IF EXISTS warehouses;
      DROP TABLE IF EXISTS branches;
      DROP TABLE IF EXISTS companies;
    ''');
  }
}
