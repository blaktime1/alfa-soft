import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/math/bankers_rounding.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/organization.dart';

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
  List<WarehouseEntity> _warehouses = [];
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
    final orgRepo = OrganizationRepository(db);

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

    bool hasCartonPackaging = false;
    final unitsPerCartonController = TextEditingController(text: '12');
    final cartonPriceController = TextEditingController();
    final cartonCostPriceController = TextEditingController();
    final cartonBarcodeController = TextEditingController();

    String? categoryId = _categories.isNotEmpty ? _categories.first.id : null;
    String baseUnitId = _units.isNotEmpty ? _units.first.id : 'unit_pcs';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.add_box_rounded, color: AppColors.brandPrimary),
                  SizedBox(width: 8),
                  Text('إضافة صنف جديد للكتالوج', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 620,
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
                                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                                onChanged: (v) => setDialogState(() => categoryId = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: baseUnitId,
                                decoration: const InputDecoration(labelText: 'وحدة القياس الأساسية *'),
                                items: _units.map((u) => DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.code})'))).toList(),
                                onChanged: (v) => setDialogState(() => baseUnitId = v ?? 'unit_pcs'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const Text('هيكل الأسعار والتكلفة (للحبة / الوحدة الأساسية)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandPrimary)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: costPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'سعر الشراء / التكلفة (SAR) *'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'أدخل رقماً صحيحاً' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: salePriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'سعر البيع (تجزئة) (SAR) *'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'أدخل رقماً صحيحاً' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: minPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'أدنى سعر بيع (جملة) (SAR)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: reorderLevelController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'حد إعادة الطلب بالمخزن'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Multi-unit Packaging (Carton vs Piece) Container
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.all_inbox_rounded, color: AppColors.brandPrimary, size: 20),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'نظام البيع بالكرتون والحبة (اختياري)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.brandPrimary),
                                    ),
                                  ),
                                  Switch(
                                    value: hasCartonPackaging,
                                    activeThumbColor: AppColors.brandPrimary,
                                    onChanged: (val) => setDialogState(() => hasCartonPackaging = val),
                                  ),
                                ],
                              ),
                              if (hasCartonPackaging) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: unitsPerCartonController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'الكرتون كم فيه حبة؟ *',
                                          hintText: 'مثال: 12 أو 24',
                                          prefixIcon: Icon(Icons.numbers_rounded, size: 18),
                                        ),
                                        validator: (v) => hasCartonPackaging && (int.tryParse(v ?? '') ?? 0) <= 1 ? 'أدخل عدداً أكبر من 1' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر بيع الكرتون (SAR)',
                                          hintText: 'اتركه فارغاً للحساب التلقائي',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonCostPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر شراء الكرتون (SAR)',
                                          hintText: 'اتركه فارغاً للحساب التلقائي',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonBarcodeController,
                                        decoration: const InputDecoration(
                                          labelText: 'باركود الكرتون (اختياري)',
                                          prefixIcon: Icon(Icons.qr_code_2_rounded, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;

                    final db = ref.read(databaseServiceProvider);
                    final repo = CatalogRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                    final costDouble = double.parse(costPriceController.text.trim());
                    final saleDouble = double.parse(salePriceController.text.trim());
                    final minDouble = double.tryParse(minPriceController.text.trim()) ?? 0.0;
                    final reorderInt = int.tryParse(reorderLevelController.text.trim()) ?? 10;

                    final int unitsPerCarton = hasCartonPackaging ? (int.tryParse(unitsPerCartonController.text.trim()) ?? 1) : 1;
                    final double cartonPriceD = hasCartonPackaging ? (double.tryParse(cartonPriceController.text.trim()) ?? 0.0) : 0.0;
                    final double cartonCostD = hasCartonPackaging ? (double.tryParse(cartonCostPriceController.text.trim()) ?? 0.0) : 0.0;
                    final String? cartonBarcode = hasCartonPackaging && cartonBarcodeController.text.trim().isNotEmpty
                        ? cartonBarcodeController.text.trim()
                        : null;

                    repo.createProduct(
                      companyId: companyId,
                      sku: skuController.text.trim(),
                      barcode: barcodeController.text.trim().isNotEmpty ? barcodeController.text.trim() : null,
                      nameAr: nameArController.text.trim(),
                      nameEn: nameEnController.text.trim().isNotEmpty ? nameEnController.text.trim() : null,
                      categoryId: categoryId,
                      baseUnitId: baseUnitId,
                      costPriceCents: BankersRounding.toMinorUnits(costDouble),
                      salePriceCents: BankersRounding.toMinorUnits(saleDouble),
                      minSalePriceCents: BankersRounding.toMinorUnits(minDouble),
                      reorderLevel: reorderInt,
                      unitsPerCarton: unitsPerCarton,
                      cartonPriceCents: BankersRounding.toMinorUnits(cartonPriceD),
                      cartonCostPriceCents: BankersRounding.toMinorUnits(cartonCostD),
                      cartonBarcode: cartonBarcode,
                    );

                    Navigator.pop(ctx);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت إضافة الصنف بنجاح للكتالوج!'), backgroundColor: AppColors.success),
                    );
                  },
                  child: const Text('حفظ الصنف'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Prompts for admin password verification when modifying cost/purchase price
  Future<bool> _promptCostPriceAdminAuth({
    required double oldPrice,
    required double newPrice,
    required String productName,
  }) async {
    final passwordController = TextEditingController();
    bool isObscured = true;
    String? errorText;

    final authorized = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.brandGoldDark, width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.shield_rounded, color: AppColors.brandGoldDark, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'تأكيد أمني: تعديل سعر الشراء / التكلفة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.brandGold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الصنف: $productName', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text('السعر السابق: ${oldPrice.toStringAsFixed(2)} SAR',
                                  style: const TextStyle(color: AppColors.lightTextSecondary)),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.brandPrimary),
                              const SizedBox(width: 12),
                              Text('السعر الجديد: ${newPrice.toStringAsFixed(2)} SAR',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.successText)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'تعديل سعر الشراء يؤثر مباشرة على تقييم المخزون وهوامش الأرباح. يرجى إدخال كلمة مرور المدير العام للموافقة:',
                      style: TextStyle(fontSize: 13, color: AppColors.lightTextPrimary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: isObscured,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'كلمة مرور المدير *',
                        prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.brandPrimary),
                        suffixIcon: IconButton(
                          icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setModalState(() => isObscured = !isObscured),
                        ),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.verified_user_rounded, size: 18),
                  label: const Text('تأكيد وتفويض السعر'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandGoldDark,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final pass = passwordController.text.trim();
                    if (pass.isEmpty) {
                      setModalState(() => errorText = 'كلمة المرور مطلوبة للمتابعة');
                      return;
                    }

                    final db = ref.read(databaseServiceProvider);
                    final passwordHash = sha256.convert(utf8.encode(pass)).toString();
                    final adminCheck = db.select(
                      'SELECT id FROM users WHERE (is_admin = 1 OR username = "admin") AND password_hash = ? LIMIT 1',
                      [passwordHash],
                    );

                    if (adminCheck.isNotEmpty) {
                      Navigator.pop(ctx, true);
                    } else {
                      setModalState(() => errorText = 'كلمة المرور غير صحيحة! تم رفض التفويض.');
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    return authorized ?? false;
  }

  void _showEditProductDialog(ProductEntity product) {
    final formKey = GlobalKey<FormState>();
    final barcodeController = TextEditingController(text: product.barcode ?? '');
    final nameArController = TextEditingController(text: product.nameAr);
    final nameEnController = TextEditingController(text: product.nameEn ?? '');
    final costPriceController = TextEditingController(text: product.costPrice.toStringAsFixed(2));
    final salePriceController = TextEditingController(text: product.salePrice.toStringAsFixed(2));
    final minPriceController = TextEditingController(text: product.minSalePrice.toStringAsFixed(2));
    final reorderLevelController = TextEditingController(text: product.reorderLevel.toString());

    bool hasCartonPackaging = product.hasCarton;
    final unitsPerCartonController = TextEditingController(text: product.unitsPerCarton > 1 ? product.unitsPerCarton.toString() : '12');
    final cartonPriceController = TextEditingController(text: product.cartonPriceCents > 0 ? (product.cartonPriceCents / 100.0).toStringAsFixed(2) : '');
    final cartonCostPriceController = TextEditingController(text: product.cartonCostPriceCents > 0 ? (product.cartonCostPriceCents / 100.0).toStringAsFixed(2) : '');
    final cartonBarcodeController = TextEditingController(text: product.cartonBarcode ?? '');

    String? categoryId = product.categoryId;
    String baseUnitId = product.baseUnitId;
    bool isActive = product.isActive;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: AppColors.brandAccent),
                  const SizedBox(width: 8),
                  Text('تعديل الصنف: ${product.nameAr}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 620,
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
                                initialValue: product.sku,
                                enabled: false,
                                decoration: const InputDecoration(labelText: 'رمز الصنف (SKU - للقراءة فقط)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: barcodeController,
                                decoration: const InputDecoration(labelText: 'الباركود الدولي'),
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
                                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                                onChanged: (v) => setDialogState(() => categoryId = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: baseUnitId,
                                decoration: const InputDecoration(labelText: 'الوحدة الأساسية'),
                                items: _units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))).toList(),
                                onChanged: (v) => setDialogState(() => baseUnitId = v ?? baseUnitId),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        Row(
                          children: [
                            const Text('هيكل الأسعار والتكلفة', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandPrimary)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.brandGold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_rounded, size: 12, color: AppColors.brandGoldDark),
                                  SizedBox(width: 4),
                                  Text('سعر الشراء محمي بكلمة مرور', style: TextStyle(fontSize: 10, color: AppColors.brandGoldDark, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: costPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'سعر الشراء / التكلفة (SAR) *',
                                  prefixIcon: Icon(Icons.shield_outlined, size: 18, color: AppColors.brandGoldDark),
                                ),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'أدخل رقماً صحيحاً' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: salePriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'سعر البيع (تجزئة) (SAR) *'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'أدخل رقماً صحيحاً' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: minPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'أدنى سعر بيع (جملة) (SAR)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: reorderLevelController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'حد إعادة الطلب بالمخزن'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Multi-unit Packaging (Carton vs Piece) Container
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.all_inbox_rounded, color: AppColors.brandPrimary, size: 20),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'نظام البيع بالكرتون والحبة (اختياري)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.brandPrimary),
                                    ),
                                  ),
                                  Switch(
                                    value: hasCartonPackaging,
                                    activeThumbColor: AppColors.brandPrimary,
                                    onChanged: (val) => setDialogState(() => hasCartonPackaging = val),
                                  ),
                                ],
                              ),
                              if (hasCartonPackaging) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: unitsPerCartonController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'الكرتون كم فيه حبة؟ *',
                                          hintText: 'مثال: 12 أو 24',
                                          prefixIcon: Icon(Icons.numbers_rounded, size: 18),
                                        ),
                                        validator: (v) => hasCartonPackaging && (int.tryParse(v ?? '') ?? 0) <= 1 ? 'أدخل عدداً أكبر من 1' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر بيع الكرتون (SAR)',
                                          hintText: 'اتركه فارغاً للحساب التلقائي',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonCostPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر شراء الكرتون (SAR)',
                                          hintText: 'اتركه فارغاً للحساب التلقائي',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: cartonBarcodeController,
                                        decoration: const InputDecoration(
                                          labelText: 'باركود الكرتون (اختياري)',
                                          prefixIcon: Icon(Icons.qr_code_2_rounded, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('حالة الصنف في المنظومة (نشط للبيع)'),
                          value: isActive,
                          activeThumbColor: AppColors.success,
                          onChanged: (val) => setDialogState(() => isActive = val),
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
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() != true) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(ctx);

                    final newCostDouble = double.parse(costPriceController.text.trim());
                    final originalCostDouble = product.costPrice;

                    // Security check: if cost price was modified, prompt for admin password
                    if ((newCostDouble - originalCostDouble).abs() > 0.001) {
                      final isAuthorized = await _promptCostPriceAdminAuth(
                        oldPrice: originalCostDouble,
                        newPrice: newCostDouble,
                        productName: product.nameAr,
                      );

                      if (!isAuthorized) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('تم إلغاء التعديل: تعديل سعر الشراء يتطلب تفويض كلمة المرور للمدير.'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                        return;
                      }
                    }

                    final db = ref.read(databaseServiceProvider);
                    final repo = CatalogRepository(db);
                    final currentUser = ref.read(currentUserProvider);

                    final saleDouble = double.parse(salePriceController.text.trim());
                    final minDouble = double.tryParse(minPriceController.text.trim()) ?? 0.0;
                    final reorderInt = int.tryParse(reorderLevelController.text.trim()) ?? 10;

                    final int unitsPerCarton = hasCartonPackaging ? (int.tryParse(unitsPerCartonController.text.trim()) ?? 1) : 1;
                    final double cartonPriceD = hasCartonPackaging ? (double.tryParse(cartonPriceController.text.trim()) ?? 0.0) : 0.0;
                    final double cartonCostD = hasCartonPackaging ? (double.tryParse(cartonCostPriceController.text.trim()) ?? 0.0) : 0.0;
                    final String? cartonBarcode = hasCartonPackaging && cartonBarcodeController.text.trim().isNotEmpty
                        ? cartonBarcodeController.text.trim()
                        : null;

                    repo.updateProduct(
                      id: product.id,
                      nameAr: nameArController.text.trim(),
                      nameEn: nameEnController.text.trim().isNotEmpty ? nameEnController.text.trim() : null,
                      barcode: barcodeController.text.trim().isNotEmpty ? barcodeController.text.trim() : null,
                      costPriceCents: BankersRounding.toMinorUnits(newCostDouble),
                      salePriceCents: BankersRounding.toMinorUnits(saleDouble),
                      minSalePriceCents: BankersRounding.toMinorUnits(minDouble),
                      reorderLevel: reorderInt,
                      categoryId: categoryId,
                      baseUnitId: baseUnitId,
                      isActive: isActive,
                      unitsPerCarton: unitsPerCarton,
                      cartonPriceCents: BankersRounding.toMinorUnits(cartonPriceD),
                      cartonCostPriceCents: BankersRounding.toMinorUnits(cartonCostD),
                      cartonBarcode: cartonBarcode,
                      modifiedBy: currentUser?.username ?? 'ADMIN',
                    );

                    nav.pop();
                    _loadData();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('تم تحديث بيانات الصنف والأسعار بنجاح!'), backgroundColor: AppColors.success),
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

  /// Dialog to set warehouse-specific price overrides (e.g. Higher price in Warehouse 2)
  void _showWarehousePricingDialog(ProductEntity product) {
    if (_warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مستودعات مسجلة في الفرع لتخصيص الأسعار')),
      );
      return;
    }

    final db = ref.read(databaseServiceProvider);
    final repo = CatalogRepository(db);
    final whPrices = repo.getWarehousePrices(product.id);
    final controllers = <String, TextEditingController>{};

    for (final wh in _warehouses) {
      final existing = whPrices.firstWhere(
        (p) => p['warehouse_id'] == wh.id,
        orElse: () => <String, dynamic>{},
      );
      final currentSale = existing.isNotEmpty
          ? ((existing['sale_price'] as int) / 100.0).toStringAsFixed(2)
          : product.salePrice.toStringAsFixed(2);
      controllers[wh.id] = TextEditingController(text: currentSale);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightBgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.storefront_rounded, color: AppColors.brandGoldDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تسعير خاص للمخازن والفروع: ${product.nameAr}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.brandPrimary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'السعر الأساسي المعتمد في المنظومة: ${product.salePrice.toStringAsFixed(2)} SAR. يمكنك تحديد سعر مختلف لكل مستودع (مثلاً بيع في مخزن 2 بسعر أعلى).',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ..._warehouses.map((wh) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(wh.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('كود المستودع: ${wh.code}', style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: controllers[wh.id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'سعر البيع',
                              suffixText: 'SAR',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              for (final wh in _warehouses) {
                final text = controllers[wh.id]?.text.trim() ?? '';
                final priceDouble = double.tryParse(text);
                if (priceDouble != null && priceDouble > 0) {
                  repo.setWarehousePrice(
                    warehouseId: wh.id,
                    productId: product.id,
                    salePriceCents: BankersRounding.toMinorUnits(priceDouble),
                  );
                }
              }
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ وتحديث أسعار المخازن بنجاح!'), backgroundColor: AppColors.success),
              );
            },
            child: const Text('حفظ أسعار المخازن'),
          ),
        ],
      ),
    );
  }

  void _showDeleteProductDialog(ProductEntity product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightBgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد حذف / تعطيل الصنف', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف الصنف "${product.nameAr}" (SKU: ${product.sku})؟ سيتم تعطيله لمنع اختلال القيود التاريخية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              final db = ref.read(databaseServiceProvider);
              final repo = CatalogRepository(db);
              final currentUser = ref.read(currentUserProvider);

              repo.deleteProduct(product.id, currentUser?.username ?? 'ADMIN');
              Navigator.pop(ctx);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف وتعطيل الصنف بنجاح!'), backgroundColor: AppColors.danger),
              );
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
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
                    Text('كتالوج الأصناف والأسعار',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.brandPrimary)),
                    const SizedBox(height: 4),
                    Text('إدارة الأصناف، وحدات القياس، أسعار التجزئة والجملة وسعر الشراء المحمي',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.lightTextSecondary)),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddProductDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة صنف جديد'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'بحث برمز SKU أو الباركود أو الاسم...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (_) => _loadData(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String?>(
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
                            DataColumn(label: Text('التعبئة والكرتون')),
                            DataColumn(label: Text('سعر الشراء (التكلفة)')),
                            DataColumn(label: Text('سعر البيع (تجزئة)')),
                            DataColumn(label: Text('أدنى سعر (جملة)')),
                            DataColumn(label: Text('حد الطلب')),
                            DataColumn(label: Text('الحالة')),
                            DataColumn(label: Text('الإجراءات')),
                          ],
                          rows: _products.map((p) {
                            return DataRow(cells: [
                              DataCell(Text(p.sku, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(p.barcode ?? '—')),
                              DataCell(Text(p.nameAr)),
                              DataCell(
                                p.hasCarton
                                    ? Chip(
                                        label: Text('كرتون (${p.unitsPerCarton} حبة)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.12),
                                        side: BorderSide.none,
                                      )
                                    : const Text('حبة فقط', style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${p.costPrice.toStringAsFixed(2)} SAR'),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.brandGoldDark),
                                  ],
                                ),
                              ),
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
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.storefront_rounded, size: 18, color: AppColors.brandGoldDark),
                                      tooltip: 'تسعير مخصص للمخازن والفروع',
                                      onPressed: () => _showWarehousePricingDialog(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.brandPrimary),
                                      tooltip: 'تعديل الصنف والأسعار',
                                      onPressed: () => _showEditProductDialog(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                      tooltip: 'حذف / تعطيل الصنف',
                                      onPressed: () => _showDeleteProductDialog(p),
                                    ),
                                  ],
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
