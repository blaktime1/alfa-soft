import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
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
          title: const Text('إضافة حساب عميل جديد', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          decoration: const InputDecoration(labelText: 'رقم الهاتف'),
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
                          decoration: const InputDecoration(labelText: 'الرقم الضريبي (اختياري)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'الحد الائتماني (SAR)'),
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
                if (!formKey.currentState!.validate()) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);
                final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                final limitCents = ((double.tryParse(creditLimitController.text) ?? 0.0) * 100).round();

                repo.createCustomer(
                  companyId: companyId,
                  code: codeController.text.trim(),
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                  taxNumber: taxNumberController.text.trim().isEmpty ? null : taxNumberController.text.trim(),
                  creditLimitCents: limitCents,
                );

                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('حفظ العميل'),
            ),
          ],
        );
      },
    );
  }

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
          title: const Text('إضافة حساب مورد جديد', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'اسم المورد أو الشركة *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: taxNumberController,
                    decoration: const InputDecoration(labelText: 'الرقم الضريبي للمورد (اختياري)'),
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
                if (!formKey.currentState!.validate()) return;

                final db = ref.read(databaseServiceProvider);
                final repo = PartnerRepository(db);
                final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                repo.createSupplier(
                  companyId: companyId,
                  code: codeController.text.trim(),
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                  taxNumber: taxNumberController.text.trim().isEmpty ? null : taxNumberController.text.trim(),
                );

                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('حفظ المورد'),
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إدارة العملاء والموردين',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('سجلات العملاء، الحسابات المدينة والدائنة، والحدود الائتمانية',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _showAddCustomerDialog();
                    } else {
                      _showAddSupplierDialog();
                    }
                  },
                  icon: const Icon(Icons.person_add_rounded),
                  label: Text(_tabController.index == 0 ? 'إضافة عميل جديد' : 'إضافة مورد جديد'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tab Navigation & Search Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: TabBar(
                        controller: _tabController,
                        onTap: (_) => setState(() {}),
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
                                DataColumn(label: Text('الرصيد الحالي')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _customers.map((c) {
                                return DataRow(cells: [
                                  DataCell(Text(c.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(c.name)),
                                  DataCell(Text(c.phone ?? '—')),
                                  DataCell(Text(c.taxNumber ?? '—')),
                                  DataCell(Text('${c.creditLimit.toStringAsFixed(2)} SAR')),
                                  DataCell(Text(
                                    '${c.currentBalance.toStringAsFixed(2)} SAR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: c.currentBalance > 0 ? AppColors.danger : AppColors.success,
                                    ),
                                  )),
                                  DataCell(Chip(
                                    label: Text(c.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: c.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
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
                                DataColumn(label: Text('الرصيد الدائن المستحق')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _suppliers.map((s) {
                                return DataRow(cells: [
                                  DataCell(Text(s.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(s.name)),
                                  DataCell(Text(s.phone ?? '—')),
                                  DataCell(Text(s.taxNumber ?? '—')),
                                  DataCell(Text(
                                    '${s.currentBalance.toStringAsFixed(2)} SAR',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  )),
                                  DataCell(Chip(
                                    label: Text(s.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: s.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
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
