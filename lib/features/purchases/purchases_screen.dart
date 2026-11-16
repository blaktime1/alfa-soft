import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/printing/printer_service.dart';
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
  List<Map<String, dynamic>> _grnNotes = [];
  List<SupplierEntity> _suppliers = [];
  List<ProductEntity> _products = [];
  List<WarehouseEntity> _warehouses = [];
  bool _isLoading = true;
  String _orderStatusFilter = 'ALL';
  String? _selectedSupplierFilter;
  final _searchController = TextEditingController();

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
    final purchaseRepo = PurchaseRepository(db);
    final partnerRepo = PartnerRepository(db);
    final catalogRepo = CatalogRepository(db);
    final orgRepo = OrganizationRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _orders = purchaseRepo.getPurchaseOrders(companyId);
        _grnNotes = purchaseRepo.getGoodsReceiptNotes(companyId);
        _suppliers = partnerRepo.getSuppliers(companyId);
        if (_suppliers.isEmpty) {
          partnerRepo.createSupplier(
            companyId: companyId,
            code: 'CASH_SUPP',
            name: 'مورد نقدي عام',
          );
          _suppliers = partnerRepo.getSuppliers(companyId);
        }
        _products = catalogRepo.getProducts(companyId: companyId);

        final branches = orgRepo.getBranches(companyId);
        _warehouses = [];
        for (final b in branches) {
          _warehouses.addAll(orgRepo.getWarehouses(b.id));
        }
        if (_warehouses.isEmpty) {
          try {
            final allWh = db.select('SELECT id, branch_id, code, name, is_active FROM warehouses WHERE is_active = 1');
            if (allWh.isNotEmpty) {
              _warehouses = allWh.map((r) => WarehouseEntity.fromMap(Map<String, dynamic>.from(r))).toList();
            } else {
              final defBranch = branches.isNotEmpty ? branches.first.id : 'br_default';
              final createdWh = orgRepo.createWarehouse(
                branchId: defBranch,
                code: 'WH-01',
                name: 'المستودع الرئيسي',
              );
              _warehouses = [createdWh];
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error loading purchases data: $e');
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

    final db = ref.read(databaseServiceProvider);
    final ps = PrinterService(db);
    final isTaxEnabled = ps.isTaxEnabled();
    final taxRate = isTaxEnabled ? ps.getTaxRatePercent() : 0.0;

    final orderNumber = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    String supplierId = _suppliers.first.id;
    final notesController = TextEditingController();

    final items = <_PurchaseItemRow>[
      _PurchaseItemRow(
        productId: _products.first.id,
        quantity: 10,
        costPrice: _products.first.costPrice,
      ),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDState) {
            double subtotal = 0;
            for (final it in items) {
              subtotal += it.total;
            }
            final vat = isTaxEnabled ? (subtotal * (taxRate / 100.0)) : 0.0;
            final grandTotal = subtotal + vat;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.add_shopping_cart_rounded, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Text('إنشاء أمر شراء جديد ($orderNumber)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: supplierId,
                              decoration: const InputDecoration(labelText: 'المورد *', border: OutlineInputBorder()),
                              items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                              onChanged: (v) => setDState(() => supplierId = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppColors.brandPrimary),
                            tooltip: 'بحث المورد',
                            onPressed: () => _showSupplierSearchModal(context, (sId) => setDState(() => supplierId = sId)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('أصناف أمر الشراء:', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              setDState(() {
                                items.add(_PurchaseItemRow(
                                  productId: _products.first.id,
                                  quantity: 1,
                                  costPrice: _products.first.costPrice,
                                ));
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('إضافة صنف'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(items.length, (idx) {
                        final item = items[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: item.productId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                        items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setDState(() {
                                              item.productId = val;
                                              final prod = _products.firstWhere((p) => p.id == val);
                                              item.costCtrl.text = prod.costPrice.toStringAsFixed(2);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.search, size: 20, color: AppColors.brandPrimary),
                                      tooltip: 'بحث واختيار الصنف',
                                      onPressed: () {
                                        _showProductSearchModal(context, (selectedProd) {
                                          setDState(() {
                                            item.productId = selectedProd.id;
                                            item.costCtrl.text = selectedProd.costPrice.toStringAsFixed(2);
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: item.qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.qtyCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: item.costCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'التكلفة (${PrinterService.defaultCurrency})', border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.costCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.costCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              if (items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                                  onPressed: () {
                                    setDState(() {
                                      final removed = items.removeAt(idx);
                                      removed.dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'ملاحظات أمر الشراء', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('المجموع: ${subtotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
                            Text(isTaxEnabled
                                ? 'الضريبة (${taxRate.toStringAsFixed(taxRate.truncateToDouble() == taxRate ? 0 : 1)}%): ${vat.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'
                                : 'الضريبة: معفى (0%)'),
                            Text('الإجمالي: ${grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final it in items) {
                      it.dispose();
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final repo = PurchaseRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                    final poItems = items.map((it) {
                      final prod = _products.firstWhere((p) => p.id == it.productId);
                      return {
                        'productId': it.productId,
                        'unitId': prod.baseUnitId,
                        'quantity': it.quantity,
                        'unitCostCents': (it.costPrice * 100).round(),
                      };
                    }).toList();

                    repo.createPurchaseOrder(
                      companyId: companyId,
                      branchId: branchId,
                      supplierId: supplierId,
                      userId: userId,
                      orderNumber: orderNumber,
                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                      items: poItems,
                    );

                    for (final it in items) {
                      it.dispose();
                    }
                    Navigator.pop(ctx);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم إنشاء أمر الشراء $orderNumber بنجاح'), backgroundColor: AppColors.success),
                    );
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

  void _showEditOrderDialog(PurchaseOrderEntity po) {
    final db = ref.read(databaseServiceProvider);
    final ps = PrinterService(db);
    final isTaxEnabled = ps.isTaxEnabled();
    final taxRate = isTaxEnabled ? ps.getTaxRatePercent() : 0.0;

    String supplierId = po.supplierId;
    final notesController = TextEditingController(text: po.notes ?? '');

    final items = po.items.map((it) {
      return _PurchaseItemRow(
        productId: it.productId,
        quantity: it.quantity,
        costPrice: it.unitCost,
      );
    }).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDState) {
            double subtotal = 0;
            for (final it in items) {
              subtotal += it.total;
            }
            final vat = isTaxEnabled ? (subtotal * (taxRate / 100.0)) : 0.0;
            final grandTotal = subtotal + vat;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Text('تعديل أمر الشراء (${po.orderNumber})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: supplierId,
                              decoration: const InputDecoration(labelText: 'المورد *', border: OutlineInputBorder()),
                              items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                              onChanged: (v) => setDState(() => supplierId = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppColors.brandPrimary),
                            tooltip: 'بحث المورد',
                            onPressed: () => _showSupplierSearchModal(context, (sId) => setDState(() => supplierId = sId)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('أصناف أمر الشراء:', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              setDState(() {
                                items.add(_PurchaseItemRow(
                                  productId: _products.first.id,
                                  quantity: 1,
                                  costPrice: _products.first.costPrice,
                                ));
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('إضافة صنف'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(items.length, (idx) {
                        final item = items[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: item.productId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                        items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setDState(() {
                                              item.productId = val;
                                              final prod = _products.firstWhere((p) => p.id == val);
                                              item.costCtrl.text = prod.costPrice.toStringAsFixed(2);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.search, size: 20, color: AppColors.brandPrimary),
                                      tooltip: 'بحث واختيار الصنف',
                                      onPressed: () {
                                        _showProductSearchModal(context, (selectedProd) {
                                          setDState(() {
                                            item.productId = selectedProd.id;
                                            item.costCtrl.text = selectedProd.costPrice.toStringAsFixed(2);
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: item.qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.qtyCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: item.costCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'التكلفة (${PrinterService.defaultCurrency})', border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.costCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.costCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              if (items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                                  onPressed: () {
                                    setDState(() {
                                      final removed = items.removeAt(idx);
                                      removed.dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'ملاحظات أمر الشراء', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('المجموع: ${subtotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
                            Text(isTaxEnabled
                                ? 'الضريبة (${taxRate.toStringAsFixed(taxRate.truncateToDouble() == taxRate ? 0 : 1)}%): ${vat.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'
                                : 'الضريبة: معفى (0%)'),
                            Text('الإجمالي: ${grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final it in items) {
                      it.dispose();
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final repo = PurchaseRepository(db);
                    final userId = db.select('SELECT id FROM users LIMIT 1').first['id'] as String;

                    final poItems = items.map((it) {
                      final prod = _products.firstWhere((p) => p.id == it.productId);
                      return {
                        'productId': it.productId,
                        'unitId': prod.baseUnitId,
                        'quantity': it.quantity,
                        'unitCostCents': (it.costPrice * 100).round(),
                      };
                    }).toList();

                    repo.updatePurchaseOrder(
                      poId: po.id,
                      supplierId: supplierId,
                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                      items: poItems,
                      userId: userId,
                    );

                    for (final it in items) {
                      it.dispose();
                    }
                    Navigator.pop(ctx);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم تحديث أمر الشراء ${po.orderNumber} بنجاح'), backgroundColor: AppColors.success),
                    );
                  },
                  child: const Text('حفظ التعديلات'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDirectPurchaseInvoiceDialog() {
    if (_suppliers.isEmpty || _products.isEmpty || _warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل مورد ومستودع وصنف واحد على الأقل أولاً')),
      );
      return;
    }

    final db = ref.read(databaseServiceProvider);
    final ps = PrinterService(db);
    final isTaxEnabled = ps.isTaxEnabled();
    final taxRate = isTaxEnabled ? ps.getTaxRatePercent() : 0.0;

    final invoiceNumber = 'PINV-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    String supplierId = _suppliers.first.id;
    String warehouseId = _warehouses.first.id;
    String paymentMethod = 'CASH';

    final items = <_PurchaseItemRow>[
      _PurchaseItemRow(
        productId: _products.first.id,
        quantity: 10,
        costPrice: _products.first.costPrice,
      ),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDState) {
            double subtotal = 0;
            for (final it in items) {
              subtotal += it.total;
            }
            final vat = isTaxEnabled ? (subtotal * (taxRate / 100.0)) : 0.0;
            final grandTotal = subtotal + vat;

            final currentSupp = _suppliers.firstWhere((s) => s.id == supplierId, orElse: () => _suppliers.first);
            final isCreditInvalid = paymentMethod == 'CREDIT' && currentSupp.code == 'CASH_SUPP';

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text('فاتورة مشتريات وتوريد مخزني مباشر ($invoiceNumber)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 750,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Supplier Field with Search Modal
                          Expanded(
                            flex: 4,
                            child: InkWell(
                              onTap: () {
                                _showSupplierSearchModal(context, (sId) {
                                  setDState(() => supplierId = sId);
                                });
                              },
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isCreditInvalid ? Colors.red.shade50 : Colors.white,
                                  border: Border.all(
                                    color: isCreditInvalid ? Colors.red.shade400 : Colors.grey.shade400,
                                    width: isCreditInvalid ? 1.5 : 1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                paymentMethod == 'CASH' ? 'المورد (اختياري للنقد)' : 'المورد * (مطلوب للآجل)',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: paymentMethod == 'CREDIT' ? Colors.red.shade700 : Colors.grey.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            currentSupp.name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isCreditInvalid ? Colors.red.shade800 : Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.search_rounded, size: 20, color: AppColors.brandPrimary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Warehouse
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: warehouseId,
                              decoration: const InputDecoration(labelText: 'مستودع التوريد *', border: OutlineInputBorder()),
                              items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                              onChanged: (v) => setDState(() => warehouseId = v!),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Payment Method
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: paymentMethod,
                              decoration: const InputDecoration(labelText: 'طريقة الدفع *', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'CASH', child: Text('نقد (كاش)')),
                                DropdownMenuItem(value: 'CREDIT', child: Text('آجل (على الحساب)')),
                              ],
                              onChanged: (v) => setDState(() {
                                paymentMethod = v!;
                                if (paymentMethod == 'CASH') {
                                  final cashSupp = _suppliers.where((s) => s.code == 'CASH_SUPP').toList();
                                  if (cashSupp.isNotEmpty) supplierId = cashSupp.first.id;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الأصناف المشتراة والموردة:', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              setDState(() {
                                items.add(_PurchaseItemRow(
                                  productId: _products.first.id,
                                  quantity: 1,
                                  costPrice: _products.first.costPrice,
                                ));
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('إضافة صنف'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      ...List.generate(items.length, (idx) {
                        final item = items[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: item.productId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                        items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nameAr, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setDState(() {
                                              item.productId = val;
                                              final prod = _products.firstWhere((p) => p.id == val);
                                              item.costCtrl.text = prod.costPrice.toStringAsFixed(2);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.search, size: 20, color: AppColors.brandPrimary),
                                      tooltip: 'بحث واختيار الصنف',
                                      onPressed: () {
                                        _showProductSearchModal(context, (selectedProd) {
                                          setDState(() {
                                            item.productId = selectedProd.id;
                                            item.costCtrl.text = selectedProd.costPrice.toStringAsFixed(2);
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: item.qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.qtyCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: item.costCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'سعر الشراء (${PrinterService.defaultCurrency})', border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                  onTap: () {
                                    item.costCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.costCtrl.text.length);
                                  },
                                  onChanged: (_) => setDState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 110,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  '${item.total.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                              if (items.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                                  onPressed: () {
                                    setDState(() {
                                      final removed = items.removeAt(idx);
                                      removed.dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.lightBgSubtle, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('المجموع قبل الضريبة: ${subtotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
                            Text(isTaxEnabled
                                ? 'ضريبة القيمة المضافة (${taxRate.toStringAsFixed(taxRate.truncateToDouble() == taxRate ? 0 : 1)}%): ${vat.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'
                                : 'ضريبة القيمة المضافة: معفى (0%)'),
                            Text('الإجمالي النهائي: ${grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    for (final it in items) {
                      it.dispose();
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('حفظ الفاتورة وتوريد المخزون فوراً'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  onPressed: () {
                    if (paymentMethod == 'CREDIT' && currentSupp.code == 'CASH_SUPP') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يجب تحديد مورد آجل حقيقي (وليس مورد نقدي عام) عند الشراء بالآجل')),
                      );
                      _showSupplierSearchModal(context, (sId) => setDState(() => supplierId = sId));
                      return;
                    }

                    final repo = PurchaseRepository(db);
                    final accountingRepo = ref.read(accountingRepositoryProvider);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
                    final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
                    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

                    try {
                      final poItems = items.map((it) {
                        final prod = _products.firstWhere((p) => p.id == it.productId);
                        return {
                          'productId': it.productId,
                          'unitId': prod.baseUnitId,
                          'quantity': it.quantity,
                          'unitCostCents': (it.costPrice * 100).round(),
                        };
                      }).toList();

                      final po = repo.createPurchaseOrder(
                        companyId: companyId,
                        branchId: branchId,
                        supplierId: supplierId,
                        userId: userId,
                        orderNumber: invoiceNumber,
                        items: poItems,
                      );

                      final grnItems = items.map((it) {
                        return {
                          'productId': it.productId,
                          'quantity': it.quantity,
                          'unitCostCents': (it.costPrice * 100).round(),
                        };
                      }).toList();

                      repo.receiveGoods(
                        companyId: companyId,
                        branchId: branchId,
                        warehouseId: warehouseId,
                        supplierId: supplierId,
                        userId: userId,
                        purchaseOrderId: po.id,
                        receiptNumber: 'GRN-$invoiceNumber',
                        receivedItems: grnItems,
                      );

                      if (paymentMethod == 'CREDIT') {
                        final grandCents = (grandTotal * 100).round();
                        db.execute('''
                          UPDATE suppliers 
                          SET current_balance = current_balance + ?, updated_at = datetime('now')
                          WHERE id = ?
                        ''', [grandCents, supplierId]);
                      }

                      final totalCostCents = (subtotal * 100).round();
                      final supplierName = _suppliers.firstWhere((s) => s.id == supplierId).name;
                      accountingRepo.postPurchaseGrnJournal(
                        companyId: companyId,
                        branchId: branchId,
                        userId: userId,
                        grnId: po.id,
                        grnNumber: invoiceNumber,
                        grnDate: DateTime.now(),
                        totalCostCents: totalCostCents,
                        supplierName: supplierName,
                      );

                      for (final it in items) {
                        it.dispose();
                      }
                      Navigator.pop(ctx);
                      _loadData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حفظ فاتورة المشتريات وتوريد الأصناف للمخزن بنجاح'), backgroundColor: AppColors.success),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.danger),
                      );
                    }
                  },
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        subtitle: Text('الكمية: ${i.quantity} | تكلفة الوحدة: ${i.unitCost.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
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

  Future<void> _printPurchaseOrder(PurchaseOrderEntity po) async {
    final supplier = _suppliers.firstWhere(
      (s) => s.id == po.supplierId,
      orElse: () => SupplierEntity(id: '', companyId: '', code: '', name: 'مورد غير مسجل'),
    );

    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT trade_name, legal_name, tax_number, address, phone FROM companies LIMIT 1');
    final comp = compResult.isNotEmpty ? compResult.first : <String, dynamic>{};
    final companyName = (comp['trade_name'] ?? comp['legal_name'] ?? 'ALFA SOFT') as String;
    final taxNo = (comp['tax_number'] ?? '') as String;

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();

        doc.addPage(
          pw.Page(
            pageFormat: format,
            textDirection: pw.TextDirection.rtl,
            build: (pw.Context ctx) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                          if (taxNo.isNotEmpty) pw.Text('الرقم الضريبي: $taxNo', style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('فاتورة وأمر شراء', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                          pw.Text('رقم المستند: ${po.orderNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                          pw.Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(po.orderDate)}', style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 1.5),
                  pw.SizedBox(height: 8),

                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('المورد: ${supplier.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        if (supplier.phone != null) pw.Text('الهاتف: ${supplier.phone}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('الحالة: ${po.status == 'RECEIVED' ? 'تم الاستلام' : 'معلق'}', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الصنف', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('الكمية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('سعر الوحدة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المجموع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                        ],
                      ),
                      ...List.generate(po.items.length, (i) {
                        final item = po.items[i];
                        final prod = _products.firstWhere((p) => p.id == item.productId, orElse: () => _products.first);
                        return pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 10))),
                            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(prod.nameAr, style: const pw.TextStyle(fontSize: 10))),
                            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${item.quantity}', style: const pw.TextStyle(fontSize: 10))),
                            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${item.unitCost.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const pw.TextStyle(fontSize: 10))),
                            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${item.lineTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const pw.TextStyle(fontSize: 10))),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: 240,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('المجموع قبل الضريبة:', style: const pw.TextStyle(fontSize: 10)),
                                pw.Text('${po.subtotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const pw.TextStyle(fontSize: 10)),
                              ],
                            ),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('ضريبة القيمة المضافة (15%):', style: const pw.TextStyle(fontSize: 10)),
                                pw.Text('${po.taxTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const pw.TextStyle(fontSize: 10)),
                              ],
                            ),
                            pw.Divider(),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('الإجمالي الكلي:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                                pw.Text('${po.grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );

        return doc.save();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _searchController.text.trim().toLowerCase();
    final filteredOrders = _orders.where((po) {
      if (_orderStatusFilter != 'ALL' && po.status != _orderStatusFilter) return false;
      if (_selectedSupplierFilter != null && po.supplierId != _selectedSupplierFilter) return false;
      if (query.isNotEmpty) {
        final supplier = _suppliers.firstWhere((s) => s.id == po.supplierId, orElse: () => SupplierEntity(id: '', companyId: '', code: '', name: ''));
        return po.orderNumber.toLowerCase().contains(query) || supplier.name.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text('إدارة المشتريات والتوريد الشاملة',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('أوامر الشراء، كشف التوريد الفعلي (GRN)، التعديل، والطباعة والتصدير',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showDirectPurchaseInvoiceDialog,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('فاتورة مشتريات وتوريد مباشر'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showCreateOrderDialog,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('أمر شراء جديد (PO)'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.lightBgSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.lightBorderSubtle),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.brandAccent,
                labelColor: AppColors.brandPrimary,
                unselectedLabelColor: AppColors.lightTextSecondary,
                tabs: [
                  Tab(icon: const Icon(Icons.shopping_bag_outlined, size: 18), text: 'أوامر وفواتير الشراء (${filteredOrders.length})'),
                  Tab(icon: const Icon(Icons.inventory_2_rounded, size: 18), text: 'كشف حركات الاستلام والتوريد المخزني (${_grnNotes.length})'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Orders & Invoices List
                  _buildOrdersView(filteredOrders),

                  // Tab 2: GRN Supply Statement
                  _buildGrnStatementView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersView(List<PurchaseOrderEntity> filteredOrders) {
    return Column(
      children: [
        // Filter bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ابحث برقم الأمر أو اسم المورد...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _orderStatusFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('كافة الحالات')),
                DropdownMenuItem(value: 'PENDING', child: Text('معلق / بانتظار التوريد')),
                DropdownMenuItem(value: 'RECEIVED', child: Text('تم الاستلام الفعلي')),
              ],
              onChanged: (v) => setState(() => _orderStatusFilter = v!),
            ),
            const SizedBox(width: 10),
            DropdownButton<String?>(
              value: _selectedSupplierFilter,
              hint: const Text('تصفية بالمورد'),
              items: [
                const DropdownMenuItem(value: null, child: Text('كافة الموردين')),
                ..._suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
              ],
              onChanged: (v) => setState(() => _selectedSupplierFilter = v),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Expanded(
          child: Card(
            child: filteredOrders.isEmpty
                ? const Center(child: Text('لا توجد أوامر شراء مطابقة لمعايير البحث', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    itemCount: filteredOrders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final po = filteredOrders[idx];
                      final supplier = _suppliers.firstWhere(
                        (s) => s.id == po.supplierId,
                        orElse: () => SupplierEntity(id: '', companyId: '', code: '', name: 'مورد غير مسجل'),
                      );
                      final isReceived = po.status == 'RECEIVED';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isReceived ? AppColors.success.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15),
                          child: Icon(
                            isReceived ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                            color: isReceived ? AppColors.success : AppColors.warning,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(po.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 10),
                            Text('• ${supplier.name}', style: const TextStyle(fontSize: 13)),
                            const Spacer(),
                            Text(
                              '${po.grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.brandPrimary),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text('التاريخ: ${DateFormat('yyyy/MM/dd').format(po.orderDate)}', style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 16),
                              Text('الأصناف: ${po.items.length} صنف', style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 16),
                              Chip(
                                label: Text(isReceived ? 'تم التوريد للمخزن' : 'معلق / قيد التوريد', style: const TextStyle(fontSize: 10)),
                                backgroundColor: isReceived ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isReceived)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('استلام (GRN)'),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandAccent, foregroundColor: Colors.white),
                                onPressed: () => _showReceiveGoodsDialog(po),
                              ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, color: AppColors.brandPrimary),
                              tooltip: 'تعديل أمر الشراء',
                              onPressed: () => _showEditOrderDialog(po),
                            ),
                            IconButton(
                              icon: const Icon(Icons.print_rounded, color: Colors.blueGrey),
                              tooltip: 'طباعة الفاتورة / أمر الشراء (A4 PDF)',
                              onPressed: () => _printPurchaseOrder(po),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrnStatementView() {
    return Card(
      child: _grnNotes.isEmpty
          ? const Center(child: Text('لا توجد أذون استلام مخزني مسجلة حتى الآن', style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              itemCount: _grnNotes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final grn = _grnNotes[idx];
                final receiptNo = grn['receipt_number'] as String? ?? '';
                final supplierName = grn['supplier_name'] as String? ?? 'مورد غير محدد';
                final warehouseName = grn['warehouse_name'] as String? ?? 'المخزن الرئيسي';
                final totalCost = ((grn['total_cost'] as int? ?? 0) / 100.0).toStringAsFixed(2);
                final date = grn['receipt_date'] as String? ?? '';
                final receiver = grn['receiver_name'] as String? ?? 'مسؤول المستودع';

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2F1),
                    child: Icon(Icons.inventory_2_rounded, color: Colors.teal),
                  ),
                  title: Row(
                    children: [
                      Text('إذن توريد: $receiptNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 10),
                      Text('• المورد: $supplierName', style: const TextStyle(fontSize: 12)),
                      const Spacer(),
                      Text('$totalCost ${PrinterService.defaultCurrency}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Text('المستودع: $warehouseName', style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 16),
                        Text('المستلم: $receiver', style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 16),
                        Text('التاريخ: $date', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showSupplierSearchModal(BuildContext context, ValueChanged<String> onSelected) {
    if (_suppliers.isEmpty) {
      try {
        final db = ref.read(databaseServiceProvider);
        final partnerRepo = PartnerRepository(db);
        final compResult = db.select('SELECT id FROM companies LIMIT 1');
        if (compResult.isNotEmpty) {
          _suppliers = partnerRepo.getSuppliers(compResult.first['id'] as String);
        }
      } catch (_) {}
    }
    String query = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          final q = query.trim().toLowerCase();
          final filtered = _suppliers.where((s) {
            if (q.isEmpty) return true;
            return s.name.toLowerCase().contains(q) ||
                s.code.toLowerCase().contains(q) ||
                (s.phone != null && s.phone!.contains(q));
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.person_search_rounded, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                const Text('البحث واختيار المورد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 550,
              height: 450,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ابحث باسم المورد، الهاتف، أو الكود...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (val) => setDState(() => query = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final s = filtered[idx];
                              final bal = s.currentBalance;
                              final isCash = s.code == 'CASH_SUPP';
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isCash ? Colors.grey.shade200 : AppColors.brandPrimary.withValues(alpha: 0.1),
                                  child: Icon(isCash ? Icons.storefront_rounded : Icons.business_rounded, color: isCash ? Colors.grey.shade700 : AppColors.brandPrimary),
                                ),
                                title: Row(
                                  children: [
                                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (isCash) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blueGrey.shade100, borderRadius: BorderRadius.circular(4)),
                                        child: const Text('مورد نقدي عام', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text('كود: ${s.code}${s.phone != null ? ' | هاتف: ${s.phone}' : ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'الرصيد: ${bal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: bal > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                      ),
                                    ),
                                    Text(bal > 0 ? 'مستحق له' : 'خالص', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  ],
                                ),
                                onTap: () {
                                  onSelected(s.id);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
  }

  void _showProductSearchModal(BuildContext context, ValueChanged<ProductEntity> onSelected) {
    if (_products.isEmpty) {
      try {
        final db = ref.read(databaseServiceProvider);
        final catalogRepo = CatalogRepository(db);
        final compResult = db.select('SELECT id FROM companies LIMIT 1');
        if (compResult.isNotEmpty) {
          _products = catalogRepo.getProducts(companyId: compResult.first['id'] as String);
        }
      } catch (_) {}
    }
    String query = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          final q = query.trim().toLowerCase();
          final filtered = _products.where((p) {
            if (q.isEmpty) return true;
            return p.nameAr.toLowerCase().contains(q) ||
                (p.nameEn != null && p.nameEn!.toLowerCase().contains(q)) ||
                p.sku.toLowerCase().contains(q) ||
                (p.barcode != null && p.barcode!.toLowerCase().contains(q));
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                const Text('البحث واختيار الصنف من المخزون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text('${filtered.length} صنف متاح', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ابحث باسم الصنف، الباركود، أو الكود...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (val) => setDState(() => query = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('لا توجد أصناف مطابقة لكلمة البحث', style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final p = filtered[idx];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.1),
                                  child: const Icon(Icons.category_rounded, color: AppColors.brandPrimary, size: 20),
                                ),
                                title: Text(p.nameAr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text('SKU: ${p.sku}${p.barcode != null ? ' | باركود: ${p.barcode}' : ''} | التكلفة: ${p.costPrice.toStringAsFixed(2)} ${PrinterService.defaultCurrency}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                trailing: const Icon(Icons.add_shopping_cart_rounded, color: AppColors.brandPrimary, size: 20),
                                onTap: () {
                                  onSelected(p);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
  }
}

class _PurchaseItemRow {
  String productId;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;

  _PurchaseItemRow({
    required this.productId,
    int quantity = 1,
    double costPrice = 0.0,
  })  : qtyCtrl = TextEditingController(text: quantity.toString()),
        costCtrl = TextEditingController(text: costPrice.toStringAsFixed(2));

  int get quantity => int.tryParse(qtyCtrl.text.trim()) ?? 1;
  double get costPrice => double.tryParse(costCtrl.text.trim()) ?? 0.0;
  double get total => quantity * costPrice;

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}
