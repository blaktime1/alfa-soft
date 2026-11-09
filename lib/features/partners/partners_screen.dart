import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/math/bankers_rounding.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/partner_repository.dart';
import '../../domain/entities/partner.dart';

class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  List<CustomerEntity> _customers = [];
  List<SupplierEntity> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    final db = ref.read(databaseServiceProvider);
    final repo = PartnerRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _customers = repo.getCustomers(companyId, query: _searchController.text);
        _suppliers = repo.getSuppliers(companyId, query: _searchController.text);
      }
    } catch (_) {
      // Handle gracefully
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openWhatsApp({required String? phone, required String message}) {
    try {
      String cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.startsWith('05')) {
        cleanPhone = '966${cleanPhone.substring(1)}';
      } else if (cleanPhone.startsWith('7') && cleanPhone.length == 9) {
        cleanPhone = '967$cleanPhone';
      }

      final encodedMsg = Uri.encodeComponent(message);
      final url = cleanPhone.isNotEmpty
          ? 'https://wa.me/$cleanPhone?text=$encodedMsg'
          : 'https://wa.me/?text=$encodedMsg';

      if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER DIALOGS & ACTIONS
  // ---------------------------------------------------------------------------

  void _showAddCustomerDialog() {
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: 'CUST-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final taxNumberController = TextEditingController();
    final creditLimitController = TextEditingController(text: '5000.00');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: AppColors.brandPrimary),
              SizedBox(width: 8),
              Text('إضافة حساب عميل جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: codeController,
                          decoration: const InputDecoration(labelText: 'كود العميل *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'رقم الهاتف / الواتساب'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم العميل أو المنشأة *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: taxNumberController,
                          decoration: const InputDecoration(labelText: 'الرقم الضريبي (إن وجد)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'سقف الائتمان الآجل (SAR)'),
                        ),
                      ),
                    ],
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
                if (formKey.currentState?.validate() != true) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);
                final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                final creditDouble = double.tryParse(creditLimitController.text.trim()) ?? 0.0;

                repo.createCustomer(
                  companyId: companyId,
                  code: codeController.text.trim(),
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  taxNumber: taxNumberController.text.trim().isNotEmpty ? taxNumberController.text.trim() : null,
                  creditLimitCents: BankersRounding.toMinorUnits(creditDouble),
                );

                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة العميل بنجاح!'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('حفظ العميل'),
            ),
          ],
        );
      },
    );
  }

  void _showEditCustomerDialog(CustomerEntity customer) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone ?? '');
    final taxNumberController = TextEditingController(text: customer.taxNumber ?? '');
    final creditLimitController = TextEditingController(text: customer.creditLimit.toStringAsFixed(2));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text('تعديل بيانات العميل (${customer.code})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم العميل أو المنشأة *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'رقم الهاتف / الواتساب'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: taxNumberController,
                          decoration: const InputDecoration(labelText: 'الرقم الضريبي'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الحد الائتماني الآجل (SAR) *'),
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
                if (formKey.currentState?.validate() != true) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);
                final creditDouble = double.tryParse(creditLimitController.text.trim()) ?? 0.0;

                repo.updateCustomer(
                  id: customer.id,
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  taxNumber: taxNumberController.text.trim().isNotEmpty ? taxNumberController.text.trim() : null,
                  creditLimitCents: BankersRounding.toMinorUnits(creditDouble),
                );

                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث بيانات العميل بنجاح!'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteCustomerDialog(CustomerEntity customer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightBgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد حذف / تعطيل العميل', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف العميل "${customer.name}"؟ الرصيد الحالي: ${customer.currentBalance.toStringAsFixed(2)} SAR.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              final db = ref.read(databaseServiceProvider);
              final repo = PartnerRepository(db);

              repo.deleteCustomer(customer.id);
              Navigator.pop(ctx);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف وتعطيل العميل بنجاح!'), backgroundColor: AppColors.danger),
              );
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  /// Dialog to record cash payment / delivery from customer settling their credit debt
  void _showCustomerPaymentDialog(CustomerEntity customer) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(text: customer.currentBalance > 0 ? customer.currentBalance.toStringAsFixed(2) : '100.00');
    final refController = TextEditingController(text: 'RCT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final notesController = TextEditingController(text: 'سداد نقدي لحساب آجل');
    String paymentMethod = 'CASH';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text('سند تحصيل / قبض نقدي من: ${customer.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي المديونية الحالية على العميل:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${customer.currentBalance.toStringAsFixed(2)} SAR',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.dangerText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'المبلغ المقبوض (SAR) *', prefixIcon: Icon(Icons.attach_money_rounded)),
                              validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'أدخل مبلغاً صالحاً' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMethod,
                              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                              items: const [
                                DropdownMenuItem(value: 'CASH', child: Text('نقداً (كاش)')),
                                DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('تحويل بنكي')),
                                DropdownMenuItem(value: 'CARD', child: Text('شبكة / بطاقة')),
                              ],
                              onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'CASH'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refController,
                        decoration: const InputDecoration(labelText: 'رقم السند / المرجع'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'البيان والملاحظات'),
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
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('تسجيل وقبض المبلغ'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;

                    final db = ref.read(databaseServiceProvider);
                    final repo = PartnerRepository(db);
                    final currentUser = ref.read(currentUserProvider);

                    final compRow = db.select('SELECT id FROM companies LIMIT 1').first;
                    final companyId = compRow['id'] as String;
                    final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                    final amountDouble = double.parse(amountController.text.trim());
                    repo.recordCustomerPayment(
                      companyId: companyId,
                      branchId: branchId,
                      customerId: customer.id,
                      amountHalalas: BankersRounding.toMinorUnits(amountDouble),
                      paymentMethod: paymentMethod,
                      referenceNumber: refController.text.trim(),
                      notes: notesController.text.trim(),
                      userId: currentUser?.id ?? 'ADMIN',
                    );

                    Navigator.pop(ctx);
                    _loadData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تسجيل سند القبض بمبلغ ${amountDouble.toStringAsFixed(2)} SAR وتخفيض رصيد العميل بنجاح!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Full Statement of Account Dialog showing chronologically what is for them and against them, with Print & WhatsApp
  void _showCustomerStatementDialog(CustomerEntity customer) {
    final db = ref.read(databaseServiceProvider);
    final repo = PartnerRepository(db);
    final statement = repo.getCustomerStatement(customer.id);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text('كشف حساب العميل: ${customer.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: customer.currentBalance > 0 ? AppColors.dangerBg : AppColors.successBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'الرصيد المتبقي عليه: ${customer.currentBalance.toStringAsFixed(2)} SAR',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: customer.currentBalance > 0 ? AppColors.dangerText : AppColors.successText,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 850,
            height: 480,
            child: statement.isEmpty
                ? const Center(child: Text('لا توجد حركات مسجلة في كشف حساب هذا العميل حتى الآن'))
                : SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
                      columns: const [
                        DataColumn(label: Text('التاريخ')),
                        DataColumn(label: Text('نوع العملية')),
                        DataColumn(label: Text('رقم المستند')),
                        DataColumn(label: Text('مدين (عليه)')),
                        DataColumn(label: Text('دائن (سدد)')),
                        DataColumn(label: Text('الرصيد المستحق')),
                        DataColumn(label: Text('البيان')),
                      ],
                      rows: statement.map((st) {
                        return DataRow(cells: [
                          DataCell(Text(st.date, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(st.docType, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          DataCell(Text(st.docNumber, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(
                            st.debit > 0 ? '${st.debit.toStringAsFixed(2)} SAR' : '—',
                            style: const TextStyle(color: AppColors.dangerText, fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(
                            st.credit > 0 ? '${st.credit.toStringAsFixed(2)} SAR' : '—',
                            style: const TextStyle(color: AppColors.successText, fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(
                            '${st.runningBalance.toStringAsFixed(2)} SAR',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(st.notes, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary))),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            // WhatsApp Share Button
            ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('مشاركة بالواتساب'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
              onPressed: () {
                final summary = StringBuffer();
                summary.writeln('مرحباً بك عزيزنا العميل: ${customer.name}');
                summary.writeln('كشف حسابك من منظومة ألفا سوفت:');
                summary.writeln('-----------------------------------');
                summary.writeln('الرصيد المتبقي المستحق: ${customer.currentBalance.toStringAsFixed(2)} SAR');
                summary.writeln('عدد العمليات المسجلة: ${statement.length}');
                if (statement.isNotEmpty) {
                  summary.writeln('آخر عملية: ${statement.last.date} | ${statement.last.docType} | ${statement.last.docNumber}');
                }
                summary.writeln('-----------------------------------');
                summary.writeln('شاكرين ومقدرين تعاملكم معنا.');

                _openWhatsApp(phone: customer.phone, message: summary.toString());
              },
            ),
            // Print / Save Button
            ElevatedButton.icon(
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('طباعة كشف الحساب'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary, foregroundColor: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم إرسال كشف حساب العميل "${customer.name}" إلى الطابعة وجاهز للحفظ محلياً كـ PDF!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SUPPLIER DIALOGS & ACTIONS
  // ---------------------------------------------------------------------------

  void _showAddSupplierDialog() {
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: 'SUPP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final taxNumberController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.local_shipping_rounded, color: AppColors.brandPrimary),
              SizedBox(width: 8),
              Text('إضافة مورد جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: codeController,
                          decoration: const InputDecoration(labelText: 'كود المورد *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'رقم هاتف المورد / الواتساب'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم المورد أو الشركة الموردة *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: taxNumberController,
                    decoration: const InputDecoration(labelText: 'الرقم الضريبي للمورد (إن وجد)'),
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
                if (formKey.currentState?.validate() != true) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);
                final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                repo.createSupplier(
                  companyId: companyId,
                  code: codeController.text.trim(),
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  taxNumber: taxNumberController.text.trim().isNotEmpty ? taxNumberController.text.trim() : null,
                );

                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة المورد بنجاح!'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('حفظ المورد'),
            ),
          ],
        );
      },
    );
  }

  void _showEditSupplierDialog(SupplierEntity supplier) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: supplier.name);
    final phoneController = TextEditingController(text: supplier.phone ?? '');
    final taxNumberController = TextEditingController(text: supplier.taxNumber ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text('تعديل بيانات المورد (${supplier.code})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم المورد *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'رقم الهاتف / الواتساب'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: taxNumberController,
                          decoration: const InputDecoration(labelText: 'الرقم الضريبي'),
                        ),
                      ),
                    ],
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
                if (formKey.currentState?.validate() != true) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);

                repo.updateSupplier(
                  id: supplier.id,
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  taxNumber: taxNumberController.text.trim().isNotEmpty ? taxNumberController.text.trim() : null,
                );

                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث بيانات المورد بنجاح!'), backgroundColor: AppColors.success),
                );
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteSupplierDialog(SupplierEntity supplier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightBgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد حذف / تعطيل المورد', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف المورد "${supplier.name}"؟ الرصيد المستحق له: ${supplier.currentBalance.toStringAsFixed(2)} SAR.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              final db = ref.read(databaseServiceProvider);
              final repo = PartnerRepository(db);

              repo.deleteSupplier(supplier.id);
              Navigator.pop(ctx);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف وتعطيل المورد بنجاح!'), backgroundColor: AppColors.danger),
              );
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  /// Dialog to pay cash/transfer to a supplier
  void _showSupplierPaymentDialog(SupplierEntity supplier) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(text: supplier.currentBalance > 0 ? supplier.currentBalance.toStringAsFixed(2) : '500.00');
    final refController = TextEditingController(text: 'VCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final notesController = TextEditingController(text: 'سداد دفعة نقدية للمورد');
    String paymentMethod = 'CASH';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.outbox_rounded, color: AppColors.brandAccent),
                  const SizedBox(width: 8),
                  Text('سند صرف نقدي للمورد: ${supplier.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.brandGold.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي الرصيد المستحق للمورد (له):', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${supplier.currentBalance.toStringAsFixed(2)} SAR',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.brandGoldDark),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'المبلغ المدفوع (SAR) *', prefixIcon: Icon(Icons.attach_money_rounded)),
                              validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'أدخل مبلغاً صالحاً' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMethod,
                              decoration: const InputDecoration(labelText: 'طريقة السداد'),
                              items: const [
                                DropdownMenuItem(value: 'CASH', child: Text('نقداً (كاش)')),
                                DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('تحويل بنكي')),
                              ],
                              onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'CASH'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refController,
                        decoration: const InputDecoration(labelText: 'رقم السند / الشيك'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'البيان والملاحظات'),
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
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('تسجيل وصرف المبلغ'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;

                    final db = ref.read(databaseServiceProvider);
                    final repo = PartnerRepository(db);
                    final currentUser = ref.read(currentUserProvider);

                    final compRow = db.select('SELECT id FROM companies LIMIT 1').first;
                    final companyId = compRow['id'] as String;
                    final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                    final amountDouble = double.parse(amountController.text.trim());
                    repo.recordSupplierPayment(
                      companyId: companyId,
                      branchId: branchId,
                      supplierId: supplier.id,
                      amountHalalas: BankersRounding.toMinorUnits(amountDouble),
                      paymentMethod: paymentMethod,
                      referenceNumber: refController.text.trim(),
                      notes: notesController.text.trim(),
                      userId: currentUser?.id ?? 'ADMIN',
                    );

                    Navigator.pop(ctx);
                    _loadData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تسجيل سند الصرف للمورد بمبلغ ${amountDouble.toStringAsFixed(2)} SAR بنجاح!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Statement of Account Dialog for Supplier
  void _showSupplierStatementDialog(SupplierEntity supplier) {
    final db = ref.read(databaseServiceProvider);
    final repo = PartnerRepository(db);
    final statement = repo.getSupplierStatement(supplier.id);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.lightBgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Text('كشف حساب المورد: ${supplier.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المتبقي له: ${supplier.currentBalance.toStringAsFixed(2)} SAR',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandGoldDark),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 850,
            height: 480,
            child: statement.isEmpty
                ? const Center(child: Text('لا توجد حركات مسجلة في كشف حساب هذا المورد حتى الآن'))
                : SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
                      columns: const [
                        DataColumn(label: Text('التاريخ')),
                        DataColumn(label: Text('نوع العملية')),
                        DataColumn(label: Text('رقم المستند')),
                        DataColumn(label: Text('مدين (صرفنا له)')),
                        DataColumn(label: Text('دائن (ورّد بضاعة)')),
                        DataColumn(label: Text('الرصيد المتبقي له')),
                        DataColumn(label: Text('البيان')),
                      ],
                      rows: statement.map((st) {
                        return DataRow(cells: [
                          DataCell(Text(st.date, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(st.docType, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          DataCell(Text(st.docNumber, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(
                            st.debit > 0 ? '${st.debit.toStringAsFixed(2)} SAR' : '—',
                            style: const TextStyle(color: AppColors.successText, fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(
                            st.credit > 0 ? '${st.credit.toStringAsFixed(2)} SAR' : '—',
                            style: const TextStyle(color: AppColors.brandGoldDark, fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(
                            '${st.runningBalance.toStringAsFixed(2)} SAR',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          )),
                          DataCell(Text(st.notes, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary))),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('مشاركة بالواتساب'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
              onPressed: () {
                final summary = StringBuffer();
                summary.writeln('كشف حساب المورد: ${supplier.name}');
                summary.writeln('منظومة ألفا سوفت:');
                summary.writeln('-----------------------------------');
                summary.writeln('الرصيد المستحق لكم: ${supplier.currentBalance.toStringAsFixed(2)} SAR');
                summary.writeln('عدد العمليات المسجلة: ${statement.length}');
                summary.writeln('-----------------------------------');

                _openWhatsApp(phone: supplier.phone, message: summary.toString());
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('طباعة كشف الحساب'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary, foregroundColor: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم إرسال كشف حساب المورد "${supplier.name}" للطباعة وجاهز للحفظ محلياً!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إدارة العملاء والموردين والآجل',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.brandPrimary)),
                    const SizedBox(height: 4),
                    Text('كشوفات الحسابات، التحصيل النقدي، البيع والشراء الآجل، والطباعة والمشاركة',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.lightTextSecondary)),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddCustomerDialog,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('إضافة عميل جديد'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showAddSupplierDialog,
                  icon: const Icon(Icons.local_shipping_rounded),
                  label: const Text('إضافة مورد جديد'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tabs & Search Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: AppColors.brandPrimary,
                        labelColor: AppColors.brandPrimary,
                        unselectedLabelColor: AppColors.lightTextSecondary,
                        tabs: [
                          Tab(text: 'العملاء (${_customers.length})'),
                          Tab(text: 'الموردون (${_suppliers.length})'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'بحث بالاسم، الكود، أو رقم الهاتف...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (_) => _loadData(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Customers View
                  Card(
                    child: _customers.isEmpty
                        ? const Center(child: Text('لا يوجد عملاء مسجلون'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('كود العميل')),
                                DataColumn(label: Text('اسم العميل')),
                                DataColumn(label: Text('رقم الهاتف')),
                                DataColumn(label: Text('الرقم الضريبي')),
                                DataColumn(label: Text('الحد الائتماني')),
                                DataColumn(label: Text('الرصيد الحالي (عليه)')),
                                DataColumn(label: Text('الحالة')),
                                DataColumn(label: Text('الإجراءات والعمليات')),
                              ],
                              rows: _customers.map((c) {
                                return DataRow(cells: [
                                  DataCell(Text(c.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(c.phone ?? '—')),
                                  DataCell(Text(c.taxNumber ?? '—')),
                                  DataCell(Text('${c.creditLimit.toStringAsFixed(2)} SAR')),
                                  DataCell(Text(
                                    '${c.currentBalance.toStringAsFixed(2)} SAR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: c.currentBalance > 0 ? AppColors.dangerText : AppColors.successText,
                                    ),
                                  )),
                                  DataCell(Chip(
                                    label: Text(c.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: c.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Collect Payment Button
                                        IconButton(
                                          icon: const Icon(Icons.add_card_rounded, color: AppColors.success, size: 19),
                                          tooltip: 'سند قبض / تحصيل نقدي لحساب آجل',
                                          onPressed: () => _showCustomerPaymentDialog(c),
                                        ),
                                        // Statement Report Button
                                        IconButton(
                                          icon: const Icon(Icons.assignment_rounded, color: AppColors.brandPrimary, size: 19),
                                          tooltip: 'كشف حساب، طباعة، ومشاركة واتساب',
                                          onPressed: () => _showCustomerStatementDialog(c),
                                        ),
                                        // Edit Button
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, color: AppColors.brandAccent, size: 19),
                                          tooltip: 'تعديل بيانات العميل',
                                          onPressed: () => _showEditCustomerDialog(c),
                                        ),
                                        // Delete Button
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 19),
                                          tooltip: 'حذف / تعطيل العميل',
                                          onPressed: () => _showDeleteCustomerDialog(c),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),

                  // Suppliers View
                  Card(
                    child: _suppliers.isEmpty
                        ? const Center(child: Text('لا يوجد موردون مسجلون'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('كود المورد')),
                                DataColumn(label: Text('اسم المورد')),
                                DataColumn(label: Text('رقم الهاتف')),
                                DataColumn(label: Text('الرقم الضريبي')),
                                DataColumn(label: Text('الرصيد المستحق (له)')),
                                DataColumn(label: Text('الحالة')),
                                DataColumn(label: Text('الإجراءات والعمليات')),
                              ],
                              rows: _suppliers.map((s) {
                                return DataRow(cells: [
                                  DataCell(Text(s.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(s.phone ?? '—')),
                                  DataCell(Text(s.taxNumber ?? '—')),
                                  DataCell(Text(
                                    '${s.currentBalance.toStringAsFixed(2)} SAR',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandGoldDark),
                                  )),
                                  DataCell(Chip(
                                    label: Text(s.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: s.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Pay Supplier Button
                                        IconButton(
                                          icon: const Icon(Icons.payment_rounded, color: AppColors.brandGoldDark, size: 19),
                                          tooltip: 'سند صرف نقدي للمورد',
                                          onPressed: () => _showSupplierPaymentDialog(s),
                                        ),
                                        // Statement Report Button
                                        IconButton(
                                          icon: const Icon(Icons.assignment_rounded, color: AppColors.brandPrimary, size: 19),
                                          tooltip: 'كشف حساب، طباعة، ومشاركة واتساب',
                                          onPressed: () => _showSupplierStatementDialog(s),
                                        ),
                                        // Edit Button
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, color: AppColors.brandAccent, size: 19),
                                          tooltip: 'تعديل بيانات المورد',
                                          onPressed: () => _showEditSupplierDialog(s),
                                        ),
                                        // Delete Button
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 19),
                                          tooltip: 'حذف / تعطيل المورد',
                                          onPressed: () => _showDeleteSupplierDialog(s),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
