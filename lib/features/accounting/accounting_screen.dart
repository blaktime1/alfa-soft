import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/printing/printer_service.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/accounting.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../core/widgets/operation_success_dialog.dart';
import '../../core/providers/license_provider.dart';

class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});

  @override
  ConsumerState<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedAccountTypeFilter = 'ALL';
  String? _selectedLedgerAccountId;

  // Vouchers Hub State & Filters
  String _voucherCategoryFilter = 'ALL';
  String _voucherStatusFilter = 'ALL'; // 'ALL', 'POSTED', 'REVERSED'
  final _voucherSearchController = TextEditingController();

  // Journal Entries Filters
  String _journalDateFilter = 'ALL'; // 'TODAY', 'WEEK', 'MONTH', 'ALL', 'CUSTOM'
  DateTime? _journalFromDate;
  DateTime? _journalToDate;
  String _journalSourceFilter = 'ALL';
  final _journalSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _voucherSearchController.dispose();
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
            Tab(icon: Icon(Icons.receipt_rounded), text: 'سندات الصرف والقبض (Vouchers Hub)'),
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
          _buildVouchersTab(context, repo, companyId),
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
  // TAB 0: VOUCHERS HUB (سندات الصرف والقبض والإيجارات والمصروفات)
  // -------------------------------------------------------------
  Widget _buildVouchersTab(BuildContext context, AccountingRepository repo, String companyId) {
    final db = ref.read(databaseServiceProvider);

    // 1. Expense Vouchers
    final expenseVouchers = repo.getExpenseVouchers(companyId);

    // 2. Receipt Vouchers from journal_entries
    final receiptRows = db.select('''
      SELECT je.*,
             COALESCE(
               (SELECT c.name_ar FROM journal_lines jl JOIN chart_of_accounts c ON jl.account_id = c.id WHERE jl.journal_entry_id = je.id AND jl.credit > 0 LIMIT 1),
               'إيرادات متنوعة'
             ) as credit_account_name,
             COALESCE(
               (SELECT c.name_ar FROM journal_lines jl JOIN chart_of_accounts c ON jl.account_id = c.id WHERE jl.journal_entry_id = je.id AND jl.debit > 0 LIMIT 1),
               'الصندوق الرئيسي'
             ) as debit_account_name,
             COALESCE(
               (SELECT SUM(jl.debit) FROM journal_lines jl WHERE jl.journal_entry_id = je.id),
               0
             ) as amount_cents
      FROM journal_entries je
      WHERE je.company_id = ? AND (je.source_type = 'RECEIPT_VOUCHER' OR je.source_type = 'REVENUE_DEPOSIT')
      ORDER BY je.entry_date DESC, je.created_at DESC
    ''', [companyId]);

    final List<_UnifiedVoucherEntry> allVouchers = [];

    for (final ev in expenseVouchers) {
      allVouchers.add(_UnifiedVoucherEntry(
        id: ev.id,
        number: ev.voucherNumber,
        type: 'EXPENSE',
        category: ev.category,
        categoryAr: ExpenseVoucher.getCategoryArabicName(ev.category),
        date: ev.voucherDate,
        amount: ev.amountCents / 100.0,
        description: ev.description,
        targetAccount: ev.expenseAccountName ?? 'مصروفات تشغيلية',
        treasuryAccount: ev.paymentAccountName ?? (ev.paymentMethod == 'BANK' ? 'البنك' : 'الصندوق الرئيسي'),
        paymentMethod: ev.paymentMethod,
        status: ev.status,
        journalEntryId: ev.journalEntryId,
        referenceNo: ev.referenceNo,
        isExpense: true,
      ));
    }

    for (final r in receiptRows) {
      allVouchers.add(_UnifiedVoucherEntry(
        id: r['id'] as String,
        number: (r['source_id'] as String? ?? r['entry_number'] as String),
        type: 'RECEIPT',
        category: 'RECEIPT',
        categoryAr: 'سند قبض وإيداع إيراد / إيجار',
        date: DateTime.parse(r['entry_date'] as String),
        amount: (r['amount_cents'] as int) / 100.0,
        description: r['narration'] as String,
        targetAccount: r['credit_account_name'] as String,
        treasuryAccount: r['debit_account_name'] as String,
        paymentMethod: 'CASH',
        status: r['status'] as String,
        journalEntryId: r['id'] as String,
        referenceNo: null,
        isExpense: false,
      ));
    }

    // Sort by date descending
    allVouchers.sort((a, b) => b.date.compareTo(a.date));

    // Filter
    final query = _voucherSearchController.text.trim().toLowerCase();
    final filtered = allVouchers.where((v) {
      // Category filter
      if (_voucherCategoryFilter != 'ALL') {
        if (_voucherCategoryFilter == 'EXPENSE' && !v.isExpense) return false;
        if (_voucherCategoryFilter == 'RECEIPT' && v.isExpense) return false;
        if (_voucherCategoryFilter != 'EXPENSE' && _voucherCategoryFilter != 'RECEIPT' && v.category != _voucherCategoryFilter) return false;
      }
      // Status filter
      if (_voucherStatusFilter == 'POSTED' && (v.status == 'REVERSED' || v.status == 'CANCELLED')) return false;
      if (_voucherStatusFilter == 'REVERSED' && (v.status != 'REVERSED' && v.status != 'CANCELLED')) return false;
      // Search query
      if (query.isNotEmpty) {
        final matches = v.number.toLowerCase().contains(query) ||
            v.description.toLowerCase().contains(query) ||
            v.categoryAr.toLowerCase().contains(query) ||
            v.targetAccount.toLowerCase().contains(query) ||
            (v.referenceNo != null && v.referenceNo!.toLowerCase().contains(query));
        if (!matches) return false;
      }
      return true;
    }).toList();

    // Statistics
    double totalActiveExpenses = 0;
    double totalActiveReceipts = 0;
    int reversedCount = 0;

    for (final v in allVouchers) {
      if (v.status == 'REVERSED' || v.status == 'CANCELLED') {
        reversedCount++;
      } else {
        if (v.isExpense) {
          totalActiveExpenses += v.amount;
        } else {
          totalActiveReceipts += v.amount;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildVoucherKpiCard(
                  title: 'إجمالي المصروفات التشغيلية السارية',
                  value: '${totalActiveExpenses.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                  icon: Icons.outbox_rounded,
                  color: Colors.red.shade700,
                  bgColor: Colors.red.shade50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoucherKpiCard(
                  title: 'إجمالي المقبوضات والإيداعات السارية',
                  value: '${totalActiveReceipts.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                  icon: Icons.move_to_inbox_rounded,
                  color: Colors.green.shade700,
                  bgColor: Colors.green.shade50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoucherKpiCard(
                  title: 'صافي التدفق المالي (إيداعات - مصروفات)',
                  value: '${(totalActiveReceipts - totalActiveExpenses).toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                  icon: Icons.account_balance_wallet_rounded,
                  color: (totalActiveReceipts - totalActiveExpenses) >= 0 ? Colors.teal.shade700 : Colors.deepOrange.shade700,
                  bgColor: (totalActiveReceipts - totalActiveExpenses) >= 0 ? Colors.teal.shade50 : Colors.deepOrange.shade50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoucherKpiCard(
                  title: 'السندات الملغاة والمعكوسة',
                  value: '$reversedCount سند',
                  icon: Icons.cancel_schedule_send_rounded,
                  color: Colors.blueGrey.shade700,
                  bgColor: Colors.blueGrey.shade50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Toolbar & Search
          Row(
            children: [
              // Search input
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _voucherSearchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ابحث برقم السند، البيان، الحساب، أو المرجع...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    suffixIcon: _voucherSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _voucherSearchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),

              // Category Filter Dropdown
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _voucherCategoryFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('جميع تصنيفات السندات')),
                      DropdownMenuItem(value: 'EXPENSE', child: Text('سندات الصرف فقط')),
                      DropdownMenuItem(value: 'RECEIPT', child: Text('سندات القبض والإيداع فقط')),
                      DropdownMenuItem(value: 'RENT', child: Text('سندات إيجار المحل')),
                      DropdownMenuItem(value: 'UTILITIES', child: Text('فواتير كهرباء ومياه وإنترنت')),
                      DropdownMenuItem(value: 'MAINTENANCE', child: Text('صيانة وإصلاحات')),
                      DropdownMenuItem(value: 'FIXED_ASSET', child: Text('كاميرات ومعدات وأصول')),
                      DropdownMenuItem(value: 'SUPPLIES', child: Text('مستلزمات وضيافة')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _voucherCategoryFilter = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Status Filter Dropdown
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _voucherStatusFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('جميع الحالات')),
                      DropdownMenuItem(value: 'POSTED', child: Text('السارية والمعتمدة فقط')),
                      DropdownMenuItem(value: 'REVERSED', child: Text('الملغاة والمعكوسة فقط')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _voucherStatusFilter = val);
                    },
                  ),
                ),
              ),
              const Spacer(),

              // Button: New Expense Voucher
              ElevatedButton.icon(
                icon: const Icon(Icons.outbox_rounded, size: 16),
                label: const Text('سند صرف مصروفات جديد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showNewExpenseVoucherDialog(context, repo, companyId),
              ),
              const SizedBox(width: 8),

              // Button: New Receipt Voucher
              ElevatedButton.icon(
                icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                label: const Text('سند إيداع / قبض إيراد جديد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showReceiptVoucherDialog(context, repo, companyId),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Vouchers List Table
          Expanded(
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('لا توجد سندات صرف أو قبض مسجلة مطابقة للبحث', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final v = filtered[idx];
                        final isReversed = v.status == 'REVERSED' || v.status == 'CANCELLED';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor: isReversed
                                ? Colors.grey.shade200
                                : (v.isExpense ? Colors.red.shade50 : Colors.green.shade50),
                            child: Icon(
                              isReversed
                                  ? Icons.cancel_outlined
                                  : (v.isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                              color: isReversed
                                  ? Colors.grey
                                  : (v.isExpense ? Colors.red.shade700 : Colors.green.shade700),
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                v.number,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  decoration: isReversed ? TextDecoration.lineThrough : null,
                                  color: isReversed ? Colors.grey : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isReversed
                                      ? Colors.grey.shade100
                                      : (v.isExpense ? Colors.red.shade50 : Colors.green.shade50),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isReversed
                                        ? Colors.grey.shade300
                                        : (v.isExpense ? Colors.red.shade200 : Colors.green.shade200),
                                  ),
                                ),
                                child: Text(
                                  v.categoryAr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isReversed
                                        ? Colors.grey.shade700
                                        : (v.isExpense ? Colors.red.shade800 : Colors.green.shade800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isReversed)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('ملغي ومعكوس', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('معتمد وساري', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Text('البيان: ${v.description}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                                const SizedBox(width: 12),
                                Text('• الحساب: ${v.targetAccount}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                const SizedBox(width: 12),
                                Text('• الخزينة/الدفع: ${v.treasuryAccount}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                const SizedBox(width: 12),
                                Text('• التاريخ: ${v.date.toIso8601String().substring(0, 10)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${v.amount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  decoration: isReversed ? TextDecoration.lineThrough : null,
                                  color: isReversed
                                      ? Colors.grey
                                      : (v.isExpense ? Colors.red.shade700 : Colors.green.shade700),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Action: View Journal Entry
                              IconButton(
                                icon: const Icon(Icons.menu_book_rounded, color: Colors.blueGrey, size: 20),
                                tooltip: 'معاينة القيد المحاسبي المزدوج',
                                onPressed: () => _showVoucherLinesDialog(context, v),
                              ),

                              // Action: Edit Voucher Notes
                              if (!isReversed)
                                IconButton(
                                  icon: const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary, size: 20),
                                  tooltip: 'تعديل بيان السند',
                                  onPressed: () => _showEditVoucherDialog(context, repo, v),
                                ),

                              // Action: Void & Reverse Voucher
                              if (!isReversed)
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 20),
                                  tooltip: 'إلغاء وعكس السند (استرجاع الرصيد)',
                                  onPressed: () => _confirmVoidVoucher(context, repo, v),
                                ),
                            ],
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

  Widget _buildVoucherKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            radius: 18,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showVoucherLinesDialog(BuildContext context, _UnifiedVoucherEntry v) {
    if (v.journalEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد قيد محاسبي مسجل')));
      return;
    }
    final db = ref.read(databaseServiceProvider);
    final lines = db.select('''
      SELECT jl.*, c.code, c.name_ar, c.account_type
      FROM journal_lines jl
      JOIN chart_of_accounts c ON jl.account_id = c.id
      WHERE jl.journal_entry_id = ?
      ORDER BY jl.debit DESC, jl.credit DESC
    ''', [v.journalEntryId]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.account_tree_rounded, color: AppColors.brandPrimary),
            const SizedBox(width: 8),
            Text('معاينة القيد المحاسبي المزدوج للسند (${v.number})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('البيان: ${v.description}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text('التاريخ: ${v.date.toIso8601String().substring(0, 10)} | الحالة: ${v.status}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                  columns: const [
                    DataColumn(label: Text('كود الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('اسم الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('مدين (Debit)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('دائن (Credit)', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: lines.map((l) {
                    final debit = (l['debit'] as int) / 100.0;
                    final credit = (l['credit'] as int) / 100.0;
                    return DataRow(
                      cells: [
                        DataCell(Text(l['code'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(l['name_ar'] as String)),
                        DataCell(Text(debit > 0 ? debit.toStringAsFixed(2) : '-', style: TextStyle(color: debit > 0 ? Colors.green.shade700 : Colors.black))),
                        DataCell(Text(credit > 0 ? credit.toStringAsFixed(2) : '-', style: TextStyle(color: credit > 0 ? Colors.red.shade700 : Colors.black))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _showEditVoucherDialog(BuildContext context, AccountingRepository repo, _UnifiedVoucherEntry v) {
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن تعديل السندات.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (v.status == 'REVERSED' || v.status == 'CANCELLED') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن تعديل سند ملغي ومعكوس')));
      return;
    }
    final descCtrl = TextEditingController(text: v.description);
    final refCtrl = TextEditingController(text: v.referenceNo ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary),
            const SizedBox(width: 8),
            Text('تعديل بيان السند (${v.number})'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'البيان والملاحظات *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(labelText: 'رقم المرجع / الشيك / الإيصال', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final newDesc = descCtrl.text.trim();
              if (newDesc.isEmpty) return;
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              if (v.isExpense) {
                repo.updateExpenseVoucher(
                  voucherId: v.id,
                  description: newDesc,
                  referenceNo: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                );
              }
              if (v.journalEntryId != null) {
                db.execute(
                  "UPDATE journal_entries SET narration = ? WHERE id = ?",
                  ['${v.categoryAr}: $newDesc', v.journalEntryId],
                );
              }
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم تحديث بيان السند ${v.number} بنجاح'), backgroundColor: AppColors.success),
              );
            },
            child: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    );
  }

  void _confirmVoidVoucher(BuildContext context, AccountingRepository repo, _UnifiedVoucherEntry v) {
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن إلغاء أو عكس السندات.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (v.status == 'REVERSED' || v.status == 'CANCELLED') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذا السند ملغي ومعكوس مسبقاً')));
      return;
    }
    if (v.journalEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد قيد محاسبي مرتبط بهذا السند لإلغائه')));
      return;
    }

    final reasonCtrl = TextEditingController(text: 'إلغاء بسبب خطأ في الإدخال');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.danger),
            const SizedBox(width: 8),
            Text('تأكيد إلغاء وعكس السند (${v.number})'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل ترغب فعلاً في إلغاء السند "${v.categoryAr}" بمبلغ ${v.amount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}؟\n\nسيقوم النظام آلياً بتسجيل قيد عكسي متوازن واسترجاع المبالغ لحساب الخزينة/البنك.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'سبب الإلغاء والعكس *', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              final reason = reasonCtrl.text.trim().isEmpty ? 'إلغاء السند' : reasonCtrl.text.trim();
              Navigator.pop(ctx);
              try {
                final userId = _getUserId();
                try {
                  repo.reverseJournalEntry(
                    entryId: v.journalEntryId!,
                    userId: userId,
                    reason: reason,
                  );
                } catch (revError) {
                  // If journal entry was already marked REVERSED, gracefully update voucher status
                  if (!revError.toString().contains('معكوس مسبقاً')) {
                    rethrow;
                  }
                }
                final db = ref.read(databaseServiceProvider);
                if (v.isExpense) {
                  try {
                    db.execute("UPDATE expense_vouchers SET status = 'CANCELLED' WHERE id = ?", [v.id]);
                  } catch (_) {}
                }
                setState(() {});
                OperationSuccessDialog.show(
                  context: context,
                  title: 'تم إلغاء وعكس السند بنجاح',
                  message: 'تم عكس القيد المحاسبي وإلغاء أثر السند واسترجاع الرصيد للخزينة بنجاح.',
                  referenceCode: v.number,
                  amountText: '${v.amount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ أثناء إلغاء السند: $e'), backgroundColor: AppColors.danger),
                );
              }
            },
            child: const Text('تأكيد الإلغاء والعكس فوراً'),
          ),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showReceiptVoucherDialog(context, repo, companyId),
                    icon: const Icon(Icons.input_rounded, size: 18),
                    label: const Text('سند قبض / إيداع إيجار وإيراد'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddAccountDialog(context, repo, companyId),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('إضافة حساب جديد'),
                  ),
                ],
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
                  final isSystem = repo.isSystemAccount(acc.code);

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
                    title: Row(
                      children: [
                        Text(acc.nameAr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        if (isSystem)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded, size: 11, color: Colors.blueGrey),
                                SizedBox(width: 3),
                                Text('حساب أساسي', style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${acc.nameEn ?? ''} | النوع: ${acc.accountType.labelAr} (${acc.accountType.isDebitNormal ? 'طبيعة مدينة' : 'طبيعة دائنة'})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${balance.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: balance < 0 ? AppColors.error : AppColors.brandAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!isSystem)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                            tooltip: 'حذف الحساب المضاف',
                            onPressed: () => _confirmDeleteAccount(context, repo, acc),
                          ),
                      ],
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
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن إضافة حسابات جديدة بدليل الحسابات.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

  void _confirmDeleteAccount(BuildContext context, AccountingRepository repo, Account acc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد حذف الحساب المضاف'),
          ],
        ),
        content: Text(
          'هل ترغب فعلاً في حذف الحساب "${acc.nameAr}" (كود: ${acc.code})؟\n\nتنبيه: لا يمكن حذف الحساب إذا كان يحمل رصيداً مالياً أو توجد قيود مسجلة عليه.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              try {
                repo.deleteAccount(acc.id);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حذف الحساب "${acc.nameAr}" بنجاح'), backgroundColor: AppColors.success),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceAll('ArgumentError: ', '')), backgroundColor: AppColors.danger),
                );
              }
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  void _showReceiptVoucherDialog(BuildContext context, AccountingRepository repo, String companyId) {
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط لانتهاء الترخيص أو العبث بالتوقيت. لا يمكن إصدار سندات قبض جديدة حتى تجديد الترخيص.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final receiptNumber = 'RCT-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController(text: 'إيداع إيجار عقار / متجر لشهر ${DateTime.now().month}-${DateTime.now().year}');
    final refCtrl = TextEditingController();
    DateTime voucherDate = DateTime.now();

    final allAccounts = repo.getAccounts(companyId);
    final cashAccounts = allAccounts.where((a) => a.accountType == AccountType.asset && (a.code == '1010' || a.code == '1020' || a.code.startsWith('10'))).toList();
    final revAccounts = allAccounts.where((a) => a.accountType == AccountType.revenue || a.accountType == AccountType.liability).toList();

    String debitAccountId = cashAccounts.isNotEmpty ? cashAccounts.first.id : allAccounts.first.id;
    // Prefer rental revenue account 4030 or rental security 2030 or first revenue
    String creditAccountId = revAccounts.firstWhere(
      (a) => a.code == '4030',
      orElse: () => revAccounts.isNotEmpty ? revAccounts.first : allAccounts.last,
    ).id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.input_rounded, color: AppColors.success),
              SizedBox(width: 8),
              Text('سند قبض وإيداع إيراد / إيجار جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('رقم السند: $receiptNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(voucherDate)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Debit Account (Where money entered: Cash or Bank)
                  DropdownButtonFormField<String>(
                    initialValue: debitAccountId,
                    decoration: const InputDecoration(labelText: 'إيداع إلى حساب (المدين - أين دخل المال؟) *', border: OutlineInputBorder()),
                    items: cashAccounts.map((a) {
                      return DropdownMenuItem(value: a.id, child: Text('${a.nameAr} (${a.code})'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDState(() => debitAccountId = v);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Credit Account (Source of revenue: Rent 4030 or Deposit 2030)
                  DropdownButtonFormField<String>(
                    initialValue: creditAccountId,
                    decoration: const InputDecoration(labelText: 'لحساب إيراد / أمانات (الدائن - مقابل ماذا؟) *', border: OutlineInputBorder()),
                    items: revAccounts.map((a) {
                      return DropdownMenuItem(value: a.id, child: Text('${a.nameAr} (${a.code})'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDState(() => creditAccountId = v);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Amount
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'مبلغ الإيداع بـ (${PrinterService.defaultCurrency}) *',
                      hintText: '0.00',
                      border: const OutlineInputBorder(),
                    ),
                    onTap: () => amountCtrl.selection = TextSelection(baseOffset: 0, extentOffset: amountCtrl.text.length),
                  ),
                  const SizedBox(height: 12),

                  // Description
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'بيان وسند الإيداع *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  // Reference Number / Cheque
                  TextFormField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الإشعار البنكي / الشيك / المرجع (اختياري)', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('ترحيل سند القبض والإيداع فوراً'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')));
                  return;
                }
                if (descCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى كتابة بيان السند')));
                  return;
                }

                try {
                  final db = ref.read(databaseServiceProvider);
                  final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                  final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                  repo.postReceiptVoucher(
                    companyId: companyId,
                    branchId: branchId,
                    userId: userId,
                    receiptNumber: receiptNumber,
                    voucherDate: voucherDate,
                    amountCents: (amount * 100).round(),
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    description: descCtrl.text.trim(),
                    referenceNumber: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                  );

                  Navigator.pop(ctx);
                  setState(() {});
                  OperationSuccessDialog.show(
                    context: context,
                    title: 'تم تسجيل وترحيل سند القبض بنجاح',
                    message: 'تم توريد المبلغ إلى الخزينة وقيد السند في اليومية العامة آلياً.',
                    referenceCode: receiptNumber,
                    amountText: '${amount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.danger));
                }
              },
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
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن عكس أو إلغاء القيود اليومية.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن تسجيل سندات صرف ومصروفات جديدة.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
                    OperationSuccessDialog.show(
                      context: context,
                      title: 'تم تسجيل سند الصرف والمصروفات بنجاح',
                      message: 'تم قيد سند المصروف وترحيل القيد في دفتر اليومية العامة وحسم المبلغ من الخزينة.',
                      referenceCode: voucher.voucherNumber,
                      amountText: '${amount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
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
    final license = ref.read(licenseInfoProvider);
    if (license.isReadOnlyArchive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('النظام يعمل في وضع الأرشيف والقراءة فقط. لا يمكن إنشاء قيود يومية جديدة.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

class _UnifiedVoucherEntry {
  final String id;
  final String number;
  final String type; // 'EXPENSE' or 'RECEIPT'
  final String category;
  final String categoryAr;
  final DateTime date;
  final double amount;
  final String description;
  final String targetAccount;
  final String treasuryAccount;
  final String paymentMethod;
  final String status;
  final String? journalEntryId;
  final String? referenceNo;
  final bool isExpense;

  _UnifiedVoucherEntry({
    required this.id,
    required this.number,
    required this.type,
    required this.category,
    required this.categoryAr,
    required this.date,
    required this.amount,
    required this.description,
    required this.targetAccount,
    required this.treasuryAccount,
    required this.paymentMethod,
    required this.status,
    this.journalEntryId,
    this.referenceNo,
    required this.isExpense,
  });
}
