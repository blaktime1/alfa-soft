import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';
import 'package:alfa_soft/domain/entities/accounting.dart';

void main() {
  late DatabaseService dbService;
  late AccountingRepository accountingRepo;

  const testCompanyId = 'comp_acc_test';
  const testBranchId = 'br_acc_test';
  const testUserId = 'user_acc_test';

  setUp(() {
    dbService = DatabaseService.inMemory();
    accountingRepo = AccountingRepository(dbService);

    // Seed master organization structure
    dbService.execute('''
      INSERT INTO companies (id, legal_name, trade_name, currency_code)
      VALUES (?, 'شركة ألفا للمحاسبة', 'ألفا سوفت المالية', 'SAR')
    ''', [testCompanyId]);

    dbService.execute('''
      INSERT INTO branches (id, company_id, code, name)
      VALUES (?, ?, 'BR-ACC-01', 'الفرع المالي التجريبي')
    ''', [testBranchId, testCompanyId]);

    dbService.execute('''
      INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin)
      VALUES (?, ?, 'accountant', 'hash', 'كبير المحاسبين', 1)
    ''', [testUserId, testCompanyId]);
  });

  tearDown(() {
    dbService.dispose();
  });

  group('Phase 4 — Double-Entry Accounting Engine Integration Tests', () {
    test('1. Chart of Accounts: seeds standard accounts and allows custom account creation', () {
      accountingRepo.seedStandardChartOfAccounts(testCompanyId);
      final accounts = accountingRepo.getAccounts(testCompanyId);

      expect(accounts.length, greaterThanOrEqualTo(12));
      expect(accounts.any((a) => a.code == '1010'), isTrue); // Cash
      expect(accounts.any((a) => a.code == '1200'), isTrue); // Inventory
      expect(accounts.any((a) => a.code == '2010'), isTrue); // AP
      expect(accounts.any((a) => a.code == '4010'), isTrue); // Sales Revenue
      expect(accounts.any((a) => a.code == '5010'), isTrue); // COGS

      // Create custom expense account
      final customAcc = accountingRepo.createAccount(
        companyId: testCompanyId,
        code: '5040',
        nameAr: 'مصروفات التسويق والإعلانات',
        nameEn: 'Marketing & Advertising',
        accountType: AccountType.expense,
      );

      expect(customAcc.code, equals('5040'));
      expect(customAcc.accountType, equals(AccountType.expense));

      final updatedAccounts = accountingRepo.getAccounts(testCompanyId);
      expect(updatedAccounts.any((a) => a.code == '5040'), isTrue);
    });

    test('2. Double-Entry Balance Constraint: rejects unbalanced entries and accepts balanced vouchers', () {
      accountingRepo.seedStandardChartOfAccounts(testCompanyId);

      final cashAcc = accountingRepo.getAccountByCode(testCompanyId, '1010')!;
      final capitalAcc = accountingRepo.getAccountByCode(testCompanyId, '3010')!;

      // Attempt unbalanced entry (Debit: 100,000, Credit: 80,000)
      expect(
        () => accountingRepo.postJournalEntry(
          companyId: testCompanyId,
          branchId: testBranchId,
          userId: testUserId,
          entryNumber: 'JE-TEST-UNBALANCED',
          entryDate: DateTime.now(),
          sourceType: 'MANUAL',
          narration: 'قيد غير متوازن فاشل',
          rawLines: [
            {'accountId': cashAcc.id, 'debit': 10000000, 'credit': 0, 'memo': 'إيداع نقدي'},
            {'accountId': capitalAcc.id, 'debit': 0, 'credit': 8000000, 'memo': 'رأس مال جزئي'},
          ],
        ),
        throwsArgumentError,
      );

      // Post strictly balanced entry: Initial Owner Capital (Debit Cash 100,000 SAR, Credit Capital 100,000 SAR)
      final balancedEntry = accountingRepo.postJournalEntry(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        entryNumber: 'JE-CAPITAL-001',
        entryDate: DateTime.now(),
        sourceType: 'MANUAL_VOUCHER',
        narration: 'إيداع رأس مال الشركاء النقدي',
        rawLines: [
          {'accountId': cashAcc.id, 'debit': 10000000, 'credit': 0, 'memo': 'إيداع بالخزينة'},
          {'accountId': capitalAcc.id, 'debit': 0, 'credit': 10000000, 'memo': 'رأس المال المستثمر'},
        ],
      );

      expect(balancedEntry.totalDebit, equals(10000000));
      expect(balancedEntry.totalCredit, equals(10000000));
      expect(balancedEntry.lines.length, equals(2));

      // Assert updated account balances
      final updatedCash = accountingRepo.getAccountByCode(testCompanyId, '1010')!;
      final updatedCapital = accountingRepo.getAccountByCode(testCompanyId, '3010')!;

      expect(updatedCash.currentBalance, equals(10000000)); // +100,000 SAR
      expect(updatedCapital.currentBalance, equals(10000000)); // +100,000 SAR
    });

    test('3. Automated Sales Invoice Posting: posts balanced debits/credits across Revenue, VAT, COGS and Inventory', () {
      accountingRepo.seedStandardChartOfAccounts(testCompanyId);

      // Sale of 1,000.00 SAR subtotal + 150.00 SAR (15% VAT) = 1,150.00 SAR Grand Total
      // COGS is 600.00 SAR
      final saleEntry = accountingRepo.postSalesInvoiceJournal(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        invoiceId: 'inv_test_01',
        invoiceNumber: 'INV-2026-0001',
        invoiceDate: DateTime.now(),
        subtotalCents: 100000,
        taxCents: 15000,
        grandTotalCents: 115000,
        totalCostCents: 60000,
        isCash: true,
      );

      // Total Debit = Grand Total (1,150) + COGS (600) = 1,750.00 SAR
      // Total Credit = Subtotal (1,000) + Tax (150) + Inventory (600) = 1,750.00 SAR
      expect(saleEntry.totalDebit, equals(175000));
      expect(saleEntry.totalCredit, equals(175000));
      expect(saleEntry.totalDebit, equals(saleEntry.totalCredit));

      // Verify individual account balances
      final cashAcc = accountingRepo.getAccountByCode(testCompanyId, '1010')!;
      final salesAcc = accountingRepo.getAccountByCode(testCompanyId, '4010')!;
      final vatAcc = accountingRepo.getAccountByCode(testCompanyId, '2020')!;
      final cogsAcc = accountingRepo.getAccountByCode(testCompanyId, '5010')!;
      final invAcc = accountingRepo.getAccountByCode(testCompanyId, '1200')!;

      expect(cashAcc.currentBalance, equals(115000));
      expect(salesAcc.currentBalance, equals(100000));
      expect(vatAcc.currentBalance, equals(15000));
      expect(cogsAcc.currentBalance, equals(60000));
      expect(invAcc.currentBalance, equals(-60000)); // Inventory reduced by 600 SAR
    });

    test('4. Automated Purchase GRN Posting: debits Inventory and credits Accounts Payable', () {
      accountingRepo.seedStandardChartOfAccounts(testCompanyId);

      final grnEntry = accountingRepo.postPurchaseGrnJournal(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        grnId: 'grn_test_01',
        grnNumber: 'GRN-2026-0001',
        grnDate: DateTime.now(),
        totalCostCents: 500000, // 5,000.00 SAR
        supplierName: 'شركة الألبان الوطنية',
      );

      expect(grnEntry.totalDebit, equals(500000));
      expect(grnEntry.totalCredit, equals(500000));

      final invAcc = accountingRepo.getAccountByCode(testCompanyId, '1200')!;
      final apAcc = accountingRepo.getAccountByCode(testCompanyId, '2010')!;

      expect(invAcc.currentBalance, equals(500000)); // +5,000 SAR in inventory
      expect(apAcc.currentBalance, equals(500000)); // +5,000 SAR owed to supplier
    });

    test('5. Trial Balance, Income Statement and Balance Sheet: strictly verify fundamental accounting equation', () {
      accountingRepo.seedStandardChartOfAccounts(testCompanyId);

      final cashAcc = accountingRepo.getAccountByCode(testCompanyId, '1010')!;
      final capitalAcc = accountingRepo.getAccountByCode(testCompanyId, '3010')!;

      // 1. Initial Capital: 200,000 SAR
      accountingRepo.postJournalEntry(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        entryNumber: 'JE-CAPITAL',
        entryDate: DateTime.now(),
        sourceType: 'MANUAL_VOUCHER',
        narration: 'إيداع رأس مال ابتدائي',
        rawLines: [
          {'accountId': cashAcc.id, 'debit': 20000000, 'credit': 0, 'memo': 'نقدية'},
          {'accountId': capitalAcc.id, 'debit': 0, 'credit': 20000000, 'memo': 'رأس مال'},
        ],
      );

      // 2. Purchase Inventory: 50,000 SAR on credit (AP)
      accountingRepo.postPurchaseGrnJournal(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        grnId: 'grn_01',
        grnNumber: 'GRN-01',
        grnDate: DateTime.now(),
        totalCostCents: 5000000,
        supplierName: 'المورد الرئيسي',
      );

      // 3. Make Sales: 30,000 SAR subtotal + 4,500 VAT = 34,500 SAR Cash, Cost = 18,000 SAR
      accountingRepo.postSalesInvoiceJournal(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        invoiceId: 'inv_01',
        invoiceNumber: 'INV-01',
        invoiceDate: DateTime.now(),
        subtotalCents: 3000000,
        taxCents: 450000,
        grandTotalCents: 3450000,
        totalCostCents: 1800000,
        isCash: true,
      );

      // 4. Pay General Expenses (Electricity & Rent): 2,000 SAR from Cash
      final expenseAcc = accountingRepo.getAccountByCode(testCompanyId, '5020')!;
      accountingRepo.postJournalEntry(
        companyId: testCompanyId,
        branchId: testBranchId,
        userId: testUserId,
        entryNumber: 'JE-EXP-01',
        entryDate: DateTime.now(),
        sourceType: 'MANUAL_VOUCHER',
        narration: 'سداد مصروف كهرباء نقداً',
        rawLines: [
          {'accountId': expenseAcc.id, 'debit': 200000, 'credit': 0, 'memo': 'فاتورة كهرباء'},
          {'accountId': cashAcc.id, 'debit': 0, 'credit': 200000, 'memo': 'خروج نقدية من الخزينة'},
        ],
      );

      // --- VERIFY TRIAL BALANCE ---
      final trialBalance = accountingRepo.getTrialBalance(testCompanyId);
      final totalDebits = trialBalance.fold(0, (s, r) => s + r.totalDebit);
      final totalCredits = trialBalance.fold(0, (s, r) => s + r.totalCredit);

      expect(totalDebits, greaterThan(0));
      expect(totalCredits, greaterThan(0));
      expect(totalDebits, equals(totalCredits)); // Strict Trial Balance mathematical equilibrium

      // --- VERIFY INCOME STATEMENT (P&L) ---
      // Revenue = 30,000 SAR (3,000,000 cents)
      // COGS = 18,000 SAR (1,800,000 cents)
      // Gross Profit = 30,000 - 18,000 = 12,000 SAR (1,200,000 cents)
      // Operating Expenses = 2,000 SAR (200,000 cents)
      // Net Profit = 12,000 - 2,000 = 10,000 SAR (1,000,000 cents)
      final income = accountingRepo.getIncomeStatement(testCompanyId);

      expect(income.revenueCents, equals(3000000));
      expect(income.cogsCents, equals(1800000));
      expect(income.grossProfitCents, equals(1200000));
      expect(income.expensesCents, equals(200000));
      expect(income.netProfitCents, equals(1000000));

      // --- VERIFY BALANCE SHEET ---
      // Assets = Cash (200,000 + 34,500 - 2,000 = 232,500) + Inventory (50,000 - 18,000 = 32,000) = 264,500 SAR
      // Liabilities = AP (50,000) + VAT Output (4,500) = 54,500 SAR
      // Equity = Capital (200,000) = 200,000 SAR
      // Current Earnings (Net Profit) = 10,000 SAR
      // Total Liabilities + Equity + Net Profit = 54,500 + 200,000 + 10,000 = 264,500 SAR!
      final balanceSheet = accountingRepo.getBalanceSheet(testCompanyId);

      expect(balanceSheet.totalAssetsCents, equals(26450000));
      expect(balanceSheet.totalLiabilitiesCents, equals(5450000));
      expect(balanceSheet.totalEquityCents, equals(20000000));
      expect(balanceSheet.currentEarningsCents, equals(1000000));
      expect(balanceSheet.isBalanced, isTrue); // Fundamental Accounting Equation PROVEN!

      // --- VERIFY GENERAL LEDGER ---
      final cashLedger = accountingRepo.getGeneralLedger(cashAcc.id);
      expect(cashLedger.length, equals(3)); // Initial capital, cash sale, expense payment
      expect(cashLedger.last.runningBalance, equals(23250000)); // Exactly 232,500.00 SAR
    });
  });
}
