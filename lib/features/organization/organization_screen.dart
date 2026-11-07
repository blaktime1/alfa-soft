import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/organization_repository.dart';
import '../../domain/entities/organization.dart';

class OrganizationScreen extends ConsumerStatefulWidget {
  const OrganizationScreen({super.key});

  @override
  ConsumerState<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends ConsumerState<OrganizationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CompanyEntity? _company;
  List<BranchEntity> _branches = [];
  List<WarehouseEntity> _warehouses = [];
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
    super.dispose();
  }

  void _loadData() {
    final db = ref.read(databaseServiceProvider);
    final repo = OrganizationRepository(db);

    try {
      _company = repo.getPrimaryCompany();
      if (_company != null) {
        _branches = repo.getBranches(_company!.id);
        _warehouses = [];
        for (final branch in _branches) {
          _warehouses.addAll(repo.getWarehouses(branch.id));
        }
      }
    } catch (_) {
      // Handle gracefully
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBranchDialog() {
    if (_company == null) return;
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: 'BR0${_branches.length + 1}');
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    bool isMain = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إضافة فرع جديد', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
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
                              decoration: const InputDecoration(labelText: 'رمز الفرع *'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: phoneController,
                              decoration: const InputDecoration(labelText: 'رقم هاتف الفرع'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'اسم الفرع *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: 'العنوان الجغرافي'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('تعيين كفرع رئيسي للمنظومة'),
                        value: isMain,
                        onChanged: (v) => setDialogState(() => isMain = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final db = ref.read(databaseServiceProvider);
                    final repo = OrganizationRepository(db);

                    repo.createBranch(
                      companyId: _company!.id,
                      code: codeController.text.trim(),
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                      address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                      isMain: isMain,
                    );

                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('حفظ الفرع'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddWarehouseDialog() {
    if (_branches.isEmpty) return;
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: 'WH0${_warehouses.length + 1}');
    final nameController = TextEditingController();
    String branchId = _branches.first.id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إضافة مستودع جديد', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: branchId,
                        decoration: const InputDecoration(labelText: 'الفرع التابع له *'),
                        items: _branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => branchId = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: codeController,
                        decoration: const InputDecoration(labelText: 'رمز المستودع *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'اسم المستودع *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final db = ref.read(databaseServiceProvider);
                    final repo = OrganizationRepository(db);

                    repo.createWarehouse(
                      branchId: branchId,
                      code: codeController.text.trim(),
                      name: nameController.text.trim(),
                    );

                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('حفظ المستودع'),
                ),
              ],
            );
          },
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
                      Text('الهيكل التنظيمي والفروع',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('إدارة بيانات الشركة، الفروع المتعددة، ومستودعات التخزين والتوزيع',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _showAddBranchDialog();
                    } else {
                      _showAddWarehouseDialog();
                    }
                  },
                  icon: const Icon(Icons.add_business_rounded),
                  label: Text(_tabController.index == 0 ? 'إضافة فرع جديد' : 'إضافة مستودع جديد'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Company Profile Header Card
            if (_company != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.corporate_fare_rounded, color: AppColors.brandAccent, size: 36),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_company!.tradeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text('الاسم القانوني: ${_company!.legalName} | العملة الأساسية: ${_company!.currency.code} (${_company!.currency.nameAr})'),
                            Text('الرقم الضريبي: ${_company!.taxNumber ?? 'غير مسجل'}'),
                          ],
                        ),
                      ),
                      Chip(
                        label: const Text('المنشأة نشطة ومسجلة'),
                        backgroundColor: AppColors.success.withValues(alpha: 0.15),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Tabs Header
            Card(
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                tabs: [
                  Tab(text: 'الفروع التشغيلية (${_branches.length})'),
                  Tab(text: 'المستودعات ومخازن التوزيع (${_warehouses.length})'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Branches Table
                  Card(
                    child: _branches.isEmpty
                        ? const Center(child: Text('لا توجد فروع مسجلة'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('رمز الفرع')),
                                DataColumn(label: Text('اسم الفرع')),
                                DataColumn(label: Text('الهاتف')),
                                DataColumn(label: Text('العنوان')),
                                DataColumn(label: Text('الرئيسي')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _branches.map((b) {
                                return DataRow(cells: [
                                  DataCell(Text(b.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(b.name)),
                                  DataCell(Text(b.phone ?? '—')),
                                  DataCell(Text(b.address ?? '—')),
                                  DataCell(b.isMain
                                      ? const Chip(
                                          label: Text('الفرع الرئيسي', style: TextStyle(fontSize: 11)),
                                          backgroundColor: AppColors.brandAccent,
                                          labelStyle: TextStyle(color: Colors.white),
                                        )
                                      : const Text('فرعي')),
                                  DataCell(Chip(
                                    label: Text(b.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: b.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),

                  // Warehouses Table
                  Card(
                    child: _warehouses.isEmpty
                        ? const Center(child: Text('لا توجد مستودعات مسجلة'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('رمز المستودع')),
                                DataColumn(label: Text('اسم المستودع')),
                                DataColumn(label: Text('الفرع التابع له')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _warehouses.map((w) {
                                final branch = _branches.firstWhere((b) => b.id == w.branchId, orElse: () => _branches.first);
                                return DataRow(cells: [
                                  DataCell(Text(w.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(w.name)),
                                  DataCell(Text(branch.name)),
                                  DataCell(Chip(
                                    label: Text(w.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: w.isActive
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
