import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/accounting.dart';

class AccountingRepository {
  final DatabaseService _db;
  const AccountingRepository(this._db);

  /// Automatically seeds standard Chart of Accounts if empty for this company
  void seedStandardChartOfAccounts(String companyId) {
    final existing = _db.select(
      'SELECT COUNT(*) as cnt FROM chart_of_accounts WHERE company_id = ?',
      [companyId],
    );
    if ((existing.first['cnt'] as int) > 0) return;

    const uuid = Uuid();
    final defaultAccounts = [
      // 1. Assets
      {'code': '1010', 'name_ar': 'الخزينة النقدية الرئيسية', 'name_en': 'Cash on Hand', 'type': 'ASSET', 'is_leaf': 1},
      {'code': '1020', 'name_ar': 'الحساب البنكي / نقاط البيع', 'name_en': 'Bank Accounts / POS', 'type': 'ASSET', 'is_leaf': 1},
      {'code': '1100', 'name_ar': 'العملاء والمدينون', 'name_en': 'Accounts Receivable', 'type': 'ASSET', 'is_leaf': 1},
      {'code': '1150', 'name_ar': 'سلف وعهد الموظفين', 'name_en': 'Employee Advances', 'type': 'ASSET', 'is_leaf': 1},
      {'code': '1200', 'name_ar': 'مخزون البضائع', 'name_en': 'Merchandise Inventory', 'type': 'ASSET', 'is_leaf': 1},
      {'code': '1500', 'name_ar': 'الأصول والمعدات الثابتة (أجهزة وكاميرات ورفوف)', 'name_en': 'Fixed Assets & Equipment', 'type': 'ASSET', 'is_leaf': 1},

      // 2. Liabilities
      {'code': '2010', 'name_ar': 'الموردون والدائنون', 'name_en': 'Accounts Payable', 'type': 'LIABILITY', 'is_leaf': 1},
      {'code': '2020', 'name_ar': 'ضريبة القيمة المضافة المستحقة (15%)', 'name_en': 'VAT Output Payable', 'type': 'LIABILITY', 'is_leaf': 1},

      // 3. Equity
      {'code': '3010', 'name_ar': 'رأس المال المستثمر', 'name_en': 'Owner Capital', 'type': 'EQUITY', 'is_leaf': 1},
      {'code': '3020', 'name_ar': 'الأرباح المحتجزة / المدورة', 'name_en': 'Retained Earnings', 'type': 'EQUITY', 'is_leaf': 1},

      // 4. Revenue
      {'code': '4010', 'name_ar': 'إيرادات المبيعات', 'name_en': 'Sales Revenue', 'type': 'REVENUE', 'is_leaf': 1},
      {'code': '4020', 'name_ar': 'خصومات ومسموحات المبيعات', 'name_en': 'Sales Discounts', 'type': 'REVENUE', 'is_leaf': 1},

      // 5. Expenses
      {'code': '5010', 'name_ar': 'تكلفة البضاعة المباعة (COGS)', 'name_en': 'Cost of Goods Sold', 'type': 'EXPENSE', 'is_leaf': 1},
      {'code': '5020', 'name_ar': 'مصروفات إدارية وعمومية وضيافة', 'name_en': 'General & Admin Expenses', 'type': 'EXPENSE', 'is_leaf': 1},
      {'code': '5021', 'name_ar': 'مصروفات صيانة وإصلاحات وأعطال', 'name_en': 'Maintenance & Repairs', 'type': 'EXPENSE', 'is_leaf': 1},
      {'code': '5030', 'name_ar': 'مصروف الإيجار', 'name_en': 'Rent Expense', 'type': 'EXPENSE', 'is_leaf': 1},
      {'code': '5031', 'name_ar': 'مصروفات كهرباء ومياه وهاتف وإنترنت', 'name_en': 'Utilities & Services', 'type': 'EXPENSE', 'is_leaf': 1},
    ];

    _db.transaction((tx) {
      for (final a in defaultAccounts) {
        tx.execute('''
          INSERT INTO chart_of_accounts (
            id, company_id, code, name_ar, name_en, account_type, is_leaf, is_active, current_balance
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0)
        ''', [
          'acc_${a['code']}_${uuid.v4().substring(0, 8)}',
          companyId,
          a['code'],
          a['name_ar'],
          a['name_en'],
          a['type'],
          a['is_leaf'],
        ]);
      }
    });
  }

  List<Account> getAccounts(String companyId) {
    final result = _db.select('''
      SELECT * FROM chart_of_accounts 
      WHERE company_id = ? 
      ORDER BY code ASC
    ''', [companyId]);

    return result.map((r) => Account.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  Account? getAccountByCode(String companyId, String code) {
    final result = _db.select('''
      SELECT * FROM chart_of_accounts 
      WHERE company_id = ? AND code = ? 
      LIMIT 1
    ''', [companyId, code]);

    if (result.isEmpty) return null;
    return Account.fromMap(Map<String, dynamic>.from(result.first));
  }

  Account? getAccountById(String companyId, String id) {
    final result = _db.select('''
      SELECT * FROM chart_of_accounts 
      WHERE company_id = ? AND id = ? 
      LIMIT 1
    ''', [companyId, id]);

    if (result.isEmpty) return null;
    return Account.fromMap(Map<String, dynamic>.from(result.first));
  }

  Account createAccount({
    required String companyId,
    required String code,
    required String nameAr,
    String? nameEn,
    required AccountType accountType,
    String? parentId,
  }) {
    final existing = _db.select(
      'SELECT id FROM chart_of_accounts WHERE company_id = ? AND code = ?',
      [companyId, code.trim()],
    );
    if (existing.isNotEmpty) {
      throw ArgumentError('رقم الحساب $code موجود مسبقاً');
    }

    const uuid = Uuid();
    final accountId = 'acc_${uuid.v4()}';

    _db.execute('''
      INSERT INTO chart_of_accounts (
        id, company_id, code, name_ar, name_en, account_type, parent_id, is_leaf, is_active, current_balance
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, 0)
    ''', [
      accountId,
      companyId,
      code.trim(),
      nameAr.trim(),
      nameEn?.trim(),
      accountType.code,
      parentId,
    ]);

    return Account(
      id: accountId,
      companyId: companyId,
      code: code.trim(),
      nameAr: nameAr.trim(),
      nameEn: nameEn?.trim(),
      accountType: accountType,
      parentId: parentId,
      createdAt: DateTime.now(),
    );
  }

  /// Updates an existing account's details
  void updateAccount({
    required String accountId,
    required String code,
    required String nameAr,
    String? nameEn,
    required AccountType accountType,
    required bool isActive,
  }) {
    _db.execute('''
      UPDATE chart_of_accounts
      SET code = ?, name_ar = ?, name_en = ?, account_type = ?, is_active = ?
      WHERE id = ?
    ''', [
      code.trim(),
      nameAr.trim(),
      nameEn?.trim(),
      accountType.code,
      isActive ? 1 : 0,
      accountId,
    ]);
  }

  /// Reverses an existing journal entry (swapping Debits and Credits and reverting balances)
  void reverseJournalEntry({
    required String entryId,
    required String userId,
    required String reason,
  }) {
    final entryRows = _db.select('SELECT * FROM journal_entries WHERE id = ?', [entryId]);
    if (entryRows.isEmpty) throw ArgumentError('القيد غير موجود');
    final entry = entryRows.first;
    if (entry['status'] == 'REVERSED') throw StateError('القيد معكوس مسبقاً');

    final linesResult = _db.select('SELECT * FROM journal_lines WHERE journal_entry_id = ?', [entryId]);

    final rawReversingLines = <Map<String, dynamic>>[];
    for (final l in linesResult) {
      final debit = l['debit'] as int;
      final credit = l['credit'] as int;
      rawReversingLines.add({
        'accountId': l['account_id'],
        'debit': credit, // Reverse: Debit becomes Credit, Credit becomes Debit
        'credit': debit,
        'memo': 'عكس القيد ${entry['entry_number']}: $reason',
      });
    }

    postJournalEntry(
      companyId: entry['company_id'] as String,
      branchId: entry['branch_id'] as String,
      userId: userId,
      entryNumber: 'REV-${entry['entry_number']}',
      entryDate: DateTime.now(),
      sourceType: 'REVERSAL',
      sourceId: entryId,
      narration: 'قيد عكسي للقيد ${entry['entry_number']}: $reason',
      rawLines: rawReversingLines,
    );

    _db.execute("UPDATE journal_entries SET status = 'REVERSED' WHERE id = ?", [entryId]);
  }

  /// Strictly posts a balanced double-entry journal voucher
  JournalEntry postJournalEntry({
    required String companyId,
    required String branchId,
    required String userId,
    required String entryNumber,
    required DateTime entryDate,
    required String sourceType,
    String? sourceId,
    required String narration,
    required List<Map<String, dynamic>> rawLines, // [{accountId, debit, credit, memo}]
  }) {
    if (rawLines.isEmpty) {
      throw ArgumentError('لا يمكن ترحيل قيد يومية بدون أسطر');
    }

    int totalDebit = 0;
    int totalCredit = 0;

    for (final line in rawLines) {
      final debit = line['debit'] as int? ?? 0;
      final credit = line['credit'] as int? ?? 0;
      if (debit < 0 || credit < 0) {
        throw ArgumentError('قيم المدين والدائن يجب أن تكون أعداداً موجبة');
      }
      if (debit > 0 && credit > 0) {
        throw ArgumentError('السطر الواحد لا يمكن أن يحتوي على مدين ودائن معاً');
      }
      if (debit == 0 && credit == 0) {
        throw ArgumentError('يجب تحديد مبلغ مدين أو دائن في كل سطر');
      }
      totalDebit += debit;
      totalCredit += credit;
    }

    if (totalDebit != totalCredit) {
      throw ArgumentError(
        'قيد اليومية غير متوازن! إجمالي المدين: ${totalDebit / 100.0} SAR، إجمالي الدائن: ${totalCredit / 100.0} SAR',
      );
    }

    if (totalDebit <= 0) {
      throw ArgumentError('مبلغ القيد يجب أن يكون أكبر من صفر');
    }

    const uuid = Uuid();
    final entryId = 'je_${uuid.v4()}';
    final isoDate = entryDate.toIso8601String();

    final List<JournalLine> postedLines = [];

    _db.transaction((tx) {
      // 1. Insert Header
      tx.execute('''
        INSERT INTO journal_entries (
          id, company_id, branch_id, entry_number, entry_date,
          source_type, source_id, narration, total_debit, total_credit,
          is_balanced, status, created_at, created_by_user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'POSTED', datetime('now'), ?)
      ''', [
        entryId,
        companyId,
        branchId,
        entryNumber,
        isoDate,
        sourceType,
        sourceId,
        narration.trim(),
        totalDebit,
        totalCredit,
        userId,
      ]);

      // 2. Insert Lines & Update Account Balances
      for (final line in rawLines) {
        final lineId = 'jl_${uuid.v4()}';
        final accountId = line['accountId'] as String;
        final debit = line['debit'] as int? ?? 0;
        final credit = line['credit'] as int? ?? 0;
        final memo = line['memo'] as String?;

        tx.execute('''
          INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, memo)
          VALUES (?, ?, ?, ?, ?, ?)
        ''', [lineId, entryId, accountId, debit, credit, memo]);

        // Fetch account type and metadata to update normal balance
        final accResult = tx.select('SELECT account_type, code, name_ar FROM chart_of_accounts WHERE id = ?', [accountId]);
        if (accResult.isEmpty) {
          throw ArgumentError('الحساب المحاسبي غير موجود: $accountId');
        }
        final accRow = accResult.first;
        final accType = AccountType.fromString(accRow['account_type'] as String);
        final accCode = accRow['code'] as String?;
        final accName = accRow['name_ar'] as String?;

        // Debit normal accounts: +Debit, -Credit
        // Credit normal accounts: +Credit, -Debit
        final int balanceChange = accType.isDebitNormal ? (debit - credit) : (credit - debit);

        tx.execute('''
          UPDATE chart_of_accounts 
          SET current_balance = current_balance + ? 
          WHERE id = ?
        ''', [balanceChange, accountId]);

        postedLines.add(JournalLine(
          id: lineId,
          journalEntryId: entryId,
          accountId: accountId,
          debit: debit,
          credit: credit,
          memo: memo,
          accountCode: accCode,
          accountName: accName,
        ));
      }

      // 3. Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'LOCAL_DESKTOP', 'POST_JOURNAL_ENTRY', 'JOURNAL_ENTRY', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        entryId,
        'Entry: $entryNumber, Total: ${totalDebit / 100.0} SAR, Lines: ${rawLines.length}',
      ]);
    });

    return JournalEntry(
      id: entryId,
      companyId: companyId,
      branchId: branchId,
      entryNumber: entryNumber,
      entryDate: entryDate,
      sourceType: sourceType,
      sourceId: sourceId,
      narration: narration,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      createdAt: DateTime.now(),
      createdByUserId: userId,
      lines: postedLines,
    );
  }

  /// Automatically creates and posts the double-entry journal for a sales invoice
  JournalEntry postSalesInvoiceJournal({
    required String companyId,
    required String branchId,
    required String userId,
    required String invoiceId,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required int subtotalCents,
    required int taxCents,
    required int grandTotalCents,
    required int totalCostCents,
    required bool isCash,
  }) {
    seedStandardChartOfAccounts(companyId);

    // Retrieve system accounts
    final cashOrArCode = isCash ? '1010' : '1100';
    final cashOrArAccount = getAccountByCode(companyId, cashOrArCode);
    final salesRevAccount = getAccountByCode(companyId, '4010');
    final vatPayAccount = getAccountByCode(companyId, '2020');
    final cogsAccount = getAccountByCode(companyId, '5010');
    final inventoryAccount = getAccountByCode(companyId, '1200');

    if (cashOrArAccount == null || salesRevAccount == null || vatPayAccount == null) {
      throw StateError('شجرة الحسابات الأساسية للمبيعات غير مكتملة');
    }

    final rawLines = <Map<String, dynamic>>[];

    // 1. Debit Cash or Accounts Receivable
    rawLines.add({
      'accountId': cashOrArAccount.id,
      'debit': grandTotalCents,
      'credit': 0,
      'memo': 'إجمالي قيمة الفاتورة $invoiceNumber',
    });

    // 2. Credit Sales Revenue
    rawLines.add({
      'accountId': salesRevAccount.id,
      'debit': 0,
      'credit': subtotalCents,
      'memo': 'صافي مبيعات الفاتورة $invoiceNumber',
    });

    // 3. Credit VAT Output Payable (if tax > 0)
    if (taxCents > 0) {
      rawLines.add({
        'accountId': vatPayAccount.id,
        'debit': 0,
        'credit': taxCents,
        'memo': 'ضريبة القيمة المضافة 15% للفاتورة $invoiceNumber',
      });
    }

    // 4. Record COGS & Inventory movement if cost is available
    if (totalCostCents > 0 && cogsAccount != null && inventoryAccount != null) {
      // Debit COGS
      rawLines.add({
        'accountId': cogsAccount.id,
        'debit': totalCostCents,
        'credit': 0,
        'memo': 'تكلفة البضاعة المباعة للفاتورة $invoiceNumber',
      });
      // Credit Inventory
      rawLines.add({
        'accountId': inventoryAccount.id,
        'debit': 0,
        'credit': totalCostCents,
        'memo': 'خروج بضاعة من المخزن للفاتورة $invoiceNumber',
      });
    }

    return postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-SALES-$invoiceNumber',
      entryDate: invoiceDate,
      sourceType: 'SALES_INVOICE',
      sourceId: invoiceId,
      narration: 'قيد مبيعات آلي للفاتورة $invoiceNumber',
      rawLines: rawLines,
    );
  }

  /// Automatically creates and posts the double-entry journal for a Goods Receipt Note (GRN)
  JournalEntry postPurchaseGrnJournal({
    required String companyId,
    required String branchId,
    required String userId,
    required String grnId,
    required String grnNumber,
    required DateTime grnDate,
    required int totalCostCents,
    String? supplierName,
  }) {
    seedStandardChartOfAccounts(companyId);

    final inventoryAccount = getAccountByCode(companyId, '1200');
    final apAccount = getAccountByCode(companyId, '2010');

    if (inventoryAccount == null || apAccount == null) {
      throw StateError('شجرة الحسابات الأساسية للمشتريات والمخزون غير مكتملة');
    }

    final rawLines = [
      {
        'accountId': inventoryAccount.id,
        'debit': totalCostCents,
        'credit': 0,
        'memo': 'إضافة إلى المخزون سند استلام $grnNumber',
      },
      {
        'accountId': apAccount.id,
        'debit': 0,
        'credit': totalCostCents,
        'memo': 'مستحقات المورد ${supplierName ?? ''} سند $grnNumber',
      },
    ];

    return postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-GRN-$grnNumber',
      entryDate: grnDate,
      sourceType: 'PURCHASE_GRN',
      sourceId: grnId,
      narration: 'قيد استلام مخزني آلي لسند $grnNumber',
      rawLines: rawLines,
    );
  }

  /// Converts system source types into clear professional Arabic labels
  static String getArabicSourceTypeName(String sourceType) {
    switch (sourceType.toUpperCase()) {
      case 'SALES_INVOICE':
        return 'فاتورة مبيعات';
      case 'PURCHASE_INVOICE':
        return 'فاتورة مشتريات';
      case 'PURCHASE_GRN':
        return 'سند استلام بضاعة (GRN)';
      case 'MANUAL_JOURNAL':
        return 'قيد تسوية يدوي';
      case 'PAYROLL':
        return 'مسير رواتب موظفين';
      case 'SALARY_ADVANCE':
        return 'سند صرف سلفة موظف';
      case 'EXPENSE_VOUCHER':
      case 'EXPENSE':
        return 'سند صرف مصروفات وتشغيل';
      case 'CUSTOMER_PAYMENT':
        return 'سند قبض عميل';
      case 'SUPPLIER_PAYMENT':
        return 'سند صرف مورد';
      case 'REVERSAL':
        return 'قيد عكسي';
      case 'INVENTORY_ADJUSTMENT':
        return 'تسوية مخزنية';
      default:
        return sourceType;
    }
  }

  /// Retrieves list of journal entries with multi-filter and date range support
  List<JournalEntry> getJournalEntries(
    String companyId, {
    int limit = 100,
    DateTime? fromDate,
    DateTime? toDate,
    String? sourceType,
    String? query,
    String? status,
  }) {
    final whereClauses = <String>['company_id = ?'];
    final params = <dynamic>[companyId];

    if (fromDate != null) {
      whereClauses.add("date(entry_date) >= date(?)");
      params.add(fromDate.toIso8601String().substring(0, 10));
    }
    if (toDate != null) {
      whereClauses.add("date(entry_date) <= date(?)");
      params.add(toDate.toIso8601String().substring(0, 10));
    }
    if (sourceType != null && sourceType != 'ALL') {
      whereClauses.add("source_type = ?");
      params.add(sourceType);
    }
    if (status != null && status != 'ALL') {
      whereClauses.add("status = ?");
      params.add(status);
    }
    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add("(entry_number LIKE ? OR narration LIKE ?)");
      params.add('%${query.trim()}%');
      params.add('%${query.trim()}%');
    }

    final sql = '''
      SELECT * FROM journal_entries 
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY entry_date DESC, created_at DESC 
      LIMIT ?
    ''';
    params.add(limit);

    final entriesResult = _db.select(sql, params);

    final List<JournalEntry> list = [];

    for (final row in entriesResult) {
      final entryId = row['id'] as String;
      final linesResult = _db.select('''
        SELECT jl.*, ca.code as account_code, ca.name_ar as account_name
        FROM journal_lines jl
        JOIN chart_of_accounts ca ON jl.account_id = ca.id
        WHERE jl.journal_entry_id = ?
      ''', [entryId]);

      final lines = linesResult
          .map((lr) => JournalLine.fromMap(Map<String, dynamic>.from(lr)))
          .toList();

      list.add(JournalEntry.fromMap(Map<String, dynamic>.from(row), lines));
    }

    return list;
  }

  /// Calculates Trial Balance (ميزان المراجعة)
  List<TrialBalanceRow> getTrialBalance(String companyId) {
    seedStandardChartOfAccounts(companyId);

    final result = _db.select('''
      SELECT 
        ca.id as account_id,
        ca.code,
        ca.name_ar,
        ca.account_type,
        COALESCE(SUM(jl.debit), 0) as total_debit,
        COALESCE(SUM(jl.credit), 0) as total_credit,
        ca.current_balance
      FROM chart_of_accounts ca
      LEFT JOIN journal_lines jl ON ca.id = jl.account_id
      LEFT JOIN journal_entries je ON jl.journal_entry_id = je.id AND je.company_id = ?
      WHERE ca.company_id = ?
      GROUP BY ca.id
      ORDER BY ca.code ASC
    ''', [companyId, companyId]);

    return result.map((r) {
      return TrialBalanceRow(
        accountId: r['account_id'] as String,
        code: r['code'] as String,
        nameAr: r['name_ar'] as String,
        accountType: AccountType.fromString(r['account_type'] as String),
        totalDebit: r['total_debit'] as int,
        totalCredit: r['total_credit'] as int,
        netBalance: r['current_balance'] as int,
      );
    }).toList();
  }

  /// Retrieves General Ledger lines for a specific account
  List<GeneralLedgerLine> getGeneralLedger(String accountId) {
    final result = _db.select('''
      SELECT 
        je.entry_number,
        je.entry_date,
        COALESCE(jl.memo, je.narration) as narration,
        je.source_type,
        jl.debit,
        jl.credit
      FROM journal_lines jl
      JOIN journal_entries je ON jl.journal_entry_id = je.id
      WHERE jl.account_id = ?
      ORDER BY je.entry_date ASC, je.created_at ASC
    ''', [accountId]);

    int runningBalance = 0;
    // Check account normal balance
    final accRow = _db.select('SELECT account_type FROM chart_of_accounts WHERE id = ?', [accountId]).first;
    final accType = AccountType.fromString(accRow['account_type'] as String);

    final List<GeneralLedgerLine> lines = [];
    for (final r in result) {
      final debit = r['debit'] as int;
      final credit = r['credit'] as int;
      if (accType.isDebitNormal) {
        runningBalance += (debit - credit);
      } else {
        runningBalance += (credit - debit);
      }

      lines.add(GeneralLedgerLine(
        entryNumber: r['entry_number'] as String,
        entryDate: DateTime.parse(r['entry_date'] as String),
        narration: r['narration'] as String,
        sourceType: r['source_type'] as String,
        debit: debit,
        credit: credit,
        runningBalance: runningBalance,
      ));
    }

    return lines;
  }

  /// Calculates Income Statement (قائمة الدخل: الإيرادات، تكلفة البضاعة، الأرباح، المصروفات)
  IncomeStatement getIncomeStatement(String companyId) {
    seedStandardChartOfAccounts(companyId);

    final tb = getTrialBalance(companyId);

    int revenueTotal = 0;
    int cogsTotal = 0;
    int expensesTotal = 0;

    final List<AccountSummaryItem> revenueItems = [];
    final List<AccountSummaryItem> expenseItems = [];

    for (final row in tb) {
      if (row.accountType == AccountType.revenue) {
        revenueTotal += row.netBalance;
        if (row.netBalance != 0) {
          revenueItems.add(AccountSummaryItem(
            code: row.code,
            nameAr: row.nameAr,
            amountCents: row.netBalance,
          ));
        }
      } else if (row.accountType == AccountType.expense) {
        if (row.code == '5010') {
          cogsTotal += row.netBalance;
        } else {
          expensesTotal += row.netBalance;
        }
        if (row.netBalance != 0) {
          expenseItems.add(AccountSummaryItem(
            code: row.code,
            nameAr: row.nameAr,
            amountCents: row.netBalance,
          ));
        }
      }
    }

    final grossProfit = revenueTotal - cogsTotal;
    final netProfit = grossProfit - expensesTotal;

    return IncomeStatement(
      revenueCents: revenueTotal,
      cogsCents: cogsTotal,
      grossProfitCents: grossProfit,
      expensesCents: expensesTotal,
      netProfitCents: netProfit,
      revenueItems: revenueItems,
      expenseItems: expenseItems,
    );
  }

  /// Calculates Balance Sheet (الميزانية العمومية: الأصول = الالتزامات + حقوق الملكية)
  BalanceSheet getBalanceSheet(String companyId) {
    seedStandardChartOfAccounts(companyId);

    final tb = getTrialBalance(companyId);
    final income = getIncomeStatement(companyId);

    int assetsTotal = 0;
    int liabilitiesTotal = 0;
    int equityTotal = 0;

    final List<AccountSummaryItem> assetItems = [];
    final List<AccountSummaryItem> liabilityItems = [];
    final List<AccountSummaryItem> equityItems = [];

    for (final row in tb) {
      if (row.accountType == AccountType.asset) {
        assetsTotal += row.netBalance;
        if (row.netBalance != 0) {
          assetItems.add(AccountSummaryItem(
            code: row.code,
            nameAr: row.nameAr,
            amountCents: row.netBalance,
          ));
        }
      } else if (row.accountType == AccountType.liability) {
        liabilitiesTotal += row.netBalance;
        if (row.netBalance != 0) {
          liabilityItems.add(AccountSummaryItem(
            code: row.code,
            nameAr: row.nameAr,
            amountCents: row.netBalance,
          ));
        }
      } else if (row.accountType == AccountType.equity) {
        equityTotal += row.netBalance;
        if (row.netBalance != 0) {
          equityItems.add(AccountSummaryItem(
            code: row.code,
            nameAr: row.nameAr,
            amountCents: row.netBalance,
          ));
        }
      }
    }

    // In double-entry accounting:
    // Assets = Liabilities + Equity + Net Income (Current Earnings)
    final rightSide = liabilitiesTotal + equityTotal + income.netProfitCents;
    final isBalanced = assetsTotal == rightSide;

    return BalanceSheet(
      totalAssetsCents: assetsTotal,
      totalLiabilitiesCents: liabilitiesTotal,
      totalEquityCents: equityTotal,
      currentEarningsCents: income.netProfitCents,
      isBalanced: isBalanced,
      assetItems: assetItems,
      liabilityItems: liabilityItems,
      equityItems: equityItems,
    );
  }

  /// Ensures that standard accounts needed for expenses exist
  Account ensureAccount({
    required String companyId,
    required String code,
    required String nameAr,
    required String nameEn,
    required AccountType accountType,
  }) {
    final existing = getAccountByCode(companyId, code);
    if (existing != null) return existing;

    const uuid = Uuid();
    final newId = 'acc_${uuid.v4()}';
    _db.execute('''
      INSERT INTO chart_of_accounts (id, company_id, code, name_ar, name_en, account_type, is_leaf, is_active, current_balance)
      VALUES (?, ?, ?, ?, ?, ?, 1, 1, 0)
    ''', [newId, companyId, code, nameAr, nameEn, accountType.code]);

    return getAccountById(companyId, newId)!;
  }

  /// Posts an expense or fixed asset purchase voucher with automatic double-entry journal
  ExpenseVoucher postExpenseVoucher({
    required String companyId,
    required String branchId,
    required String userId,
    required String category, // 'RENT', 'UTILITIES', 'MAINTENANCE', 'FIXED_ASSET', 'SUPPLIES', 'OTHER'
    required int amountCents,
    required String paymentMethod, // 'CASH', 'BANK'
    required String description,
    String? referenceNo,
    DateTime? voucherDate,
  }) {
    seedStandardChartOfAccounts(companyId);

    final vDate = voucherDate ?? DateTime.now();
    final paymentCode = paymentMethod.toUpperCase() == 'BANK' ? '1020' : '1010';
    final paymentAcc = getAccountByCode(companyId, paymentCode);
    if (paymentAcc == null) {
      throw StateError('حساب وسيلة الدفع ($paymentCode) غير موجود في شجرة الحسابات');
    }

    // Determine target expense/asset account
    String expenseCode;
    String defaultArName;
    AccountType accType = AccountType.expense;

    switch (category.toUpperCase()) {
      case 'RENT':
        expenseCode = '5030';
        defaultArName = 'مصروف الإيجار';
        break;
      case 'UTILITIES':
        expenseCode = '5031';
        defaultArName = 'مصروفات كهرباء ومياه وهاتف وإنترنت';
        break;
      case 'MAINTENANCE':
        expenseCode = '5021';
        defaultArName = 'مصروفات صيانة وإصلاحات وأعطال';
        break;
      case 'FIXED_ASSET':
        expenseCode = '1500';
        defaultArName = 'الأصول والمعدات الثابتة (أجهزة وكاميرات ورفوف)';
        accType = AccountType.asset;
        break;
      case 'SUPPLIES':
        expenseCode = '5020';
        defaultArName = 'مصروفات إدارية وضيافة ومستلزمات';
        break;
      case 'OTHER':
      default:
        expenseCode = '5020';
        defaultArName = 'مصروفات تشغيلية وعمومية أخرى';
        break;
    }

    final targetAccount = ensureAccount(
      companyId: companyId,
      code: expenseCode,
      nameAr: defaultArName,
      nameEn: defaultArName,
      accountType: accType,
    );

    const uuid = Uuid();
    final voucherId = 'exp_${uuid.v4()}';
    final voucherNumber = 'VOUCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final categoryAr = ExpenseVoucher.getCategoryArabicName(category);

    // Double entry:
    // Debit: Expense or Asset
    // Credit: Cash or Bank
    final journalEntry = postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-$voucherNumber',
      entryDate: vDate,
      sourceType: 'EXPENSE_VOUCHER',
      sourceId: voucherId,
      narration: 'سند صرف ($categoryAr): $description',
      rawLines: [
        {
          'accountId': targetAccount.id,
          'debit': amountCents,
          'credit': 0,
          'memo': description,
        },
        {
          'accountId': paymentAcc.id,
          'debit': 0,
          'credit': amountCents,
          'memo': 'صرف من ${paymentAcc.nameAr} - سند $voucherNumber',
        },
      ],
    );

    _db.execute('''
      INSERT INTO expense_vouchers (
        id, company_id, voucher_number, category, expense_account_id, payment_account_id,
        amount_cents, payment_method, reference_no, description, voucher_date,
        journal_entry_id, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      voucherId,
      companyId,
      voucherNumber,
      category.toUpperCase(),
      targetAccount.id,
      paymentAcc.id,
      amountCents,
      paymentMethod.toUpperCase(),
      referenceNo,
      description,
      vDate.toIso8601String().substring(0, 10),
      journalEntry.id,
      userId,
    ]);

    return ExpenseVoucher(
      id: voucherId,
      companyId: companyId,
      voucherNumber: voucherNumber,
      category: category.toUpperCase(),
      expenseAccountId: targetAccount.id,
      paymentAccountId: paymentAcc.id,
      amountCents: amountCents,
      paymentMethod: paymentMethod.toUpperCase(),
      referenceNo: referenceNo,
      description: description,
      voucherDate: vDate,
      journalEntryId: journalEntry.id,
      createdBy: userId,
      createdAt: DateTime.now(),
      expenseAccountName: targetAccount.nameAr,
      paymentAccountName: paymentAcc.nameAr,
    );
  }

  /// Retrieves list of recorded expense vouchers
  List<ExpenseVoucher> getExpenseVouchers(
    String companyId, {
    int limit = 100,
    String? category,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final where = <String>['ev.company_id = ?'];
    final params = <dynamic>[companyId];

    if (category != null && category != 'ALL') {
      where.add('ev.category = ?');
      params.add(category.toUpperCase());
    }
    if (fromDate != null) {
      where.add('date(ev.voucher_date) >= date(?)');
      params.add(fromDate.toIso8601String().substring(0, 10));
    }
    if (toDate != null) {
      where.add('date(ev.voucher_date) <= date(?)');
      params.add(toDate.toIso8601String().substring(0, 10));
    }

    final sql = '''
      SELECT 
        ev.*,
        exp_acc.name_ar as expense_account_name,
        pay_acc.name_ar as payment_account_name
      FROM expense_vouchers ev
      JOIN chart_of_accounts exp_acc ON ev.expense_account_id = exp_acc.id
      JOIN chart_of_accounts pay_acc ON ev.payment_account_id = pay_acc.id
      WHERE ${where.join(' AND ')}
      ORDER BY ev.voucher_date DESC, ev.created_at DESC
      LIMIT ?
    ''';
    params.add(limit);

    final res = _db.select(sql, params);
    return res.map((r) => ExpenseVoucher.fromMap(Map<String, dynamic>.from(r))).toList();
  }
}
