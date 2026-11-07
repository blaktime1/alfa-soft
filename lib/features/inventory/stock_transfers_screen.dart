import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/inventory_operation_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/entities/inventory_operation.dart';
import '../../domain/entities/organization.dart';
import '../../domain/entities/catalog.dart';

class StockTransfersScreen extends ConsumerStatefulWidget {
  const StockTransfersScreen({super.key});

  @override
  ConsumerState<StockTransfersScreen> createState() => _StockTransfersScreenState();
}

class _StockTransfersScreenState extends ConsumerState<StockTransfersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<StockTransferEntity> _transfers = [];
  List<WarehouseEntity> _warehouses = [];
  List<ProductEntity> _products = [];
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
    final invRepo = InventoryOperationRepository(db);
    final orgRepo = OrganizationRepository(db);
    final catalogRepo = CatalogRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _transfers = invRepo.getTransfers(companyId);
        _products = catalogRepo.getProducts(companyId: companyId);

        final branches = orgRepo.getBranches(companyId);
        _warehouses = [];
        for (final b in branches) {
          _warehouses.addAll(orgRepo.getWarehouses(b.id));
        }
      }
    } catch (_) {
      // Handle gracefully
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showNewTransferDialog() {
    if (_warehouses.length < 2 || _products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يلزم توفر مستودعين وصنف واحد على الأقل للتحويل المخزني')),
      );
      return;
    }

    final transferNumber = 'TR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    String fromWhId = _warehouses.first.id;
    String toWhId = _warehouses[1].id;
    String productId = _products.first.id;
    final qtyController = TextEditingController(text: '5');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تحويل مخزني بين المستودعات', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('رقم التحويل: $transferNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: fromWhId,
                            decoration: const InputDecoration(labelText: 'من مستودع (المصدر) *'),
                            items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                            onChanged: (v) => setDialogState(() => fromWhId = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: toWhId,
                            decoration: const InputDecoration(labelText: 'إلى مستودع (الوجهة) *'),
                            items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                            onChanged: (v) => setDialogState(() => toWhId = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'الصنف المحول *'),
                      items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr))).toList(),
                      onChanged: (v) => setDialogState(() => productId = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'الكمية المحولة *'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(qtyController.text) ?? 1;
                    final db = ref.read(databaseServiceProvider);
                    final repo = InventoryOperationRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final prod = _products.firstWhere((p) => p.id == productId);

                    try {
                      repo.transferStock(
                        companyId: companyId,
                        fromWarehouseId: fromWhId,
                        toWarehouseId: toWhId,
                        userId: userId,
                        transferNumber: transferNumber,
                        items: [
                          {
                            'productId': productId,
                            'quantity': qty,
                            'unitCostCents': prod.costPriceCents,
                          }
                        ],
                      );
                      Navigator.pop(ctx);
                      _loadData();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                    }
                  },
                  child: const Text('تأكيد التحويل المخزني'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNewAdjustmentDialog() {
    if (_warehouses.isEmpty || _products.isEmpty) return;

    String warehouseId = _warehouses.first.id;
    String productId = _products.first.id;
    String adjustmentType = 'SURPLUS';
    final qtyController = TextEditingController(text: '1');
    final reasonController = TextEditingController(text: 'تسوية جرد دورية');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تسوية جردية للمخزون (Adjust Stock)', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: warehouseId,
                            decoration: const InputDecoration(labelText: 'المستودع *'),
                            items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                            onChanged: (v) => setDialogState(() => warehouseId = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: adjustmentType,
                            decoration: const InputDecoration(labelText: 'نوع التسوية *'),
                            items: const [
                              DropdownMenuItem(value: 'SURPLUS', child: Text('فائض مخزني (+)')),
                              DropdownMenuItem(value: 'DEFICIT', child: Text('عجز مخزني (-)')),
                              DropdownMenuItem(value: 'DAMAGED', child: Text('تالف / منتهي الصلاحية (-)')),
                            ],
                            onChanged: (v) => setDialogState(() => adjustmentType = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'الصنف *'),
                      items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr))).toList(),
                      onChanged: (v) => setDialogState(() => productId = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'الكمية *'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      decoration: const InputDecoration(labelText: 'سبب التسوية *'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(qtyController.text) ?? 1;
                    final db = ref.read(databaseServiceProvider);
                    final repo = InventoryOperationRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final prod = _products.firstWhere((p) => p.id == productId);

                    repo.adjustStock(
                      companyId: companyId,
                      warehouseId: warehouseId,
                      productId: productId,
                      userId: userId,
                      adjustmentType: adjustmentType,
                      quantity: qty,
                      unitCostCents: prod.costPriceCents,
                      reason: reasonController.text.trim(),
                    );

                    Navigator.pop(ctx);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تسجيل التسوية الجردية وتحديث بطاقة الصنف')),
                    );
                  },
                  child: const Text('اعتماد التسوية'),
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
                      Text('التحويلات المخزنية والتسويات',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('إدارة حركة البضائع بين المستودعات وتسويات الجرد الفعلي والعجز والفائض',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _showNewTransferDialog();
                    } else {
                      _showNewAdjustmentDialog();
                    }
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(_tabController.index == 0 ? 'تحويل مخزني جديد' : 'تسوية جرد جديدة'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tab Navigation Bar
            Card(
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                tabs: [
                  Tab(text: 'التحويلات بين الفروع (${_transfers.length})'),
                  const Tab(text: 'تسويات الجرد الفعلي'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Transfers View
                  Card(
                    child: _transfers.isEmpty
                        ? const Center(child: Text('لا توجد تحويلات مخزنية مسجلة'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('رقم التحويل')),
                                DataColumn(label: Text('من مستودع')),
                                DataColumn(label: Text('إلى مستودع')),
                                DataColumn(label: Text('تاريخ التحويل')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _transfers.map((tr) {
                                final fromWh = _warehouses.firstWhere((w) => w.id == tr.fromWarehouseId, orElse: () => _warehouses.first);
                                final toWh = _warehouses.firstWhere((w) => w.id == tr.toWarehouseId, orElse: () => _warehouses.first);

                                return DataRow(cells: [
                                  DataCell(Text(tr.transferNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(fromWh.name)),
                                  DataCell(Text(toWh.name)),
                                  DataCell(Text('${tr.transferDate.year}-${tr.transferDate.month.toString().padLeft(2, '0')}-${tr.transferDate.day.toString().padLeft(2, '0')}')),
                                  DataCell(Chip(
                                    label: const Text('مكتمل وناجز', style: TextStyle(fontSize: 11)),
                                    backgroundColor: AppColors.success.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),

                  // Adjustments Tab Info
                  Card(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.rule_rounded, size: 56, color: AppColors.brandAccent),
                          const SizedBox(height: 16),
                          const Text('تسويات الجرد الفعلية مرتبطة بأستاذ المخزون العام',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text('اضغط على "تسوية جرد جديدة" لتسجيل الفروقات الناتجة عن الجرد الفعلي'),
                        ],
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
