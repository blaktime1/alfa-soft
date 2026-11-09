import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Database Service & Migration Tests', () {
    late DatabaseService dbService;

    setUp(() {
      dbService = DatabaseService.inMemory();
    });

    tearDown(() {
      dbService.dispose();
    });

    test('All migrations run successfully and schema tables exist', () {
      expect(dbService.checkIntegrity(), isTrue);

      final tablesResult = dbService.select('''
        SELECT name FROM sqlite_master WHERE type='table'
      ''');
      final tableNames = tablesResult.map((r) => r['name'] as String).toSet();

      expect(tableNames, containsAll([
        'schema_migrations',
        'companies',
        'branches',
        'warehouses',
        'users',
        'roles',
        'role_permissions',
        'audit_logs',
        'units',
        'categories',
        'products',
        'inventory_balances',
        'inventory_movements',
        'customers',
        'suppliers',
        'pos_shifts',
        'sales_invoices',
        'sales_invoice_items',
        'payments',
        'chart_of_accounts',
        'journal_entries',
        'journal_lines',
        'sync_outbox',
        'purchase_orders',
        'purchase_order_items',
        'goods_receipt_notes',
        'goods_receipt_items',
        'stock_transfers',
        'stock_transfer_items',
        'stock_adjustments',
        'pos_suspended_sales',
        'cost_centers',
        'employees',
        'payroll_runs',
        'salary_slips',
        'approval_requests',
        'approval_steps',
        'system_settings',
      ]));

      // Verify migration table recorded all 6 migrations
      final migrations = dbService.select('SELECT version FROM schema_migrations ORDER BY version ASC');
      expect(migrations.length, equals(6));
    });

    test('Foreign key constraints are strictly enforced', () {
      // Attempting to insert a branch without an existing company must throw an exception
      expect(() {
        dbService.execute('''
          INSERT INTO branches (id, company_id, code, name)
          VALUES ('br_1', 'comp_non_existent', 'BR01', 'Main Branch')
        ''');
      }, throwsA(isA<SqliteException>()));
    });

    test('Transactions roll back completely on failure', () {
      // Insert a valid company
      dbService.execute('''
        INSERT INTO companies (id, legal_name, trade_name)
        VALUES ('comp_1', 'شركة ألفا المحدودة', 'ألفا سوفت')
      ''');

      try {
        dbService.transaction((db) {
          db.execute('''
            INSERT INTO branches (id, company_id, code, name)
            VALUES ('br_1', 'comp_1', 'BR01', 'Branch 1')
          ''');

          // Simulate mid-transaction error (foreign key violation or intentional throw)
          throw Exception('Intentional mid-transaction failure');
        });
      } catch (_) {
        // Expected
      }

      // Verify branch was NOT saved due to rollback
      final branches = dbService.select('SELECT * FROM branches WHERE id = ?', ['br_1']);
      expect(branches, isEmpty);
    });

    test('Audit logging inserts valid snapshot payloads', () {
      dbService.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, previous_state, new_state)
        VALUES ('aud_1', 'comp_1', 'usr_admin', 'dev_pos1', 'PRICE_CHANGE', 'PRODUCT', 'prod_1', '{"price": 100}', '{"price": 120}')
      ''');

      final logs = dbService.select('SELECT action, entity_name FROM audit_logs WHERE id = ?', ['aud_1']);
      expect(logs.first['action'], equals('PRICE_CHANGE'));
      expect(logs.first['entity_name'], equals('PRODUCT'));
    });
  });
}
