import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/entities/catalog.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  List<ProductEntity> _products = [];
  List<CategoryEntity> _categories = [];
  List<UnitEntity> _units = [];
  String? _selectedCategoryId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    final db = ref.read(databaseServiceProvider);
    final repo = CatalogRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _categories = repo.getCategories(companyId);
        _units = repo.getUnits(companyId);
        _products = repo.getProducts(
          companyId: companyId,
          query: _searchController.text,
          categoryId: _selectedCategoryId,
        );
      }
    } catch (_) {
      // Handle gracefully
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddProductDialog() {
    final formKey = GlobalKey<FormState>();
    final skuController = TextEditingController(text: 'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final barcodeController = TextEditingController();
    final nameArController = TextEditingController();
    final nameEnController = TextEditingController();
    final costPriceController = TextEditingController(text: '0.00');
    final salePriceController = TextEditingController(text: '0.00');
    final minPriceController = TextEditingController(text: '0.00');
    final reorderLevelController = TextEditingController(text: '10');

    String? categoryId = _categories.isNotEmpty ? _categories.first.id : null;
    String baseUnitId = _units.isNotEmpty ? _units.first.id : 'unit_pcs';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إضافة صنف جديد للكتالوج', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 600,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: skuController,
                                decoration: const InputDecoration(labelText: 'رمز الصنف (SKU) *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: barcodeController,
                                decoration: const InputDecoration(labelText: 'الباركود الدولي (اختياري)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameArController,
                          decoration: const InputDecoration(labelText: 'اسم الصنف بالعربية *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameEnController,
                          decoration: const InputDecoration(labelText: 'اسم الصنف بالإنجليزية (اختياري)'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: categoryId,
                                decoration: const InputDecoration(labelText: 'التصنيف'),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('بدون تصنيف')),
                                  ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                                ],
                                onChanged: (v) => setDialogState(() => categoryId = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: baseUnitId,
                                decoration: const InputDecoration(labelText: 'وحدة القياس الأساسية *'),
                                items: _units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))).toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => baseUnitId = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: costPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'سعر التكلفة (SAR)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: salePriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'سعر البيع الافتراضي (SAR) *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: minPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'أدنى سعر بيع'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reorderLevelController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'حد إعادة الطلب (تنبيه نقص المخزون)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('حفظ الصنف'),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    final db = ref.read(databaseServiceProvider);
                    final repo = CatalogRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                    final costCents = ((double.tryParse(costPriceController.text) ?? 0.0) * 100).round();
                    final saleCents = ((double.tryParse(salePriceController.text) ?? 0.0) * 100).round();
                    final minCents = ((double.tryParse(minPriceController.text) ?? 0.0) * 100).round();
                    final reorder = int.tryParse(reorderLevelController.text) ?? 0;

                    repo.createProduct(
                      companyId: companyId,
                      categoryId: categoryId,
                      baseUnitId: baseUnitId,
                      sku: skuController.text.trim(),
                      barcode: barcodeController.text.trim().isEmpty ? skuController.text.trim() : barcodeController.text.trim(),
                      nameAr: nameArController.text.trim(),
                      nameEn: nameEnController.text.trim().isEmpty ? null : nameEnController.text.trim(),
                      costPriceCents: costCents,
                      salePriceCents: saleCents,
                      minSalePriceCents: minCents,
                      reorderLevel: reorder,
                    );

                    Navigator.pop(ctx);
                    _loadData();
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
                      Text('كتالوج الأصناف والخدمات',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('إدارة بطاقات المنتجات، الباركود، أسعار البيع والتكلفة وحدود الطلب',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddProductDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة صنف جديد'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Search and Filter Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'بحث بالاسم، الباركود، أو الـ SKU...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (_) => _loadData(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(labelText: 'تصفية حسب التصنيف'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('جميع التصنيفات')),
                          ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedCategoryId = v);
                          _loadData();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Products Table
            Expanded(
              child: Card(
                child: _products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text('لا توجد أصناف تطابق معايير البحث',
                                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('SKU / كود')),
                            DataColumn(label: Text('الباركود')),
                            DataColumn(label: Text('اسم الصنف')),
                            DataColumn(label: Text('سعر التكلفة')),
                            DataColumn(label: Text('سعر البيع')),
                            DataColumn(label: Text('أدنى سعر')),
                            DataColumn(label: Text('حد الطلب')),
                            DataColumn(label: Text('الحالة')),
                          ],
                          rows: _products.map((p) {
                            return DataRow(cells: [
                              DataCell(Text(p.sku, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(p.barcode ?? '—')),
                              DataCell(Text(p.nameAr)),
                              DataCell(Text('${p.costPrice.toStringAsFixed(2)} SAR')),
                              DataCell(Text('${p.salePrice.toStringAsFixed(2)} SAR',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandAccent))),
                              DataCell(Text('${p.minSalePrice.toStringAsFixed(2)} SAR')),
                              DataCell(Text('${p.reorderLevel}')),
                              DataCell(Chip(
                                label: Text(p.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                backgroundColor: p.isActive
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.danger.withValues(alpha: 0.15),
                                side: BorderSide.none,
                              )),
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
