import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/printing/printer_service.dart';
import '../../domain/entities/enterprise.dart';
import '../../data/repositories/enterprise_repository.dart';
import '../../data/repositories/accounting_repository.dart';

class EnterpriseScreen extends ConsumerStatefulWidget {
  const EnterpriseScreen({super.key});

  @override
  ConsumerState<EnterpriseScreen> createState() => _EnterpriseScreenState();
}

class _EnterpriseScreenState extends ConsumerState<EnterpriseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late EnterpriseRepository _enterpriseRepo;
  late AccountingRepository _accountingRepo;

  List<Employee> _employees = [];
  List<ApprovalRequest> _approvals = [];
  List<CostCenter> _costCenters = [];
  List<SalaryAdvance> _salaryAdvances = [];
  PayrollRun? _lastPayrollRun;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final db = ref.read(databaseServiceProvider);
    _enterpriseRepo = EnterpriseRepository(db);
    _accountingRepo = AccountingRepository(db);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getCompanyId() {
    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    return compResult.isNotEmpty ? compResult.first['id'] as String : 'c1';
  }

  String _getBranchId() {
    final db = ref.read(databaseServiceProvider);
    final bResult = db.select('SELECT id FROM branches LIMIT 1');
    return bResult.isNotEmpty ? bResult.first['id'] as String : 'b1';
  }

  String _getUserId() {
    final db = ref.read(databaseServiceProvider);
    final uResult = db.select('SELECT id FROM users LIMIT 1');
    return uResult.isNotEmpty ? uResult.first['id'] as String : 'u1';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final companyId = _getCompanyId();

    try {
      final emps = _enterpriseRepo.getEmployees(companyId);
      final apps = _enterpriseRepo.getApprovalRequests(companyId);
      final ccs = _enterpriseRepo.getCostCenters(companyId);
      final latestRun = _enterpriseRepo.getLatestPayrollRun(companyId);
      final advances = _enterpriseRepo.getSalaryAdvances(companyId);

      setState(() {
        _employees = emps;
        _approvals = apps;
        _costCenters = ccs;
        _lastPayrollRun = latestRun;
        _salaryAdvances = advances;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGeneratePayroll() async {
    final companyId = _getCompanyId();
    final month = DateFormat('yyyy-MM').format(DateTime.now());

    try {
      final run = _enterpriseRepo.generatePayrollRun(
        companyId: companyId,
        periodMonth: month,
      );

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم توليد مسير رواتب شهر $month بنجاح! الإجمالي الصافي: ${(run.totalNet / 100).toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String friendlyError = e.toString();
        if (friendlyError.contains('UNIQUE constraint failed') || friendlyError.contains('مسبقاً')) {
          friendlyError = 'تم توليد واعتماد مسير الرواتب لشهر $month مسبقاً في القيود المحاسبية. لا يمكن إعادة توليده لمنع ازدواجية الصرف.';
        } else if (friendlyError.startsWith('Exception: ')) {
          friendlyError = friendlyError.replaceFirst('Exception: ', '');
        } else if (friendlyError.startsWith('Bad state: ')) {
          friendlyError = friendlyError.replaceFirst('Bad state: ', '');
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.brandPrimary),
                SizedBox(width: 8),
                Text('تنبيه مسير الرواتب'),
              ],
            ),
            content: Text(
              friendlyError,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً، فهمت'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleApproveAndPostPayroll() async {
    if (_lastPayrollRun == null) return;
    final companyId = _getCompanyId();
    final branchId = _getBranchId();
    final userId = _getUserId();

    try {
      _enterpriseRepo.approvePayrollRun(
        payrollRunId: _lastPayrollRun!.id,
        userId: userId,
      );

      final entry = _enterpriseRepo.postPayrollToGeneralLedger(
        payrollRunId: _lastPayrollRun!.id,
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        accountingRepo: _accountingRepo,
      );

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد وترحيل مسير الرواتب إلى دفتر الأستاذ العام بنجاح! رقم القيد: ${entry.entryNumber}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل ترحيل المسير: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showRecordAdvanceDialog() {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل موظف واحد على الأقل قبل صرف السلف'), backgroundColor: AppColors.error),
      );
      return;
    }

    String selectedEmployeeId = _employees.first.id;
    String paymentMethod = 'CASH';
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: 'سلفة على الراتب');
    String repaymentMonth = DateFormat('yyyy-MM').format(DateTime.now());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedEmp = _employees.firstWhere((e) => e.id == selectedEmployeeId, orElse: () => _employees.first);

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.request_quote_rounded, color: AppColors.brandAccent),
                SizedBox(width: 8),
                Text('صرف سلفة موظف (سحب من الراتب)'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'يتم تسجيل السلفة كقيد محاسبي فوري (سلف موظفين - مدين، والخزينة/البنك - دائن) ويتم استقطاعها آلياً عند توليد مسير الرواتب.',
                      style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                    ),
                    const SizedBox(height: 16),

                    // 1. Employee Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: selectedEmployeeId,
                      decoration: const InputDecoration(
                        labelText: 'اختر الموظف المستفيد *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      items: _employees.map((emp) {
                        return DropdownMenuItem(
                          value: emp.id,
                          child: Text('${emp.fullName} (${emp.jobTitle}) - الراتب: ${(emp.grossSalary / 100).toStringAsFixed(0)} ${PrinterService.defaultCurrency}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedEmployeeId = val);
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
                              labelText: 'مبلغ السلفة (${PrinterService.defaultCurrency}) *',
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
                              labelText: 'وسيلة الصرف',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'CASH', child: Text('نقداً (الخزينة)')),
                              DropdownMenuItem(value: 'BANK', child: Text('بنك / تحويل')),
                            ],
                            onChanged: (val) {
                              if (val != null) setDialogState(() => paymentMethod = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 3. Repayment Month
                    DropdownButtonFormField<String>(
                      initialValue: repaymentMonth,
                      decoration: const InputDecoration(
                        labelText: 'شهر الاستقطاع من المسير *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_month_rounded),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: DateFormat('yyyy-MM').format(DateTime.now()),
                          child: Text('هذا الشهر (${DateFormat('yyyy-MM').format(DateTime.now())})'),
                        ),
                        DropdownMenuItem(
                          value: DateFormat('yyyy-MM').format(DateTime.now().add(const Duration(days: 31))),
                          child: Text('الشهر القادم (${DateFormat('yyyy-MM').format(DateTime.now().add(const Duration(days: 31)))})'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => repaymentMonth = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 4. Notes
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'البيان / سبب السلفة',
                        hintText: 'مثال: سحب دفعة نقدية لظرف طارئ...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandAccent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('اعتماد وصرف السلفة'),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(ctx);

                  if (amount <= 0) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر'), backgroundColor: AppColors.error),
                    );
                    return;
                  }

                  if (amount * 100 > selectedEmp.grossSalary) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('تحذير: مبلغ السلفة يتجاوز إجمالي الراتب الشهري للموظف (${(selectedEmp.grossSalary / 100).toStringAsFixed(2)} ${PrinterService.defaultCurrency})'),
                        backgroundColor: Colors.orange.shade800,
                      ),
                    );
                  }

                  try {
                    final advance = _enterpriseRepo.recordSalaryAdvance(
                      companyId: _getCompanyId(),
                      branchId: _getBranchId(),
                      userId: _getUserId(),
                      employeeId: selectedEmployeeId,
                      amountCents: (amount * 100).round(),
                      paymentMethod: paymentMethod,
                      repaymentMonth: repaymentMonth,
                      notes: notesCtrl.text.trim(),
                      accountingRepo: _accountingRepo,
                    );

                    nav.pop();
                    await _loadData();

                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('تم صرف السلفة رقم ${advance.advanceNumber} للموظف ${advance.employeeName} بنجاح وقيدها دفترياً'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('خطأ أثناء تسجيل السلفة: $e'), backgroundColor: AppColors.error),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleProcessStep(ApprovalRequest req, bool isApproved) async {
    final userId = _getUserId();
    try {
      _enterpriseRepo.processApprovalStep(
        approvalRequestId: req.id,
        approverUserId: userId,
        isApproved: isApproved,
        comments: isApproved ? 'موافق عليه رسمياً' : 'مرفوض لعدم استيفاء الشروط',
      );

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isApproved ? 'تم تسجيل الموافقة على الطلب بنجاح' : 'تم رفض الطلب'),
            backgroundColor: isApproved ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الميزات المؤسسية المتقدمة — Enterprise Suite'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded), text: 'الموظفون ومسيرات الرواتب (HR & Payroll)'),
            Tab(icon: Icon(Icons.rule_folder_rounded), text: 'سير الموافقات متعدد المستويات (Approvals)'),
            Tab(icon: Icon(Icons.account_tree_rounded), text: 'مراكز التكلفة (Cost Centers)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildHrPayrollTab(context),
                _buildApprovalsTab(context),
                _buildCostCentersTab(context),
              ],
            ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: HR & PAYROLL RUNS
  // -------------------------------------------------------------
  Widget _buildHrPayrollTab(BuildContext context) {
    final curFmt = NumberFormat.currency(symbol: '${PrinterService.defaultCurrency} ', decimalDigits: 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('سجل الموظفين والكوادر (${_employees.length} موظف)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showRecordAdvanceDialog,
                    icon: const Icon(Icons.request_quote_rounded, color: Colors.orange),
                    label: const Text('صرف سلفة موظف (سحب من الراتب)', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orange, width: 1.5),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showCreateEmployeeDialog,
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('إضافة موظف جديد'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _handleGeneratePayroll,
                    icon: const Icon(Icons.payments_rounded),
                    label: const Text('توليد مسير الرواتب الشهري'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandAccent),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Employees Table
          Card(
            child: _employees.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لا يوجد موظفون مسجلون حالياً. أضف موظفين للبدء.')),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('كود الموظف')),
                        DataColumn(label: Text('الاسم الكامل')),
                        DataColumn(label: Text('المسمى الوظيفي')),
                        DataColumn(label: Text('القسم')),
                        DataColumn(label: Text('الراتب الأساسي')),
                        DataColumn(label: Text('البدلات (سكن/مواصلات)')),
                        DataColumn(label: Text('إجمالي الراتب')),
                        DataColumn(label: Text('الحالة')),
                      ],
                      rows: _employees.map((emp) {
                        return DataRow(cells: [
                          DataCell(Text(emp.employeeCode, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(emp.fullName)),
                          DataCell(Text(emp.jobTitle)),
                          DataCell(Text(emp.department)),
                          DataCell(Text(curFmt.format(emp.basicSalary / 100))),
                          DataCell(Text(curFmt.format((emp.housingAllowance + emp.transportAllowance) / 100))),
                          DataCell(Text(curFmt.format(emp.grossSalary / 100),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success))),
                          DataCell(Chip(
                            label: Text(emp.status == 'ACTIVE' ? 'نشط' : emp.status),
                            backgroundColor: emp.status == 'ACTIVE'
                                ? AppColors.success.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.2),
                            side: BorderSide.none,
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          // Salary Advances Section
          if (_salaryAdvances.isNotEmpty) ...[
            Text('سجل سلف الموظفين والمسحوبات (${_salaryAdvances.length} سلفة)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('رقم السلفة')),
                    const DataColumn(label: Text('اسم الموظف')),
                    DataColumn(label: Text('المبلغ (${PrinterService.defaultCurrency})')),
                    const DataColumn(label: Text('طريقة الصرف')),
                    const DataColumn(label: Text('تاريخ الصرف')),
                    const DataColumn(label: Text('شهر الاستقطاع')),
                    const DataColumn(label: Text('الحالة')),
                    const DataColumn(label: Text('البيان')),
                  ],
                  rows: _salaryAdvances.map((adv) {
                    final isPending = adv.status == 'PENDING';
                    return DataRow(cells: [
                      DataCell(Text(adv.advanceNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(adv.employeeName ?? '')),
                      DataCell(Text(curFmt.format(adv.amountCents / 100),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                      DataCell(Text(adv.paymentMethod == 'BANK' ? 'بنك / تحويل' : 'نقداً من الخزينة')),
                      DataCell(Text(DateFormat('yyyy-MM-dd').format(adv.requestDate))),
                      DataCell(Text(adv.repaymentMonth)),
                      DataCell(Chip(
                        label: Text(isPending ? 'بانتظار الاستقطاع' : 'تم الاستقطاع بالمسير'),
                        backgroundColor: isPending ? Colors.orange.withValues(alpha: 0.15) : AppColors.success.withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: isPending ? Colors.orange.shade800 : AppColors.success),
                        side: BorderSide.none,
                      )),
                      DataCell(Text(adv.notes ?? '-')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Active/Generated Payroll Run
          if (_lastPayrollRun != null) ...[
            Text('مسير الرواتب المستحق: ${_lastPayrollRun!.periodMonth}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('حالة المسير: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Chip(
                              label: Text(
                                _lastPayrollRun!.status == 'POSTED_TO_JOURNAL'
                                    ? 'تم الترحيل للدفاتر المحاسبية (نهائي)'
                                    : (_lastPayrollRun!.status == 'APPROVED' ? 'معتمد' : 'مسودة قيد المراجعة'),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              backgroundColor: _lastPayrollRun!.status == 'POSTED_TO_JOURNAL'
                                  ? AppColors.brandPrimary.withValues(alpha: 0.15)
                                  : (_lastPayrollRun!.status == 'APPROVED' ? AppColors.success.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15)),
                              side: BorderSide.none,
                            ),
                          ],
                        ),
                        if (_lastPayrollRun!.status == 'DRAFT')
                          ElevatedButton.icon(
                            onPressed: _handleApproveAndPostPayroll,
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('اعتماد وترحيل فوري للقيود المحاسبية'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metricTile('إجمالي الرواتب الأساسية', curFmt.format(_lastPayrollRun!.totalGross / 100)),
                        _metricTile('إجمالي الاستقطاعات والسلف', curFmt.format(_lastPayrollRun!.totalDeductions / 100), color: Colors.orange.shade800),
                        _metricTile('صافي الرواتب المستحقة', curFmt.format(_lastPayrollRun!.totalNet / 100),
                            color: AppColors.success),
                      ],
                    ),
                    if (_lastPayrollRun!.slips.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text('تفاصيل قسائم رواتب الموظفين (Salary Slips):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            const DataColumn(label: Text('الموظف')),
                            DataColumn(label: Text('الأساسي (${PrinterService.defaultCurrency})')),
                            DataColumn(label: Text('البدلات (${PrinterService.defaultCurrency})')),
                            DataColumn(label: Text('الاستقطاعات/السلف (${PrinterService.defaultCurrency})')),
                            DataColumn(label: Text('صافي الراتب (${PrinterService.defaultCurrency})')),
                          ],
                          rows: _lastPayrollRun!.slips.map((slip) {
                            return DataRow(cells: [
                              DataCell(Text(slip.employeeName ?? slip.employeeId, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(curFmt.format(slip.basicSalary / 100))),
                              DataCell(Text(curFmt.format(slip.allowances / 100))),
                              DataCell(Text(curFmt.format(slip.deductions / 100),
                                  style: TextStyle(color: slip.deductions > 0 ? Colors.orange.shade900 : null, fontWeight: slip.deductions > 0 ? FontWeight.bold : null))),
                              DataCell(Text(curFmt.format(slip.netSalary / 100),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: MULTI-TIER APPROVALS
  // -------------------------------------------------------------
  Widget _buildApprovalsTab(BuildContext context) {
    final curFmt = NumberFormat.currency(symbol: '${PrinterService.defaultCurrency} ', decimalDigits: 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('طلبات الاعتماد والموافقات المشروطة (${_approvals.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ElevatedButton.icon(
                onPressed: _showCreateSampleApprovalDialog,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('إنشاء طلب اعتماد تجريبي'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_approvals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('لا توجد طلبات اعتماد معلقة حالياً.')),
              ),
            )
          else
            ..._approvals.map((req) {
              final isPending = req.status == 'PENDING';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                req.status == 'APPROVED'
                                    ? Icons.check_circle_rounded
                                    : (req.status == 'REJECTED' ? Icons.cancel_rounded : Icons.pending_actions_rounded),
                                color: req.status == 'APPROVED'
                                    ? AppColors.success
                                    : (req.status == 'REJECTED' ? AppColors.error : AppColors.brandAccent),
                              ),
                              const SizedBox(width: 8),
                              Text('${req.documentType} #${req.requestNumber}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          Chip(
                            label: Text(
                              req.status == 'PENDING'
                                  ? 'بانتظار المستوى ${req.currentStepLevel} من ${req.requiredStepLevels}'
                                  : req.status,
                            ),
                            backgroundColor: isPending
                                ? AppColors.brandAccent.withValues(alpha: 0.15)
                                : (req.status == 'APPROVED'
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.error.withValues(alpha: 0.15)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('القيمة المالية للمستند: ${curFmt.format(req.amount / 100)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: req.steps.map((st) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Chip(
                              avatar: Icon(
                                st.decision == 'APPROVED'
                                    ? Icons.check
                                    : (st.decision == 'REJECTED' ? Icons.close : Icons.hourglass_top),
                                size: 14,
                              ),
                              label: Text('المستوى ${st.stepLevel}: ${st.roleRequired} (${st.decision})'),
                            ),
                          );
                        }).toList(),
                      ),
                      if (isPending) ...[
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _handleProcessStep(req, false),
                              icon: const Icon(Icons.close_rounded, color: AppColors.error),
                              label: const Text('رفض الطلب', style: TextStyle(color: AppColors.error)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () => _handleProcessStep(req, true),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('اعتماد وموافقة'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: COST CENTERS
  // -------------------------------------------------------------
  Widget _buildCostCentersTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('دليل مراكز التكلفة والمشاريع (${_costCenters.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ElevatedButton.icon(
                onPressed: _showCreateCostCenterDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة مركز تكلفة جديد'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: _costCenters.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لا توجد مراكز تكلفة مسجلة حالياً.')),
                  )
                : DataTable(
                    columns: const [
                      DataColumn(label: Text('رمز المركز (Code)')),
                      DataColumn(label: Text('الاسم بالعربية')),
                      DataColumn(label: Text('الاسم بالإنجليزية')),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: _costCenters.map((cc) {
                      return DataRow(cells: [
                        DataCell(Text(cc.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(cc.nameAr)),
                        DataCell(Text(cc.nameEn ?? '—')),
                        DataCell(Chip(
                          label: Text(cc.isActive ? 'نشط' : 'معطل'),
                          backgroundColor: cc.isActive
                              ? AppColors.success.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.2),
                          side: BorderSide.none,
                        )),
                      ]);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // DIALOGS
  // -------------------------------------------------------------
  void _showCreateEmployeeDialog() {
    final codeCtrl = TextEditingController(text: 'EMP-${_employees.length + 101}');
    final nameCtrl = TextEditingController();
    final nationalIdCtrl = TextEditingController(text: '1098765432');
    final titleCtrl = TextEditingController(text: 'محاسب عام');
    final deptCtrl = TextEditingController(text: 'الإدارة المالية');
    final salaryCtrl = TextEditingController(text: '6500');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة موظف جديد'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'كود الموظف')),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 8),
              TextField(controller: nationalIdCtrl, decoration: const InputDecoration(labelText: 'الهوية الوطنية')),
              const SizedBox(height: 8),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'المسمى الوظيفي')),
              const SizedBox(height: 8),
              TextField(controller: deptCtrl, decoration: const InputDecoration(labelText: 'القسم / الإدارة')),
              const SizedBox(height: 8),
              TextField(
                controller: salaryCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'الراتب الأساسي (${PrinterService.defaultCurrency})'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final salary = ((double.tryParse(salaryCtrl.text.trim()) ?? 0) * 100).round();
              final companyId = _getCompanyId();
              final branchId = _getBranchId();

              _enterpriseRepo.createEmployee(
                companyId: companyId,
                branchId: branchId,
                employeeCode: codeCtrl.text.trim(),
                fullName: nameCtrl.text.trim(),
                nationalId: nationalIdCtrl.text.trim(),
                jobTitle: titleCtrl.text.trim(),
                department: deptCtrl.text.trim(),
                hireDate: DateTime.now(),
                basicSalary: salary,
                housingAllowance: (salary * 0.25).round(),
                transportAllowance: 50000, // 500 SAR
              );

              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('حفظ الموظف'),
          ),
        ],
      ),
    );
  }

  void _showCreateCostCenterDialog() {
    final codeCtrl = TextEditingController(text: 'CC-${_costCenters.length + 101}');
    final nameArCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مركز تكلفة'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'رمز المركز (Code)')),
              const SizedBox(height: 8),
              TextField(controller: nameArCtrl, decoration: const InputDecoration(labelText: 'الاسم بالعربية')),
              const SizedBox(height: 8),
              TextField(controller: nameEnCtrl, decoration: const InputDecoration(labelText: 'الاسم بالإنجليزية (اختياري)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final companyId = _getCompanyId();
              _enterpriseRepo.createCostCenter(
                companyId: companyId,
                code: codeCtrl.text.trim(),
                nameAr: nameArCtrl.text.trim(),
                nameEn: nameEnCtrl.text.trim().isEmpty ? null : nameEnCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showCreateSampleApprovalDialog() {
    final docCtrl = TextEditingController(text: 'PO-2026-999');
    final amountCtrl = TextEditingController(text: '65000'); // > 10,000 -> 2 levels

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنشاء طلب اعتماد مستند'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'رقم المستند / أمر الشراء')),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'القيمة المالية (${PrinterService.defaultCurrency})'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final amountCents = ((double.tryParse(amountCtrl.text.trim()) ?? 0) * 100).round();
              final companyId = _getCompanyId();
              final userId = _getUserId();

              _enterpriseRepo.submitApprovalRequest(
                companyId: companyId,
                documentType: 'PURCHASE_ORDER',
                documentId: 'po_test_id',
                requestNumber: docCtrl.text.trim(),
                amount: amountCents,
                createdByUserId: userId,
              );

              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('تقديم للاعتماد'),
          ),
        ],
      ),
    );
  }
}
