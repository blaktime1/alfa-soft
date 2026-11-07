import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/partner_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/partner.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/organization.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PurchaseOrderEntity> _orders = [];
  List<SupplierEntity> _suppliers = [];
  List<ProductEntity> _products = [];
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
    final purchaseRepo = PurchaseRepository(db);
    final partnerRepo = PartnerRepository(db);
    final catalogRepo = CatalogRepository(db);
    final orgRepo = OrganizationRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _orders = purchaseRepo.getPurchaseOrders(companyId);
        _suppliers = partnerRepo.getSuppliers(companyId);
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

  void _showCreateOrderDialog() {
    if (_suppliers.isEmpty || _products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل مورد وصنف واحد على الأقل أولاً')),
      );
      return;
    }

    final orderNumber = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    String supplierId = _suppliers.first.id;
    String productId = _products.first.id;
    final qtyController = TextEditingController(text: '10');
    final costController = TextEditingController(text: _products.first.costPrice.toStringAsFixed(2));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إنشاء أمر شراء جديد (PO)', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('رقم الأمر: $orderNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: supplierId,
                      decoration: const InputDecoration(labelText: 'المورد *'),
                      items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                      onChanged: (v) => setDialogState(() => supplierId = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'الصنف المطلوب *'),
                      items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr))).toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          productId = v!;
                          final sel = _products.firstWhere((p) => p.id == v);
                          costController.text = sel.costPrice.toStringAsFixed(2);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'الكمية *'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'تكلفة الوحدة (SAR) *'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(qtyController.text) ?? 1;
                    final costCents = ((double.tryParse(costController.text) ?? 0.0) * 100).round();

                    final db = ref.read(databaseServiceProvider);
                    final repo = PurchaseRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final unitId = _products.firstWhere((p) => p.id == productId).baseUnitId;

                    repo.createPurchaseOrder(
                      companyId: companyId,
                      branchId: branchId,
                      supplierId: supplierId,
                      userId: userId,
                      orderNumber: orderNumber,
                      items: [
                        {
                          'productId': productId,
                          'unitId': unitId,
                          'quantity': qty,
                          'unitCostCents': costCents,
                        }
                      ],
                    );

                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('حفظ أمر الشراء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReceiveGoodsDialog(PurchaseOrderEntity po) {
    if (_warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إنشاء مستودع واحد على الأقل أولاً')),
      );
      return;
    }

    final receiptNumber = 'GRN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    String warehouseId = _warehouses.first.id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('استلام بضاعة مخزنياً (GRN)', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('أمر الشراء: ${po.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('إذن الاستلام: $receiptNumber'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: warehouseId,
                      decoration: const InputDecoration(labelText: 'مستودع الاستلام الفعلي *'),
                      items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                      onChanged: (v) => setDialogState(() => warehouseId = v!),
                    ),
                    const SizedBox(height: 16),
                    const Text('الأصناف المستلمة (سيتم رفع أرصدة المخزون وحساب متوسط التكلفة):'),
                    const SizedBox(height: 8),
                    ...po.items.map((i) {
                      final prod = _products.firstWhere((p) => p.id == i.productId, orElse: () => _products.first);
                      return ListTile(
                        dense: true,
                        title: Text(prod.nameAr),
                        subtitle: Text('الكمية: ${i.quantity} | تكلفة الوحدة: ${i.unitCost.toStringAsFixed(2)} SAR'),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                ElevatedButton.icon(
                  icon: const Icon(Icons.inventory_rounded),
                  label: const Text('تأكيد الاستلام الفعلي ورفع المخزون'),
                  onPressed: () {
                    final db = ref.read(databaseServiceProvider);
                    final repo = PurchaseRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                    repo.receiveGoods(
                      companyId: companyId,
                      branchId: po.branchId,
                      warehouseId: warehouseId,
                      supplierId: po.supplierId,
                      userId: userId,
                      purchaseOrderId: po.id,
                      receiptNumber: receiptNumber,
                      receivedItems: po.items.map((i) => {
                        'productId': i.productId,
                        'quantity': i.quantity,
                        'unitCostCents': i.unitCostCents,
                      }).toList(),
                    );

                    Navigator.pop(ctx);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم استلام البضاعة وتحديث أرصدة المخزون برقم: $receiptNumber')),
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
                      Text('إدارة المشتريات والتوريد',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('أوامر الشراء، أذون الاستلام الفعلي (GRN)، واحتساب التكلفة المرجحة',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showCreateOrderDialog,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('أمر شراء جديد (PO)'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Orders Table
            Expanded(
              child: Card(
                child: _orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_bag_outlined,
                                size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text('لا توجد أوامر شراء مسجلة',
                                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('رقم الأمر')),
                            DataColumn(label: Text('المورد')),
                            DataColumn(label: Text('تاريخ الأمر')),
                            DataColumn(label: Text('المجموع الكلي')),
                            DataColumn(label: Text('الحالة')),
                            DataColumn(label: Text('الإجراء')),
                          ],
                          rows: _orders.map((po) {
                            final supplier = _suppliers.firstWhere(
                              (s) => s.id == po.supplierId,
                              orElse: () => SupplierEntity(id: '', companyId: '', code: '', name: 'مورد غير مسجل'),
                            );
                            final isReceived = po.status == 'RECEIVED';

                            return DataRow(cells: [
                              DataCell(Text(po.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(supplier.name)),
                              DataCell(Text('${po.orderDate.year}-${po.orderDate.month.toString().padLeft(2, '0')}-${po.orderDate.day.toString().padLeft(2, '0')}')),
                              DataCell(Text('${po.grandTotal.toStringAsFixed(2)} SAR',
                                  style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Chip(
                                label: Text(isReceived ? 'تم الاستلام' : 'معلق / بانتظار التوريد',
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor: isReceived
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.warning.withValues(alpha: 0.15),
                                side: BorderSide.none,
                              )),
                              DataCell(
                                isReceived
                                    ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                                    : ElevatedButton.icon(
                                        icon: const Icon(Icons.download_rounded, size: 16),
                                        label: const Text('استلام بضاعة (GRN)'),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          backgroundColor: AppColors.brandAccent,
                                        ),
                                        onPressed: () => _showReceiveGoodsDialog(po),
                                      ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
