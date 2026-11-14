import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/printing/printer_service.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';
import 'package:alfa_soft/data/repositories/enterprise_repository.dart';
import 'package:alfa_soft/domain/entities/accounting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late PrinterService printerService;
  late AccountingRepository accountingRepo;
  late EnterpriseRepository enterpriseRepo;

  const companyId = 'comp-test-001';
  const branchId = 'branch-test-001';
  const userId = 'user-test-001';

  setUp(() {
    db = DatabaseService.inMemory();
    printerService = PrinterService(db);
    accountingRepo = AccountingRepository(db);
    enterpriseRepo = EnterpriseRepository(db);

    // Seed test company and branch
    db.execute('''
      INSERT INTO companies (id, legal_name, trade_name, currency_code)
      VALUES (?, 'شركة ألفا الاختبارية', 'ألفا سوفت', 'SAR')
    ''', [companyId]);

    db.execute('''
      INSERT INTO branches (id, company_id, name, code)
      VALUES (?, ?, 'الفرع الرئيسي', 'BR-01')
    ''', [branchId, companyId]);

    db.execute('''
      INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin)
      VALUES (?, ?, 'admin', 'dummy_hash', 'المدير العام', 1)
    ''', [userId, companyId]);

    accountingRepo.seedStandardChartOfAccounts(companyId);
  });

  tearDown(() {
    db.dispose();
  });

  group('1. فرض العملة وإدارتها من إعدادات النظام وتحديث سجل المنشأة', () {
    test('تغيير العملة الافتراضية يحدث system_settings وسجل المنشأة companies', () {
      expect(printerService.getDefaultCurrency(), equals('SAR'));

      // Switch to YER (ريال يمني)
      printerService.setDefaultCurrency('YER');
      expect(printerService.getDefaultCurrency(), equals('YER'));
      expect(PrinterService.defaultCurrency, equals('YER'));

      final compRows = db.select('SELECT currency_code FROM companies WHERE id = ?', [companyId]);
      expect(compRows.first['currency_code'], equals('YER'));

      // Switch to USD (دولار)
      printerService.setDefaultCurrency('USD');
      expect(printerService.getDefaultCurrency(), equals('USD'));
      expect(PrinterService.defaultCurrency, equals('USD'));

      final compRowsUSD = db.select('SELECT currency_code FROM companies WHERE id = ?', [companyId]);
      expect(compRowsUSD.first['currency_code'], equals('USD'));
    });
  });

  group('2. سندات صرف المصروفات والأصول مع القيد المزدوج الآلي', () {
    test('تسجيل سند صرف إيجار يولد قيداً متوازناً ويخصم من الخزينة', () {
      final voucher = accountingRepo.postExpenseVoucher(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        category: 'RENT',
        amountCents: 500000, // 5,000.00
        paymentMethod: 'CASH',
        description: 'سداد إيجار المحل لشهر نوفمبر',
        referenceNo: 'RENT-NOV-2026',
      );

      expect(voucher.voucherNumber, startsWith('VOUCH-'));
      expect(voucher.category, equals('RENT'));
      expect(voucher.amountCents, equals(500000));
      expect(voucher.journalEntryId, isNotNull);

      final vouchers = accountingRepo.getExpenseVouchers(companyId);
      expect(vouchers.length, equals(1));
      expect(vouchers.first.description, equals('سداد إيجار المحل لشهر نوفمبر'));
      expect(vouchers.first.expenseAccountName, contains('الإيجار'));

      // Check Journal Entry
      final jeList = accountingRepo.getJournalEntries(companyId, sourceType: 'EXPENSE_VOUCHER');
      expect(jeList.length, equals(1));
      final je = jeList.first;
      expect(je.totalDebit, equals(500000));
      expect(je.totalCredit, equals(500000));
      expect(je.lines.length, equals(2));

      // Debit line: 5030 (Rent)
      final debitLine = je.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountCode, equals('5030'));
      expect(debitLine.debit, equals(500000));

      // Credit line: 1010 (Cash)
      final creditLine = je.lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountCode, equals('1010'));
      expect(creditLine.credit, equals(500000));
    });

    test('تسجيل شراء أصول ومعدات (كاميرات مراقبة ورفوف) يولد قيد أصول ثابتة 1500', () {
      final voucher = accountingRepo.postExpenseVoucher(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        category: 'FIXED_ASSET',
        amountCents: 350000, // 3,500.00
        paymentMethod: 'BANK',
        description: 'شراء 4 كاميرات مراقبة جديدة ورفوف حديد للمستودع',
        referenceNo: 'INV-ASSET-881',
      );

      expect(voucher.category, equals('FIXED_ASSET'));
      expect(voucher.amountCents, equals(350000));
      expect(voucher.paymentMethod, equals('BANK'));

      final jeList = accountingRepo.getJournalEntries(companyId, sourceType: 'EXPENSE_VOUCHER');
      final je = jeList.firstWhere((e) => e.sourceId == voucher.id);
      expect(je.totalDebit, equals(350000));
      expect(je.totalCredit, equals(350000));

      // Debit Asset: 1500
      final debitLine = je.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountCode, equals('1500'));

      // Credit Bank: 1020
      final creditLine = je.lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountCode, equals('1020'));
    });

    test('تسجيل فواتير كهرباء ومياه وصيانة أعطال وتشغيل', () {
      // 1. Utilities (كهرباء ومياه وإنترنت)
      final utilVouch = accountingRepo.postExpenseVoucher(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        category: 'UTILITIES',
        amountCents: 45000,
        paymentMethod: 'CASH',
        description: 'فاتورة الكهرباء والإنترنت',
      );
      expect(utilVouch.category, equals('UTILITIES'));

      // 2. Maintenance (صيانة أعطال)
      final maintVouch = accountingRepo.postExpenseVoucher(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        category: 'MAINTENANCE',
        amountCents: 20000,
        paymentMethod: 'CASH',
        description: 'إصلاح عطل مكيف صالة العرض',
      );
      expect(maintVouch.category, equals('MAINTENANCE'));

      final vouchers = accountingRepo.getExpenseVouchers(companyId);
      expect(vouchers.length, equals(2));
    });
  });

  group('3. سلف الموظفين (سحب جزء من الراتب) وتوليد مسير الرواتب والاستقطاع الآلي', () {
    late String empId;

    setUp(() {
      final emp = enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-001',
        fullName: 'أحمد المحاسب',
        nationalId: '1029384756',
        jobTitle: 'محاسب عام',
        department: 'الإدارة المالية',
        hireDate: DateTime(2025, 1, 1),
        basicSalary: 600000, // 6,000.00
        housingAllowance: 100000, // 1,000.00
        transportAllowance: 50000, // 500.00 => Gross: 7,500.00
      );
      empId = emp.id;
    });

    test('صرف سلفة موظف ينشئ قيد سلف مدين 1150 وخزينة دائن 1010', () {
      final advance = enterpriseRepo.recordSalaryAdvance(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        employeeId: empId,
        amountCents: 150000, // 1,500.00
        paymentMethod: 'CASH',
        repaymentMonth: '2026-11',
        notes: 'سلفة دفعة زواج طارئة',
        accountingRepo: accountingRepo,
      );

      expect(advance.advanceNumber, startsWith('ADV-'));
      expect(advance.amountCents, equals(150000));
      expect(advance.status, equals('PENDING'));
      expect(advance.employeeName, equals('أحمد المحاسب'));

      final advances = enterpriseRepo.getSalaryAdvances(companyId);
      expect(advances.length, equals(1));
      expect(advances.first.status, equals('PENDING'));

      // Check Journal Entry
      final jeList = accountingRepo.getJournalEntries(companyId, sourceType: 'SALARY_ADVANCE');
      expect(jeList.length, equals(1));
      final je = jeList.first;
      expect(je.totalDebit, equals(150000));
      expect(je.totalCredit, equals(150000));

      final debitLine = je.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountCode, equals('1150')); // سلف الموظفين
    });

    test('توليد مسير الرواتب يستقطع سلفة الموظف آلياً ويتيح إعادة الاحتساب في المسودة دون خطأ', () {
      // 1. Record advance
      enterpriseRepo.recordSalaryAdvance(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        employeeId: empId,
        amountCents: 200000, // 2,000.00
        paymentMethod: 'CASH',
        repaymentMonth: '2026-11',
        accountingRepo: accountingRepo,
      );

      // 2. Generate Payroll Run for 2026-11
      final run1 = enterpriseRepo.generatePayrollRun(
        companyId: companyId,
        periodMonth: '2026-11',
      );

      expect(run1.periodMonth, equals('2026-11'));
      expect(run1.totalGross, equals(750000)); // 6000 + 1000 + 500 = 7500.00
      expect(run1.totalDeductions, equals(200000)); // 2000.00 auto-deducted advance!
      expect(run1.totalNet, equals(550000)); // 7500 - 2000 = 5500.00 Net!
      expect(run1.status, equals('DRAFT'));

      // 3. User clicks Generate Payroll again for the same month (Recalculate Draft)
      // Must NOT fail with SQLite UNIQUE constraint!
      final run2 = enterpriseRepo.generatePayrollRun(
        companyId: companyId,
        periodMonth: '2026-11',
      );

      expect(run2.id, equals(run1.id));
      expect(run2.totalGross, equals(750000));
      expect(run2.totalDeductions, equals(200000));
      expect(run2.totalNet, equals(550000));

      // 4. Approve and Post to General Ledger
      enterpriseRepo.approvePayrollRun(payrollRunId: run2.id, userId: userId);

      final je = enterpriseRepo.postPayrollToGeneralLedger(
        payrollRunId: run2.id,
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        accountingRepo: accountingRepo,
      );

      // Verify balanced double entry:
      // Dr. 5101 Salaries Expense = 7,500.00
      // Cr. 1150 Advances Deducted = 2,000.00
      // Cr. 2105 Salaries Payable = 5,500.00
      expect(je.totalDebit, equals(750000));
      expect(je.totalCredit, equals(750000));
      expect(je.lines.length, equals(3));

      final grossLine = je.lines.firstWhere((l) => l.accountCode == '5101');
      expect(grossLine.debit, equals(750000));

      final advanceLine = je.lines.firstWhere((l) => l.accountCode == '1150');
      expect(advanceLine.credit, equals(200000));

      final payableLine = je.lines.firstWhere((l) => l.accountCode == '2105');
      expect(payableLine.credit, equals(550000));

      // Verify advance status changed to DEDUCTED
      final advances = enterpriseRepo.getSalaryAdvances(companyId);
      expect(advances.first.status, equals('DEDUCTED'));

      // 5. Trying to regenerate an already approved/posted payroll run throws clear friendly Arabic StateError
      expect(
        () => enterpriseRepo.generatePayrollRun(
          companyId: companyId,
          periodMonth: '2026-11',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('تم اعتماد وترحيل مسير رواتب شهر 2026-11 مسبقاً'),
        )),
      );
    });
  });
}
