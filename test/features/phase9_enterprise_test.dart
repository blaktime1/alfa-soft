import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/enterprise_repository.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';

void main() {
  group('Phase 9: Advanced Enterprise Features (HR, Payroll, GL Posting & Multi-tier Approvals)', () {
    late DatabaseService db;
    late EnterpriseRepository enterpriseRepo;
    late AccountingRepository accountingRepo;

    const companyId = 'comp-ent-1';
    const branchId = 'br-ent-1';
    const userId = 'usr-admin-1';

    setUp(() {
      db = DatabaseService.inMemory();
      enterpriseRepo = EnterpriseRepository(db);
      accountingRepo = AccountingRepository(db);

      // Seed core company, branch, user, and standard Chart of Accounts
      db.execute(
        "INSERT INTO companies (id, legal_name, trade_name, tax_number) VALUES (?, 'Enterprise Corp', 'الفا انتربرايز', '310999999900003')",
        [companyId],
      );
      db.execute(
        "INSERT INTO branches (id, company_id, code, name) VALUES (?, ?, 'BR01', 'الفرع الرئيسي')",
        [branchId, companyId],
      );
      db.execute(
        "INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin) VALUES (?, ?, 'admin', 'hash', 'مدير النظام', 1)",
        [userId, companyId],
      );
      db.execute(
        "INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin) VALUES ('mgr-1', ?, 'manager', 'hash', 'مدير الفرع', 1)",
        [companyId],
      );
      db.execute(
        "INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin) VALUES ('cfo-1', ?, 'cfo', 'hash', 'المدير المالي', 1)",
        [companyId],
      );

      accountingRepo.seedStandardChartOfAccounts(companyId);
    });

    tearDown(() {
      db.dispose();
    });

    test('1. Cost Centers: Creates and retrieves distinct cost centers', () {
      final cc1 = enterpriseRepo.createCostCenter(
        companyId: companyId,
        code: 'CC-101',
        nameAr: 'مشروع مجمع الرياض السكني',
        nameEn: 'Riyadh Complex Project',
      );

      final cc2 = enterpriseRepo.createCostCenter(
        companyId: companyId,
        code: 'CC-102',
        nameAr: 'فرع طريق الملك فهد',
      );

      expect(cc1.code, equals('CC-101'));
      expect(cc2.code, equals('CC-102'));

      final list = enterpriseRepo.getCostCenters(companyId);
      expect(list.length, equals(2));
      expect(list.first.code, equals('CC-101'));
    });

    test('2. HR & Employees: Registers employees with salary breakdown and calculates gross salary', () {
      final emp1 = enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-001',
        fullName: 'أحمد بن خالد التميمي',
        nationalId: '1088776655',
        jobTitle: 'كبير مهندسي البرمجيات',
        department: 'تقنية المعلومات',
        hireDate: DateTime(2025, 1, 15),
        basicSalary: 1200000, // 12,000.00 SAR
        housingAllowance: 300000, // 3,000.00 SAR
        transportAllowance: 100000, // 1,000.00 SAR
      );

      final emp2 = enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-002',
        fullName: 'سارة عبد الرحمن',
        nationalId: '1099887766',
        jobTitle: 'مديرة الموارد البشرية',
        department: 'الموارد البشرية',
        hireDate: DateTime(2025, 3, 1),
        basicSalary: 900000, // 9,000.00 SAR
        housingAllowance: 225000, // 2,250.00 SAR
        transportAllowance: 80000, // 800.00 SAR
      );

      expect(emp1.grossSalary, equals(1600000)); // 16,000.00 SAR
      expect(emp2.grossSalary, equals(1205000)); // 12,050.00 SAR

      final emps = enterpriseRepo.getEmployees(companyId);
      expect(emps.length, equals(2));
      expect(emps[0].employeeCode, equals('EMP-001'));
      expect(emps[1].employeeCode, equals('EMP-002'));
    });

    test('3. Automated Monthly Payroll Run: Generates slips and aggregates totals', () {
      // Create 2 employees
      enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-101',
        fullName: 'فيصل العتيبي',
        nationalId: '1011111111',
        jobTitle: 'مسؤول مبيعات',
        department: 'المبيعات',
        hireDate: DateTime(2025, 2, 1),
        basicSalary: 500000, // 5,000 SAR
        housingAllowance: 125000, // 1,250 SAR
        transportAllowance: 50000, // 500 SAR
      );

      enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-102',
        fullName: 'محمد الشهري',
        nationalId: '1022222222',
        jobTitle: 'أخصائي محاسبة',
        department: 'المالية',
        hireDate: DateTime(2025, 4, 1),
        basicSalary: 700000, // 7,000 SAR
        housingAllowance: 175000, // 1,750 SAR
        transportAllowance: 50000, // 500 SAR
      );

      final run = enterpriseRepo.generatePayrollRun(
        companyId: companyId,
        periodMonth: '2026-11',
      );

      expect(run.status, equals('DRAFT'));
      expect(run.periodMonth, equals('2026-11'));
      expect(run.slips.length, equals(2));

      // emp1: 5000 + 1750 = 6750 SAR (675000 cents)
      // emp2: 7000 + 2250 = 9250 SAR (925000 cents)
      // Total: 16,000 SAR (1,600,000 cents)
      expect(run.totalNet, equals(1600000));
      expect(run.totalGross, equals(1600000));
      expect(run.totalDeductions, equals(0));
    });

    test('4. Payroll General Ledger Integration: Automatically posts balanced double-entry journal', () {
      enterpriseRepo.createEmployee(
        companyId: companyId,
        branchId: branchId,
        employeeCode: 'EMP-201',
        fullName: 'عمر القحطاني',
        nationalId: '1033333333',
        jobTitle: 'مدير فرع',
        department: 'الإدارة',
        hireDate: DateTime(2025, 1, 1),
        basicSalary: 1000000, // 10,000 SAR
        housingAllowance: 250000, // 2,500 SAR
        transportAllowance: 100000, // 1,000 SAR
      );

      final run = enterpriseRepo.generatePayrollRun(
        companyId: companyId,
        periodMonth: '2026-11',
      );

      // Must be approved before posting
      enterpriseRepo.approvePayrollRun(
        payrollRunId: run.id,
        userId: userId,
      );

      // Post to General Ledger
      final journalEntry = enterpriseRepo.postPayrollToGeneralLedger(
        payrollRunId: run.id,
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        accountingRepo: accountingRepo,
      );

      expect(journalEntry.isBalanced, isTrue);
      expect(journalEntry.totalDebit, equals(1350000)); // 13,500 SAR
      expect(journalEntry.totalCredit, equals(1350000));
      expect(journalEntry.sourceType, equals('PAYROLL'));
      expect(journalEntry.lines.length, equals(2));

      // Line 1: Debit 5101 (Salaries Expense)
      final salaryExpenseAcc = accountingRepo.getAccountByCode(companyId, '5101')!;
      final salaryPayableAcc = accountingRepo.getAccountByCode(companyId, '2105')!;

      final debitLine = journalEntry.lines.firstWhere((l) => l.debit > 0);
      expect(debitLine.accountId, equals(salaryExpenseAcc.id));
      expect(debitLine.debit, equals(1350000));

      // Line 2: Credit 2105 (Salaries Payable)
      final creditLine = journalEntry.lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountId, equals(salaryPayableAcc.id));
      expect(creditLine.credit, equals(1350000));

      // Verify Trial Balance remains perfectly in balance
      final trialBalance = accountingRepo.getTrialBalance(companyId);
      final totalDebits = trialBalance.fold(0, (s, r) => s + r.totalDebit);
      final totalCredits = trialBalance.fold(0, (s, r) => s + r.totalCredit);
      expect(totalDebits, equals(totalCredits));
      expect(totalDebits, equals(1350000));
    });

    test('5. Multi-tier Approval Engine: Low-value document requires 1 tier, High-value requires 2 tiers', () {
      // 1. Low value: 5,000 SAR (500,000 cents) -> 1 level
      final lowReq = enterpriseRepo.submitApprovalRequest(
        companyId: companyId,
        documentType: 'STOCK_ADJUSTMENT',
        documentId: 'adj-01',
        requestNumber: 'ADJ-2026-001',
        amount: 500000,
        createdByUserId: userId,
      );

      expect(lowReq.requiredStepLevels, equals(1));
      expect(lowReq.steps.length, equals(1));
      expect(lowReq.steps.first.roleRequired, equals('BRANCH_MANAGER'));

      // 2. High value: 85,000 SAR (8,500,000 cents) -> 2 levels
      final highReq = enterpriseRepo.submitApprovalRequest(
        companyId: companyId,
        documentType: 'PURCHASE_ORDER',
        documentId: 'po-99',
        requestNumber: 'PO-2026-099',
        amount: 8500000,
        createdByUserId: userId,
      );

      expect(highReq.requiredStepLevels, equals(2));
      expect(highReq.steps.length, equals(2));
      expect(highReq.steps[0].roleRequired, equals('BRANCH_MANAGER'));
      expect(highReq.steps[1].roleRequired, equals('FINANCE_DIRECTOR'));
    });

    test('6. Multi-tier Approval Progression: Level 1 approval advances, Level 2 completes', () {
      final highReq = enterpriseRepo.submitApprovalRequest(
        companyId: companyId,
        documentType: 'PURCHASE_ORDER',
        documentId: 'po-100',
        requestNumber: 'PO-2026-100',
        amount: 6000000, // 60,000 SAR (> 10,000 SAR -> 2 levels)
        createdByUserId: userId,
      );

      expect(highReq.status, equals('PENDING'));
      expect(highReq.currentStepLevel, equals(1));

      // Level 1: Branch Manager approves
      final step1Result = enterpriseRepo.processApprovalStep(
        approvalRequestId: highReq.id,
        approverUserId: 'mgr-1',
        isApproved: true,
        comments: 'معتمد من مدير الفرع',
      );

      // Still pending because Level 2 is required
      expect(step1Result.status, equals('PENDING'));
      expect(step1Result.currentStepLevel, equals(2));
      expect(step1Result.steps[0].decision, equals('APPROVED'));
      expect(step1Result.steps[1].decision, equals('PENDING'));

      // Level 2: Finance Director approves
      final step2Result = enterpriseRepo.processApprovalStep(
        approvalRequestId: highReq.id,
        approverUserId: 'cfo-1',
        isApproved: true,
        comments: 'معتمد نهائياً من الإدارة المالية',
      );

      // Now fully APPROVED!
      expect(step2Result.status, equals('APPROVED'));
      expect(step2Result.steps[1].decision, equals('APPROVED'));
    });

    test('7. Multi-tier Approval Rejection: Immediate termination upon rejection', () {
      final highReq = enterpriseRepo.submitApprovalRequest(
        companyId: companyId,
        documentType: 'PURCHASE_ORDER',
        documentId: 'po-101',
        requestNumber: 'PO-2026-101',
        amount: 7500000,
        createdByUserId: userId,
      );

      // Reject at level 1
      final result = enterpriseRepo.processApprovalStep(
        approvalRequestId: highReq.id,
        approverUserId: 'mgr-1',
        isApproved: false,
        comments: 'مرفوض لتجاوز ميزانية الفرع التقديرية',
      );

      expect(result.status, equals('REJECTED'));
      expect(result.steps.first.decision, equals('REJECTED'));
    });
  });
}
