import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/user_repository.dart';
import 'package:alfa_soft/core/backup/backup_service.dart';

void main() {
  group('Backup, User Management & Sync Replication Tests', () {
    late DatabaseService dbService;
    late UserRepository userRepo;
    late BackupService backupService;
    late Directory tempDir;
    final companyId = 'comp_test_backup';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alfa_backup_test_');
      dbService = DatabaseService.inMemory();
      userRepo = UserRepository(dbService);
      backupService = BackupService(dbService);

      // Seed company, branch, warehouse, customer
      dbService.execute('''
        INSERT INTO companies (id, legal_name, trade_name, tax_number)
        VALUES (?, 'Alfa Test Corp', 'شركة الفا للبرمجيات', '310999999900003')
      ''', [companyId]);

      dbService.execute('''
        INSERT INTO branches (id, company_id, code, name)
        VALUES ('br_1', ?, 'BR01', 'الفرع الرئيسي')
      ''', [companyId]);

      dbService.execute('''
        INSERT INTO warehouses (id, branch_id, code, name)
        VALUES ('wh_1', 'br_1', 'WH01', 'المستودع الرئيسي')
      ''', []);

      dbService.execute('''
        INSERT INTO customers (id, company_id, code, name, phone)
        VALUES ('cust_1', ?, 'C01', 'عميل نقدي', '0500000000')
      ''', [companyId]);
    });

    tearDown(() {
      dbService.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('Creating a user enqueues SyncOperation into sync_outbox for multi-terminal replication', () {
      final user = userRepo.createUser(
        companyId: companyId,
        username: 'cashier_salem',
        password: 'secret_password_123',
        fullName: 'سالم أحمد المحاسب',
        email: 'salem@alfa.local',
        phone: '0501234567',
        isAdmin: false,
      );

      expect(user.id, isNotEmpty);
      expect(user.username, equals('cashier_salem'));

      // Verify sync_outbox contains user creation event
      final outboxRows = dbService.select('''
        SELECT entity_type, entity_id, operation
        FROM sync_outbox
        WHERE entity_type = 'USER' AND entity_id = ?
      ''', [user.id]);

      expect(outboxRows.isNotEmpty, isTrue);
      expect(outboxRows.first['entity_type'], equals('USER'));
      expect(outboxRows.first['operation'], equals('CREATE'));
    });

    test('Creating custom role enqueues role sync event and stores granular permissions', () {
      final permissions = [
        'pos:sale',
        'pos:discount',
        'pos:refund',
        'inventory:view',
        'reports:view',
      ];

      final role = userRepo.createRole(
        companyId: companyId,
        name: 'مشرف مبيعات ومخازن',
        description: 'صلاحيات إشرافية على الفواتير والمخزون',
        permissions: permissions,
      );

      expect(role.id, isNotEmpty);
      expect(role.permissions.length, equals(5));

      // Verify role persisted
      final roleRows = dbService.select('SELECT * FROM roles WHERE id = ?', [role.id]);
      expect(roleRows.isNotEmpty, isTrue);
      expect(roleRows.first['name'], equals('مشرف مبيعات ومخازن'));

      // Verify sync_outbox event for role
      final outboxRows = dbService.select('''
        SELECT * FROM sync_outbox
        WHERE entity_type = 'ROLE' AND entity_id = ?
      ''', [role.id]);
      expect(outboxRows.isNotEmpty, isTrue);
      expect(outboxRows.first['operation'], equals('CREATE'));
    });

    test('Admin user activity & sales reporting calculates accurate totals per user', () {
      // 1. Create user
      final user = userRepo.createUser(
        companyId: companyId,
        username: 'seller_1',
        password: 'password123',
        fullName: 'أحمد البائع',
      );

      // 2. Insert sales invoices by this user
      dbService.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, discount_total,
          grand_total, paid_total, status, payment_status, created_by_user_id
        ) VALUES (
          'inv_1', ?, 'br_1', 'wh_1', 'cust_1',
          'INV-001', '2026-11-09', 10000, 1500, 0,
          11500, 11500, 'POSTED', 'PAID', ?
        )
      ''', [companyId, user.id]);

      dbService.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, discount_total,
          grand_total, paid_total, status, payment_status, created_by_user_id
        ) VALUES (
          'inv_2', ?, 'br_1', 'wh_1', 'cust_1',
          'INV-002', '2026-11-09', 20000, 3000, 0,
          23000, 20000, 'POSTED', 'PARTIAL', ?
        )
      ''', [companyId, user.id]);

      // 3. Query user activity reports
      final reports = userRepo.getUserActivityReports(companyId);
      final userReport = reports.firstWhere((r) => r.userId == user.id);

      expect(userReport.invoiceCount, equals(2));
      expect(userReport.totalSalesHalalas, equals(34500)); // 11500 + 23000
      expect(userReport.totalPaidHalalas, equals(31500));  // 11500 + 20000
      expect(userReport.totalSales, equals(345.00));
      expect(userReport.totalPaid, equals(315.00));
    });

    test('BackupService creates hot backup and companion text manifest with date, time, and company metadata', () async {
      final backupDir = Directory('${tempDir.path}/custom_backup_drive');

      // Create hot backup
      final result = await backupService.createBackup(
        customTargetDir: backupDir.path,
        executedBy: 'المدير العام (admin)',
        companyName: 'شركة الفا للبرمجيات',
      );

      expect(result.isSuccess, isTrue);
      expect(result.existsSync(), isTrue);
      expect(File(result.dbFilePath).existsSync(), isTrue);

      // Verify Arabic companion text file was created
      final manifestFile = File(result.manifestFilePath);
      expect(manifestFile.existsSync(), isTrue);

      final manifestText = manifestFile.readAsStringSync();
      expect(manifestText.contains('منظومة ألفا سوفت لإدارة الموارد المؤسسية'), isTrue);
      expect(manifestText.contains('تاريخ إنشاء النسخة'), isTrue);
      expect(manifestText.contains('ساعة إنشاء النسخة'), isTrue);
      expect(manifestText.contains('شركة الفا للبرمجيات'), isTrue);
      expect(manifestText.contains('المدير العام (admin)'), isTrue);

      // Verify listBackups sees the archive
      final archives = backupService.listBackups(backupDir.path);
      expect(archives.length, greaterThanOrEqualTo(1));
    });

    test('BackupService saves and retrieves persistent backup settings', () {
      backupService.setBackupDirectory(r'E:\MyAlfaBackups');
      backupService.setAutoBackupOnClose(true);

      expect(backupService.isAutoBackupOnCloseEnabled(), isTrue);

      final rows = dbService.select("SELECT value FROM system_settings WHERE key = 'backup_directory'");
      expect(rows.first['value'], equals(r'E:\MyAlfaBackups'));

      backupService.setAutoBackupOnClose(false);
      expect(backupService.isAutoBackupOnCloseEnabled(), isFalse);
    });
  });
}
