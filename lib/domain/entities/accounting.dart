enum AccountType {
  asset('ASSET', 'أصول', true),
  liability('LIABILITY', 'التزامات', false),
  equity('EQUITY', 'حقوق ملكية', false),
  revenue('REVENUE', 'إيرادات', false),
  expense('EXPENSE', 'مصروفات', true);

  final String code;
  final String labelAr;
  final bool isDebitNormal;

  const AccountType(this.code, this.labelAr, this.isDebitNormal);

  static AccountType fromString(String val) {
    return AccountType.values.firstWhere(
      (e) => e.code.toUpperCase() == val.toUpperCase() || e.name.toUpperCase() == val.toUpperCase(),
      orElse: () => AccountType.asset,
    );
  }
}

class Account {
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final AccountType accountType;
  final String? parentId;
  final bool isLeaf;
  final bool isActive;
  final int currentBalance;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    this.nameEn,
    required this.accountType,
    this.parentId,
    this.isLeaf = true,
    this.isActive = true,
    this.currentBalance = 0,
    required this.createdAt,
  });

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String?,
      accountType: AccountType.fromString(map['account_type'] as String),
      parentId: map['parent_id'] as String?,
      isLeaf: (map['is_leaf'] as int? ?? 1) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      currentBalance: map['current_balance'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'code': code,
      'name_ar': nameAr,
      'name_en': nameEn,
      'account_type': accountType.code,
      'parent_id': parentId,
      'is_leaf': isLeaf ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'current_balance': currentBalance,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class JournalLine {
  final String id;
  final String journalEntryId;
  final String accountId;
  final int debit;
  final int credit;
  final String? memo;
  final String? accountCode;
  final String? accountName;

  const JournalLine({
    required this.id,
    required this.journalEntryId,
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.memo,
    this.accountCode,
    this.accountName,
  });

  factory JournalLine.fromMap(Map<String, dynamic> map) {
    return JournalLine(
      id: map['id'] as String,
      journalEntryId: map['journal_entry_id'] as String,
      accountId: map['account_id'] as String,
      debit: map['debit'] as int? ?? 0,
      credit: map['credit'] as int? ?? 0,
      memo: map['memo'] as String?,
      accountCode: map['account_code'] as String?,
      accountName: map['account_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'journal_entry_id': journalEntryId,
      'account_id': accountId,
      'debit': debit,
      'credit': credit,
      'memo': memo,
    };
  }
}

class JournalEntry {
  final String id;
  final String companyId;
  final String branchId;
  final String entryNumber;
  final DateTime entryDate;
  final String sourceType;
  final String? sourceId;
  final String narration;
  final int totalDebit;
  final int totalCredit;
  final bool isBalanced;
  final String status;
  final DateTime createdAt;
  final String createdByUserId;
  final List<JournalLine> lines;

  const JournalEntry({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.entryNumber,
    required this.entryDate,
    required this.sourceType,
    this.sourceId,
    required this.narration,
    required this.totalDebit,
    required this.totalCredit,
    this.isBalanced = true,
    this.status = 'POSTED',
    required this.createdAt,
    required this.createdByUserId,
    this.lines = const [],
  });

  factory JournalEntry.fromMap(Map<String, dynamic> map, [List<JournalLine> lines = const []]) {
    return JournalEntry(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      branchId: map['branch_id'] as String,
      entryNumber: map['entry_number'] as String,
      entryDate: DateTime.parse(map['entry_date'] as String),
      sourceType: map['source_type'] as String,
      sourceId: map['source_id'] as String?,
      narration: map['narration'] as String,
      totalDebit: map['total_debit'] as int,
      totalCredit: map['total_credit'] as int,
      isBalanced: (map['is_balanced'] as int? ?? 1) == 1,
      status: map['status'] as String? ?? 'POSTED',
      createdAt: DateTime.parse(map['created_at'] as String),
      createdByUserId: map['created_by_user_id'] as String,
      lines: lines,
    );
  }
}

class TrialBalanceRow {
  final String accountId;
  final String code;
  final String nameAr;
  final AccountType accountType;
  final int totalDebit;
  final int totalCredit;
  final int netBalance;

  const TrialBalanceRow({
    required this.accountId,
    required this.code,
    required this.nameAr,
    required this.accountType,
    required this.totalDebit,
    required this.totalCredit,
    required this.netBalance,
  });
}

class GeneralLedgerLine {
  final String entryNumber;
  final DateTime entryDate;
  final String narration;
  final String sourceType;
  final int debit;
  final int credit;
  final int runningBalance;

  const GeneralLedgerLine({
    required this.entryNumber,
    required this.entryDate,
    required this.narration,
    required this.sourceType,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });
}

class AccountSummaryItem {
  final String code;
  final String nameAr;
  final int amountCents;

  const AccountSummaryItem({
    required this.code,
    required this.nameAr,
    required this.amountCents,
  });
}

class IncomeStatement {
  final int revenueCents;
  final int cogsCents;
  final int grossProfitCents;
  final int expensesCents;
  final int netProfitCents;
  final List<AccountSummaryItem> revenueItems;
  final List<AccountSummaryItem> expenseItems;

  const IncomeStatement({
    required this.revenueCents,
    required this.cogsCents,
    required this.grossProfitCents,
    required this.expensesCents,
    required this.netProfitCents,
    this.revenueItems = const [],
    this.expenseItems = const [],
  });
}

class BalanceSheet {
  final int totalAssetsCents;
  final int totalLiabilitiesCents;
  final int totalEquityCents;
  final int currentEarningsCents;
  final bool isBalanced;
  final List<AccountSummaryItem> assetItems;
  final List<AccountSummaryItem> liabilityItems;
  final List<AccountSummaryItem> equityItems;

  const BalanceSheet({
    required this.totalAssetsCents,
    required this.totalLiabilitiesCents,
    required this.totalEquityCents,
    required this.currentEarningsCents,
    required this.isBalanced,
    this.assetItems = const [],
    this.liabilityItems = const [],
    this.equityItems = const [],
  });
}

class ExpenseVoucher {
  final String id;
  final String companyId;
  final String voucherNumber;
  final String category; // 'RENT', 'UTILITIES', 'MAINTENANCE', 'FIXED_ASSET', 'SUPPLIES', 'OTHER'
  final String expenseAccountId;
  final String paymentAccountId;
  final int amountCents;
  final String paymentMethod; // 'CASH', 'BANK'
  final String? referenceNo;
  final String description;
  final DateTime voucherDate;
  final String? journalEntryId;
  final String? createdBy;
  final DateTime createdAt;
  final String? expenseAccountName;
  final String? paymentAccountName;

  const ExpenseVoucher({
    required this.id,
    required this.companyId,
    required this.voucherNumber,
    required this.category,
    required this.expenseAccountId,
    required this.paymentAccountId,
    required this.amountCents,
    required this.paymentMethod,
    this.referenceNo,
    required this.description,
    required this.voucherDate,
    this.journalEntryId,
    this.createdBy,
    required this.createdAt,
    this.expenseAccountName,
    this.paymentAccountName,
  });

  factory ExpenseVoucher.fromMap(Map<String, dynamic> map) {
    return ExpenseVoucher(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      voucherNumber: map['voucher_number'] as String,
      category: map['category'] as String,
      expenseAccountId: map['expense_account_id'] as String,
      paymentAccountId: map['payment_account_id'] as String,
      amountCents: map['amount_cents'] as int,
      paymentMethod: map['payment_method'] as String,
      referenceNo: map['reference_no'] as String?,
      description: map['description'] as String,
      voucherDate: DateTime.parse(map['voucher_date'] as String),
      journalEntryId: map['journal_entry_id'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      expenseAccountName: map['expense_account_name'] as String?,
      paymentAccountName: map['payment_account_name'] as String?,
    );
  }

  static String getCategoryArabicName(String category) {
    switch (category.toUpperCase()) {
      case 'RENT':
        return 'إيجار شهري / سنوي';
      case 'UTILITIES':
        return 'فواتير كهرباء ومياه وإنترنت';
      case 'MAINTENANCE':
        return 'صيانة وتصليح أعطال';
      case 'FIXED_ASSET':
        return 'أصول ومعدات (كاميرات، رفوف، أجهزة)';
      case 'SUPPLIES':
        return 'ضيافة ونظافة ومستلزمات';
      case 'OTHER':
      default:
        return 'مصروفات تشغيلية أخرى';
    }
  }
}
