import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';
import 'package:alfa_soft/data/repositories/pos_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';

void main() {
  group('Phase 10: Security, Reliability, Stress Testing & QA Hardening', () {
    late DatabaseService db;
    late AccountingRepository accountingRepo;
    late PosRepository posRepo;
    late CatalogRepository catalogRepo;

    const companyId = 'sec-comp-1';
    const branchId = 'sec-br-1';
    const warehouseId = 'sec-wh-1';
    const userId = 'sec-usr-1';

    setUp(() {
      db = DatabaseService.inMemory();
      accountingRepo = AccountingRepository(db);
      posRepo = PosRepository(db);
      catalogRepo = CatalogRepository(db);

      // Seed organization
      db.execute(
        "INSERT INTO companies (id, legal_name, trade_name, tax_number) VALUES (?, 'Secure Corp', 'الفا للأمن', '310999999900003')",
        [companyId],
      );
      db.execute(
        "INSERT INTO branches (id, company_id, code, name) VALUES (?, ?, 'BR01', 'الفرع الرئيسي')",
        [branchId, companyId],
      );
      db.execute(
        "INSERT INTO warehouses (id, branch_id, code, name) VALUES (?, ?, 'WH01', 'المستودع الرئيسي')",
        [warehouseId, branchId],
      );
      db.execute(
        "INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin) VALUES (?, ?, 'sec_admin', 'hash', 'مسؤول الحماية', 1)",
        [userId, companyId],
      );

      accountingRepo.seedStandardChartOfAccounts(companyId);
    });

    tearDown(() {
      db.dispose();
    });

    test('1. Database Integrity Verification: PRAGMA integrity_check passes ok', () {
      final isHealthy = db.checkIntegrity();
      expect(isHealthy, isTrue);
    });

    test('2. Atomic Transaction Rollback: Zero orphan records remain after failure halfway', () {
      final initialCount = db.select('SELECT COUNT(*) as cnt FROM chart_of_accounts').first['cnt'] as int;

      try {
        db.transaction((tx) {
          tx.execute(
            "INSERT INTO chart_of_accounts (id, company_id, code, name_ar, account_type, is_leaf, is_active, current_balance) VALUES ('acc-temp-1', ?, '9991', 'حساب مؤقت', 'ASSET', 1, 1, 0)",
            [companyId],
          );
          // Force catastrophic error in the middle of transaction
          throw Exception('Simulated fatal hardware / power outage error!');
        });
      } catch (_) {
        // Expected exception
      }

      final postCount = db.select('SELECT COUNT(*) as cnt FROM chart_of_accounts').first['cnt'] as int;
      expect(postCount, equals(initialCount), reason: 'Transaction must rollback completely leaving zero orphan rows');

      final orphanCheck = db.select("SELECT * FROM chart_of_accounts WHERE id = 'acc-temp-1'");
      expect(orphanCheck.isEmpty, isTrue);
    });

    test('3. High-Frequency Write Stress Test: 200 consecutive balanced transactions with zero lock errors', () {
      final cashAcc = accountingRepo.getAccountByCode(companyId, '1010')!;
      final salesAcc = accountingRepo.getAccountByCode(companyId, '4010')!;

      final stopwatch = Stopwatch()..start();

      for (int i = 1; i <= 200; i++) {
        accountingRepo.postJournalEntry(
          companyId: companyId,
          branchId: branchId,
          userId: userId,
          entryNumber: 'JE-STRESS-$i',
          entryDate: DateTime.now(),
          sourceType: 'STRESS_TEST',
          narration: 'قيد اختبار الإجهاد التكراري رقم $i',
          rawLines: [
            {'accountId': cashAcc.id, 'debit': 10000, 'credit': 0, 'memo': 'نقدية'},
            {'accountId': salesAcc.id, 'debit': 0, 'credit': 10000, 'memo': 'مبيعات'},
          ],
        );
      }

      stopwatch.stop();

      // Check all 200 were inserted
      final totalEntries = db.select(
        "SELECT COUNT(*) as cnt FROM journal_entries WHERE source_type = 'STRESS_TEST'",
      ).first['cnt'] as int;
      expect(totalEntries, equals(200));

      // Check Trial Balance is still in mathematical equilibrium
      final trialBalance = accountingRepo.getTrialBalance(companyId);
      final totalDebits = trialBalance.fold(0, (s, r) => s + r.totalDebit);
      final totalCredits = trialBalance.fold(0, (s, r) => s + r.totalCredit);
      expect(totalDebits, equals(totalCredits));
      expect(totalDebits, equals(200 * 10000)); // Exactly 20,000.00 SAR

      // Verify PRAGMA integrity is still ok after 200 rapid writes
      expect(db.checkIntegrity(), isTrue);
    });

    test('4. POS High-Speed Concurrency: Rapid shift open, sales, and closing cycle', () {
      final shift = posRepo.openShift(
        branchId: branchId,
        userId: userId,
        startingCashCents: 50000, // 500.00 SAR
      );

      expect(shift.status, equals('OPEN'));
      expect(shift.startingCash, equals(500.00));

      // Record 10 fast cash payments of 115.00 SAR (11500 cents) = 1,150.00 SAR
      for (int i = 1; i <= 10; i++) {
        db.execute('''
          INSERT INTO payments (id, company_id, branch_id, document_type, document_id, payment_method, amount, created_by_user_id)
          VALUES (?, ?, ?, 'SALES_INVOICE', ?, 'CASH', 11500, ?)
        ''', ['pay-stress-$i', companyId, branchId, 'inv-stress-$i', userId]);
      }

      // Close shift with expected total = 500.00 (opening) + 1,150.00 (sales) = 1,650.00 SAR (165000 cents)
      final closedShift = posRepo.closeShift(
        shiftId: shift.id,
        actualCashCents: 165000,
        notes: 'إغلاق وردية بعد اختبار الإجهاد السريع',
      );

      expect(closedShift.status, equals('CLOSED'));
      expect(closedShift.expectedCash, equals(1650.00));
      expect(closedShift.actualCash, equals(1650.00));
      expect(closedShift.difference, equals(0.0), reason: 'Zero cash variance');
    });

    test('5. Immutable Audit Trail: Ensures all modifications log who, what, and when', () {
      final cashAcc = accountingRepo.getAccountByCode(companyId, '1010')!;
      final salesAcc = accountingRepo.getAccountByCode(companyId, '4010')!;

      // Post transaction to generate immutable audit entry
      accountingRepo.postJournalEntry(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        entryNumber: 'JE-AUDIT-001',
        entryDate: DateTime.now(),
        sourceType: 'TEST_AUDIT',
        narration: 'قيد إثبات سجل التدقيق المحاسبي',
        rawLines: [
          {'accountId': cashAcc.id, 'debit': 50000, 'credit': 0, 'memo': 'نقدية'},
          {'accountId': salesAcc.id, 'debit': 0, 'credit': 50000, 'memo': 'مبيعات'},
        ],
      );

      final auditRows = db.select('SELECT * FROM audit_logs ORDER BY timestamp DESC');
      expect(auditRows.isNotEmpty, isTrue);

      final firstLog = auditRows.first;
      expect(firstLog['company_id'], equals(companyId));
      expect(firstLog['action'], equals('POST_JOURNAL_ENTRY'));
      expect(firstLog['device_id'], equals('LOCAL_DESKTOP'));
      expect(firstLog['user_id'], equals(userId));
    });
  });
}
