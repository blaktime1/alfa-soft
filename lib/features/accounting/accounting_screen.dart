import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/printing/printer_service.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/accounting.dart';
import '../../data/repositories/accounting_repository.dart';

class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});

  @override
  ConsumerState<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedAccountTypeFilter = 'ALL';
  String? _selectedLedgerAccountId;

  // Journal Entries Filters
  String _journalDateFilter = 'ALL'; // 'TODAY', 'WEEK', 'MONTH', 'ALL', 'CUSTOM'
  DateTime? _journalFromDate;
  DateTime? _journalToDate;
  String _journalSourceFilter = 'ALL';
  final _journalSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _journalSearchController.dispose();
    super.dispose();
  }

  String _getCompanyId() {
    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    return compResult.isNotEmpty ? compResult.first['id'] as String : 'DEFAULT_COMPANY';
  }

  String _getBranchId() {
    final db = ref.read(databaseServiceProvider);
    final bResult = db.select('SELECT id FROM branches LIMIT 1');
    return bResult.isNotEmpty ? bResult.first['id'] as String : 'DEFAULT_BRANCH';
  }

  String _getUserId() {
    final db = ref.read(databaseServiceProvider);
    final uResult = db.select('SELECT id FROM users LIMIT 1');
    return uResult.isNotEmpty ? uResult.first['id'] as String : 'DEFAULT_USER';
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);
    final companyId = _getCompanyId();

    // Ensure standard chart of accounts is seeded
    repo.seedStandardChartOfAccounts(companyId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإدارة المالية والمحاسبية — General Ledger & Accounting'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_tree_rounded), text: 'دليل الحسابات (COA)'),
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'قيود اليومية (Journal Entries)'),
            Tab(icon: Icon(Icons.balance_rounded), text: 'ميزان المراجعة (Trial Balance)'),
            Tab(icon: Icon(Icons.pie_chart_rounded), text: 'القوائم المالية (P&L / Balance Sheet)'),
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'دفتر الأستاذ (General Ledger)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChartOfAccountsTab(context, repo, companyId),
          _buildJournalEntriesTab(context, repo, companyId),
          _buildTrialBalanceTab(context, repo, companyId),
          _buildFinancialStatementsTab(context, repo, companyId),
          _buildGeneralLedgerTab(context, repo, companyId),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: CHART OF ACCOUNTS
  // -------------------------------------------------------------
  Widget _buildChartOfAccountsTab(BuildContext context, AccountingRepository repo, String companyId) {
    final accounts = repo.getAccounts(companyId);
    final filtered = _selectedAccountTypeFilter == 'ALL'
        ? accounts
        : accounts.where((a) => a.accountType.code == _selectedAccountTypeFilter).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _filterChip('الكل', 'ALL'),
                  _filterChip('الأصول', 'ASSET'),
                  _filterChip('الالتزامات', 'LIABILITY'),
                  _filterChip('حقوق الملكية', 'EQUITY'),
                  _filterChip('الإيرادات', 'REVENUE'),
                  _filterChip('المصروفات', 'EXPENSE'),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showAddAccountDialog(context, repo, companyId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة حساب جديد'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final acc = filtered[index];
                  final balance = acc.currentBalance / 100.0;
                  return ListTile(
                    leading: Container(
                      width: 50,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _getTypeColor(acc.accountType).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        acc.code,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getTypeColor(acc.accountType),
                        ),
                      ),
                    ),
                    title: Text(acc.nameAr, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${acc.nameEn ?? ''} | النوع: ${acc.accountType.labelAr} (${acc.accountType.isDebitNormal ? 'طبيعة مدينة' : 'طبيعة دائنة'})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: Text(
                      '${balance.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: balance < 0 ? AppColors.error : AppColors.brandAccent,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _selectedAccountTypeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedAccountTypeFilter = value);
      },
    );
  }

  Color _getTypeColor(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return Colors.blue;
      case AccountType.liability:
        return Colors.orange;
      case AccountType.equity:
        return Colors.purple;
      case AccountType.revenue:
        return AppColors.success;
      case AccountType.expense:
        return AppColors.error;
    }
  }

  void _showAddAccountDialog(BuildContext context, AccountingRepository repo, String companyId) {
    final codeCtrl = TextEditingController();
    final nameArCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();
    AccountType selectedType = AccountType.asset;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة حساب جديد إلى دليل الحسابات'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الحساب (الكود) *', hintText: 'مثال: 1030'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameArCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الحساب بالعربية *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameEnCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الحساب بالإنجليزية (اختياري)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'نوع الحساب المحاسبي'),
                    items: AccountType.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text('${t.labelAr} (${t.code})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (codeCtrl.text.trim().isEmpty || nameArCtrl.text.trim().isEmpty) return;
                try {
                  repo.createAccount(
                    companyId: companyId,
                    code: codeCtrl.text.trim(),
                    nameAr: nameArCtrl.text.trim(),
                    nameEn: nameEnCtrl.text.trim().isEmpty ? null : nameEnCtrl.text.trim(),
                    accountType: selectedType,
                  );
                  Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('حفظ الحساب'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: JOURNAL ENTRIES
  // -------------------------------------------------------------
  Widget _buildJournalEntriesTab(BuildContext context, AccountingRepository repo, String companyId) {
    DateTime? effectiveFromDate;
    DateTime? effectiveToDate;
    final now = DateTime.now();

    if (_journalDateFilter == 'TODAY') {
      effectiveFromDate = DateTime(now.year, now.month, now.day);
      effectiveToDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_journalDateFilter == 'WEEK') {
      effectiveFromDate = now.subtract(const Duration(days: 7));
      effectiveToDate = now;
    } else if (_journalDateFilter == 'MONTH') {
      effectiveFromDate = now.subtract(const Duration(days: 30));
      effectiveToDate = now;
    } else if (_journalDateFilter == 'CUSTOM') {
      effectiveFromDate = _journalFromDate;
      effectiveToDate = _journalToDate;
    }

    final entries = repo.getJournalEntries(
      companyId,
      fromDate: effectiveFromDate,
      toDate: effectiveToDate,
      sourceType: _journalSourceFilter == 'ALL' ? null : _journalSourceFilter,
      query: _journalSearchController.text.trim(),
    );

    final totalDebits = entries.fold(0, (sum, e) => sum + e.totalDebit);
    final totalCredits = entries.fold(0, (sum, e) => sum + e.totalCredit);
    final isFullyBalanced = totalDebits == totalCredits;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with New Voucher Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.brandPrimary, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل قيود اليومية العامة (${entries.length} قيد)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Text(
                    'نظام القيد المزدوج المحاسبي الشامل — التحقق من توازن الحسابات والترحيل الآلي',
                    style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showNewExpenseVoucherDialog(context, repo, companyId),
                    icon: const Icon(Icons.outbox_rounded, color: Colors.teal),
                    label: const Text('سند صرف مصروفات وتشغيل', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.teal, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showNewVoucherDialog(context, repo, companyId),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('سند قيد يدوي جديد'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters Ribbon (Date Chips, Source Dropdown, Search Box)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightBgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lightBorderSubtle),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Search Field
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _journalSearchController,
                        decoration: InputDecoration(
                          hintText: 'بحث برقم القيد أو البيان أو الملاحظة...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _journalSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    setState(() => _journalSearchController.clear());
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Source Type Dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _journalSourceFilter,
                        decoration: InputDecoration(
                          labelText: 'مصدر القيد المحاسبي',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('جميع المصادر (All)')),
                          DropdownMenuItem(value: 'SALES_INVOICE', child: Text('فواتير مبيعات')),
                          DropdownMenuItem(value: 'PURCHASE_INVOICE', child: Text('فواتير مشتريات')),
                          DropdownMenuItem(value: 'PURCHASE_GRN', child: Text('استلام بضاعة GRN')),
                          DropdownMenuItem(value: 'EXPENSE_VOUCHER', child: Text('سند صرف مصروفات وتشغيل')),
                          DropdownMenuItem(value: 'SALARY_ADVANCE', child: Text('سند صرف سلفة موظف')),
                          DropdownMenuItem(value: 'PAYROLL', child: Text('مسير رواتب موظفين')),
                          DropdownMenuItem(value: 'MANUAL_JOURNAL', child: Text('قيود يدوية وتسويات')),
                          DropdownMenuItem(value: 'REVERSAL', child: Text('قيود عكسية')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _journalSourceFilter = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick Date Filters
                Row(
                  children: [
                    const Text('الفترة الزمنية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _journalDateFilter == 'ALL',
                      onSelected: (sel) => setState(() => _journalDateFilter = 'ALL'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('اليوم'),
                      selected: _journalDateFilter == 'TODAY',
                      onSelected: (sel) => setState(() => _journalDateFilter = 'TODAY'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('آخر 7 أيام'),
                      selected: _journalDateFilter == 'WEEK',
                      onSelected: (sel) => setState(() => _journalDateFilter = 'WEEK'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('هذا الشهر'),
                      selected: _journalDateFilter == 'MONTH',
                      onSelected: (sel) => setState(() => _journalDateFilter = 'MONTH'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(_journalDateFilter == 'CUSTOM' && _journalFromDate != null
                          ? '${DateFormat('yyyy-MM-dd').format(_journalFromDate!)} إلى ${DateFormat('yyyy-MM-dd').format(_journalToDate ?? DateTime.now())}'
                          : 'تحديد فترة مخصصة...'),
                      selected: _journalDateFilter == 'CUSTOM',
                      avatar: const Icon(Icons.date_range_rounded, size: 14),
                      onSelected: (sel) async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDateRange: _journalFromDate != null && _journalToDate != null
                              ? DateTimeRange(start: _journalFromDate!, end: _journalToDate!)
                              : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
                        );
                        if (picked != null) {
                          setState(() {
                            _journalDateFilter = 'CUSTOM';
                            _journalFromDate = picked.start;
                            _journalToDate = picked.end;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Double-Entry Balance Statistics Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isFullyBalanced
                  ? AppColors.success.withValues(alpha: 0.08)
                  : AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFullyBalanced ? AppColors.success.withValues(alpha: 0.4) : AppColors.danger.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isFullyBalanced ? Icons.check_circle_rounded : Icons.warning_rounded,
                  color: isFullyBalanced ? AppColors.success : AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isFullyBalanced ? 'القيود متزنة ومطابقة محاسبياً (المدين = الدائن)' : 'تحذير: يوجد عدم توازن في المبالغ!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isFullyBalanced ? AppColors.success : AppColors.danger,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text('إجمالي المدين: ${(totalDebits / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 16),
                Text('إجمالي الدائن: ${(totalCredits / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Entries List
          Expanded(
            child: Card(
              child: entries.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: AppColors.lightTextSecondary),
                            SizedBox(height: 12),
                            Text('لا توجد قيود محاسبية مطابقة لشروط البحث والفلترة المحددة',
                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary)),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final amount = (entry.totalDebit / 100.0).toStringAsFixed(2);
                        final arabicSource = AccountingRepository.getArabicSourceTypeName(entry.sourceType);

                        Color chipColor = Colors.blue;
                        if (entry.sourceType == 'SALES_INVOICE') chipColor = Colors.green;
                        if (entry.sourceType == 'PURCHASE_INVOICE' || entry.sourceType == 'PURCHASE_GRN') chipColor = Colors.orange;
                        if (entry.sourceType == 'PAYROLL') chipColor = Colors.purple;
                        if (entry.sourceType == 'REVERSAL') chipColor = Colors.red;

                        return ExpansionTile(
                          leading: Chip(
                            label: Text(arabicSource, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            backgroundColor: chipColor.withValues(alpha: 0.15),
                            side: BorderSide(color: chipColor.withValues(alpha: 0.3)),
                          ),
                          title: Row(
                            children: [
                              Text(entry.entryNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Text(
                                DateFormat('yyyy-MM-dd • hh:mm a').format(entry.entryDate),
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              if (entry.isBalanced)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('متزن ✓', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          subtitle: Text(entry.narration),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$amount ${PrinterService.defaultCurrency}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 14),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Table(
                                border: TableBorder.all(color: Colors.grey.shade300),
                                columnWidths: const {
                                  0: FlexColumnWidth(1.2),
                                  1: FlexColumnWidth(2.5),
                                  2: FlexColumnWidth(1.2),
                                  3: FlexColumnWidth(1.2),
                                  4: FlexColumnWidth(2.0),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1)),
                                    children: const [
                                      Padding(padding: EdgeInsets.all(6), child: Text('كود الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('اسم الحساب المحاسبي', style: TextStyle(fontWeight: FontWeight.bold))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('مدين (Debit)', style: TextStyle(fontWeight: FontWeight.bold))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('دائن (Credit)', style: TextStyle(fontWeight: FontWeight.bold))),
                                      Padding(padding: EdgeInsets.all(6), child: Text('البيان / تفصيل الحركة', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                  ...entry.lines.map((l) {
                                    return TableRow(
                                      children: [
                                        Padding(padding: const EdgeInsets.all(6), child: Text(l.accountCode ?? '')),
                                        Padding(padding: const EdgeInsets.all(6), child: Text(l.accountName ?? '')),
                                        Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(l.debit > 0 ? (l.debit / 100.0).toStringAsFixed(2) : '-',
                                              style: TextStyle(fontWeight: l.debit > 0 ? FontWeight.bold : FontWeight.normal)),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(l.credit > 0 ? (l.credit / 100.0).toStringAsFixed(2) : '-',
                                              style: TextStyle(fontWeight: l.credit > 0 ? FontWeight.bold : FontWeight.normal)),
                                        ),
                                        Padding(padding: const EdgeInsets.all(6), child: Text(l.memo ?? '')),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  if (entry.status == 'REVERSED')
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.danger.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('⚠️ تم عكس هذا القيد وإلغاء أثره المحاسبي',
                                          style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                                    )
                                  else
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.undo_rounded, size: 16, color: AppColors.danger),
                                      label: const Text('عكس وإلغاء القيد', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
                                      onPressed: () => _handleReverseJournalEntry(entry, repo),
                                    ),
                                  const Spacer(),
                                  Text('مصدر القيد: $arabicSource (${entry.sourceType})',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleReverseJournalEntry(JournalEntry entry, AccountingRepository repo) {
    final reasonCtrl = TextEditingController(text: 'عكس وإلغاء قيد تسوية');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد عكس القيد المحاسبي', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من عكس القيد رقم (${entry.entryNumber})؟ سيتم تبديل الدائن بالمدين وعكس الأثر المالي فوراً.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب العكس',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            icon: const Icon(Icons.undo_rounded),
            label: const Text('عكس القيد الآن'),
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              try {
                repo.reverseJournalEntry(
                  entryId: entry.id,
                  userId: _getUserId(),
                  reason: reason,
                );
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم عكس القيد رقم ${entry.entryNumber} بنجاح وإلغاء أثره'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ أثناء عكس القيد: $e'), backgroundColor: AppColors.danger),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showNewExpenseVoucherDialog(BuildContext context, AccountingRepository repo, String companyId) {
    String selectedCategory = 'RENT';
    String paymentMethod = 'CASH';
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController(text: 'سداد إيجار المحل');
    final refCtrl = TextEditingController();
    DateTime voucherDate = DateTime.now();

    final categories = [
      {'code': 'RENT', 'title': 'إيجار المقر / المحل الشهري أو السنوي', 'icon': Icons.storefront_rounded},
      {'code': 'UTILITIES', 'title': 'فواتير تشغيل (كهرباء ومياه وهاتف وإنترنت)', 'icon': Icons.bolt_rounded},
      {'code': 'MAINTENANCE', 'title': 'صيانة وإصلاح أعطال ومعدات', 'icon': Icons.build_rounded},
      {'code': 'FIXED_ASSET', 'title': 'شراء أصول ومعدات (كاميرات مراقبة، رفوف، أجهزة)', 'icon': Icons.videocam_rounded},
      {'code': 'SUPPLIES', 'title': 'مستلزمات نظافة وضيافة وأدوات مكتبية', 'icon': Icons.coffee_rounded},
      {'code': 'OTHER', 'title': 'مصروفات تشغيلية وعمومية أخرى', 'icon': Icons.payments_rounded},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.outbox_rounded, color: Colors.teal),
                ),
                const SizedBox(width: 10),
                const Text('سند صرف وتسجيل مصروفات وتشغيل / أصول'),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تسجيل مباشر للمصروفات مع إنشاء القيد المزدوج الآلي وتحديث أرصدة الخزينة والبنك',
                      style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                    ),
                    const SizedBox(height: 16),

                    // 1. Expense Category
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'تصنيف المصروف / البند',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['code'] as String,
                          child: Row(
                            children: [
                              Icon(c['icon'] as IconData, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(c['title'] as String, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedCategory = val;
                            if (val == 'RENT') descCtrl.text = 'سداد إيجار المحل';
                            if (val == 'UTILITIES') descCtrl.text = 'سداد فاتورة الكهرباء والإنترنت';
                            if (val == 'MAINTENANCE') descCtrl.text = 'صيانة وإصلاح أعطال';
                            if (val == 'FIXED_ASSET') descCtrl.text = 'شراء كاميرات مراقبة أو رفوف جديدة';
                            if (val == 'SUPPLIES') descCtrl.text = 'شراء مستلزمات نظافة وضيافة';
                            if (val == 'OTHER') descCtrl.text = 'مصروفات تشغيلية متنوعة';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // 2. Amount & Payment Method
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'المبلغ (${PrinterService.defaultCurrency})',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.attach_money_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: paymentMethod,
                            decoration: const InputDecoration(
                              labelText: 'طريقة الدفع',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'CASH', child: Text('نقداً (الخزينة)')),
                              DropdownMenuItem(value: 'BANK', child: Text('بنك / شبكة')),
                            ],
                            onChanged: (val) {
                              if (val != null) setDialogState(() => paymentMethod = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 3. Description
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'البيان / تفاصيل المصروف *',
                        hintText: 'مثال: إيجار شهر نوفمبر، أو شراء 4 كاميرات مراقبة هيكفيجن...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. Reference & Date
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: refCtrl,
                            decoration: const InputDecoration(
                              labelText: 'رقم الفاتورة / المرجع (اختياري)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: voucherDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() => voucherDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'تاريخ الصرف',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today_rounded),
                              ),
                              child: Text(
                                DateFormat('yyyy-MM-dd').format(voucherDate),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('تسجيل وترحيل سند الصرف'),
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  final desc = descCtrl.text.trim();
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر'), backgroundColor: AppColors.error),
                    );
                    return;
                  }
                  if (desc.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى كتابة بيان ووصف المصروف'), backgroundColor: AppColors.error),
                    );
                    return;
                  }

                  try {
                    final voucher = repo.postExpenseVoucher(
                      companyId: companyId,
                      branchId: _getBranchId(),
                      userId: _getUserId(),
                      category: selectedCategory,
                      amountCents: (amount * 100).round(),
                      paymentMethod: paymentMethod,
                      description: desc,
                      referenceNo: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                      voucherDate: voucherDate,
                    );

                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تسجيل سند الصرف رقم ${voucher.voucherNumber} وترحيل القيد المحاسبي بنجاح'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ أثناء حفظ سند الصرف: $e'), backgroundColor: AppColors.error),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showNewVoucherDialog(BuildContext context, AccountingRepository repo, String companyId) {
    final accounts = repo.getAccounts(companyId);
    final narrationCtrl = TextEditingController(text: 'قيد يومية تسوية يدوية');
    final lines = <Map<String, dynamic>>[
      {'accountId': accounts.first.id, 'debit': 0, 'credit': 0, 'memo': ''},
      {'accountId': accounts.length > 1 ? accounts[1].id : accounts.first.id, 'debit': 0, 'credit': 0, 'memo': ''},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          int totalDebit = lines.fold(0, (s, l) => s + (l['debit'] as int? ?? 0));
          int totalCredit = lines.fold(0, (s, l) => s + (l['credit'] as int? ?? 0));
          final isBalanced = totalDebit > 0 && totalDebit == totalCredit;

          return AlertDialog(
            title: const Text('إنشاء سند قيد محاسبي يدوي متوازن'),
            content: SizedBox(
              width: 750,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: narrationCtrl,
                      decoration: const InputDecoration(labelText: 'البيان العام للقيد *'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('أسطر القيد المحاسبي:', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              lines.add({
                                'accountId': accounts.first.id,
                                'debit': 0,
                                'credit': 0,
                                'memo': '',
                              });
                            });
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إضافة سطر'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(lines.length, (idx) {
                      final item = lines[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: item['accountId'] as String,
                                isExpanded: true,
                                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                items: accounts.map((a) {
                                  return DropdownMenuItem(
                                    value: a.id,
                                    child: Text('${a.code} - ${a.nameAr}', overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => item['accountId'] = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: item['debit'] == 0 ? '' : ((item['debit'] as int) / 100.0).toStringAsFixed(2),
                                decoration: const InputDecoration(
                                  labelText: 'مدين',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val) ?? 0;
                                  setDialogState(() {
                                    item['debit'] = (numVal * 100).round();
                                    if (item['debit'] > 0) item['credit'] = 0;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: item['credit'] == 0 ? '' : ((item['credit'] as int) / 100.0).toStringAsFixed(2),
                                decoration: const InputDecoration(
                                  labelText: 'دائن',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (val) {
                                  final numVal = double.tryParse(val) ?? 0;
                                  setDialogState(() {
                                    item['credit'] = (numVal * 100).round();
                                    if (item['credit'] > 0) item['debit'] = 0;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (lines.length > 2)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                onPressed: () {
                                  setDialogState(() => lines.removeAt(idx));
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                    // Balance indicator footer
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isBalanced ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('إجمالي المدين: ${(totalDebit / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('إجمالي الدائن: ${(totalCredit / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Icon(isBalanced ? Icons.check_circle : Icons.warning_amber_rounded,
                                  color: isBalanced ? AppColors.success : AppColors.error),
                              const SizedBox(width: 6),
                              Text(
                                isBalanced ? 'القيد متوازن تماماً' : 'غير متوازن (الفرق: ${((totalDebit - totalCredit).abs() / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isBalanced ? AppColors.success : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: !isBalanced
                    ? null
                    : () {
                        try {
                          final branchId = _getBranchId();
                          final userId = _getUserId();
                          final entryNumber = 'JV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

                          repo.postJournalEntry(
                            companyId: companyId,
                            branchId: branchId,
                            userId: userId,
                            entryNumber: entryNumber,
                            entryDate: DateTime.now(),
                            sourceType: 'MANUAL_VOUCHER',
                            narration: narrationCtrl.text.trim(),
                            rawLines: lines,
                          );

                          Navigator.pop(ctx);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم ترحيل السند $entryNumber بنجاح'), backgroundColor: AppColors.success),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('خطأ في الترحيل: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      },
                child: const Text('ترحيل القيد للميزانية'),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: TRIAL BALANCE (ميزان المراجعة)
  // -------------------------------------------------------------
  Widget _buildTrialBalanceTab(BuildContext context, AccountingRepository repo, String companyId) {
    final rows = repo.getTrialBalance(companyId);
    final totalDebits = rows.fold(0, (s, r) => s + r.totalDebit);
    final totalCredits = rows.fold(0, (s, r) => s + r.totalCredit);
    final isBalanced = totalDebits == totalCredits;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isBalanced ? AppColors.success.withValues(alpha: 0.12) : AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isBalanced ? AppColors.success : AppColors.error),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isBalanced ? Icons.verified_rounded : Icons.error_outline,
                        color: isBalanced ? AppColors.success : AppColors.error),
                    const SizedBox(width: 8),
                    Text(
                      isBalanced
                          ? 'ميزان المراجعة متوازن رياضياً بنسبة 100% (إجمالي المدين = إجمالي الدائن)'
                          : 'تنبيه: ميزان المراجعة غير متوازن! يوجد فرق محاسبي.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isBalanced ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
                Text(
                  'المجموع العام: ${(totalDebits / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('رقم الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('اسم الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('نوع الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('مجموع المدين (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('مجموع الدائن (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('الرصيد الصافي (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: [
                    ...rows.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(Text(r.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(r.nameAr)),
                          DataCell(Text(r.accountType.labelAr)),
                          DataCell(Text((r.totalDebit / 100.0).toStringAsFixed(2))),
                          DataCell(Text((r.totalCredit / 100.0).toStringAsFixed(2))),
                          DataCell(
                            Text(
                              (r.netBalance / 100.0).toStringAsFixed(2),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: r.netBalance < 0 ? AppColors.error : AppColors.brandAccent,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    // Total summary row
                    DataRow(
                      color: WidgetStateProperty.all(Colors.grey.withValues(alpha: 0.15)),
                      cells: [
                        const DataCell(Text('المجموع الإجمالي', style: TextStyle(fontWeight: FontWeight.bold))),
                        const DataCell(Text('')),
                        const DataCell(Text('')),
                        DataCell(Text(
                          (totalDebits / 100.0).toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                        )),
                        DataCell(Text(
                          (totalCredits / 100.0).toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                        )),
                        DataCell(Text('0.00 ${PrinterService.defaultCurrency} (موزون)', style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 4: FINANCIAL STATEMENTS (قائمة الدخل والميزانية العمومية)
  // -------------------------------------------------------------
  Widget _buildFinancialStatementsTab(BuildContext context, AccountingRepository repo, String companyId) {
    final income = repo.getIncomeStatement(companyId);
    final balanceSheet = repo.getBalanceSheet(companyId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 1. Income Statement Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.show_chart_rounded, color: AppColors.brandAccent),
                      const SizedBox(width: 8),
                      Text('قائمة الدخل والأرباح (Income Statement / P&L)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  _statementRow('إجمالي إيرادات المبيعات (Sales Revenue)', income.revenueCents, isHeader: true),
                  ...income.revenueItems.map((i) => _statementSubRow(i.nameAr, i.amountCents)),
                  const SizedBox(height: 8),
                  _statementRow('(-) تكلفة البضاعة المباعة (Cost of Goods Sold - COGS)', -income.cogsCents),
                  const Divider(height: 16),
                  _statementRow('(=) مجمل الربح التشغيلي (Gross Profit)', income.grossProfitCents, isBold: true, highlight: true),
                  const SizedBox(height: 12),
                  _statementRow('(-) المصروفات الإدارية والتشغيلية (Operating Expenses)', -income.expensesCents, isHeader: true),
                  ...income.expenseItems.map((i) => _statementSubRow(i.nameAr, i.amountCents)),
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (income.netProfitCents >= 0 ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'صافي الربح / (الخسارة) للفترة (Net Profit / Loss):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: income.netProfitCents >= 0 ? AppColors.success : AppColors.error,
                          ),
                        ),
                        Text(
                          '${(income.netProfitCents / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: income.netProfitCents >= 0 ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Balance Sheet Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, color: AppColors.brandPrimary),
                      const SizedBox(width: 8),
                      Text('الميزانية العمومية والمركز المالي (Balance Sheet)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Chip(
                        label: Text(
                          balanceSheet.isBalanced ? 'الميزانية متطابقة وموزونة' : 'الميزانية غير متطابقة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: balanceSheet.isBalanced ? AppColors.success : AppColors.error,
                          ),
                        ),
                        backgroundColor: (balanceSheet.isBalanced ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Assets Section
                  _statementRow('الأصول (Assets)', balanceSheet.totalAssetsCents, isHeader: true, isBold: true),
                  ...balanceSheet.assetItems.map((i) => _statementSubRow(i.nameAr, i.amountCents)),
                  const Divider(height: 16),
                  _statementRow('إجمالي الأصول (Total Assets)', balanceSheet.totalAssetsCents, isBold: true, highlight: true),
                  const SizedBox(height: 20),

                  // Liabilities Section
                  _statementRow('الالتزامات (Liabilities)', balanceSheet.totalLiabilitiesCents, isHeader: true, isBold: true),
                  ...balanceSheet.liabilityItems.map((i) => _statementSubRow(i.nameAr, i.amountCents)),
                  const Divider(height: 16),
                  _statementRow('إجمالي الالتزامات (Total Liabilities)', balanceSheet.totalLiabilitiesCents, isBold: true),
                  const SizedBox(height: 20),

                  // Equity Section
                  _statementRow('حقوق الملكية (Equity)', balanceSheet.totalEquityCents, isHeader: true, isBold: true),
                  ...balanceSheet.equityItems.map((i) => _statementSubRow(i.nameAr, i.amountCents)),
                  _statementSubRow('أرباح الفترة الحالية (من قائمة الدخل)', balanceSheet.currentEarningsCents),
                  const Divider(height: 16),
                  _statementRow(
                    'إجمالي الالتزامات وحقوق الملكية (Total Liabilities & Equity)',
                    balanceSheet.totalLiabilitiesCents + balanceSheet.totalEquityCents + balanceSheet.currentEarningsCents,
                    isBold: true,
                    highlight: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statementRow(String label, int amountCents, {bool isHeader = false, bool isBold = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: (isBold || isHeader) ? FontWeight.bold : FontWeight.normal,
              fontSize: isHeader ? 15 : (isBold ? 14 : 13),
              color: highlight ? AppColors.brandAccent : null,
            ),
          ),
          Text(
            '${(amountCents / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
            style: TextStyle(
              fontWeight: (isBold || isHeader) ? FontWeight.bold : FontWeight.normal,
              fontSize: isHeader ? 15 : (isBold ? 15 : 13),
              color: highlight ? AppColors.brandAccent : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statementSubRow(String label, int amountCents) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 2, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Text('${(amountCents / 100.0).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 5: GENERAL LEDGER (دفتر الأستاذ)
  // -------------------------------------------------------------
  Widget _buildGeneralLedgerTab(BuildContext context, AccountingRepository repo, String companyId) {
    final accounts = repo.getAccounts(companyId);
    if (_selectedLedgerAccountId == null && accounts.isNotEmpty) {
      _selectedLedgerAccountId = accounts.first.id;
    }

    final lines = _selectedLedgerAccountId != null ? repo.getGeneralLedger(_selectedLedgerAccountId!) : <GeneralLedgerLine>[];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text('اختر الحساب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 12),
              SizedBox(
                width: 350,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedLedgerAccountId,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: accounts.map((a) {
                    return DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.code} - ${a.nameAr}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLedgerAccountId = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: lines.isEmpty
                  ? const Center(child: Text('لا توجد حركات مسجلة لهذا الحساب'))
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: [
                          const DataColumn(label: Text('رقم القيد', style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text('البيان / الوصف', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('مدين (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('دائن (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الرصيد التراكمي (${PrinterService.defaultCurrency})', style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: lines.map((l) {
                          return DataRow(
                            cells: [
                              DataCell(Text(l.entryNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(DateFormat('yyyy-MM-dd').format(l.entryDate))),
                              DataCell(Text(l.narration)),
                              DataCell(Text(l.debit > 0 ? (l.debit / 100.0).toStringAsFixed(2) : '-')),
                              DataCell(Text(l.credit > 0 ? (l.credit / 100.0).toStringAsFixed(2) : '-')),
                              DataCell(
                                Text(
                                  (l.runningBalance / 100.0).toStringAsFixed(2),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandAccent),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
