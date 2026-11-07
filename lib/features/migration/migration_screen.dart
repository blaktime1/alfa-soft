import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/migration/csv_migration_parser.dart';
import '../../core/migration/data_migration_importer.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  MigrationEntityType _selectedEntity = MigrationEntityType.products;
  final TextEditingController _csvController = TextEditingController();

  ParsedCsvData? _parsedData;
  Map<String, String> _fieldMappings = {};
  MigrationValidationResult? _validationResult;
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSampleCsv();
  }

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  void _loadSampleCsv() {
    if (_selectedEntity == MigrationEntityType.products) {
      _csvController.text = '''
كود الصنف,الباركود,اسم الصنف,سعر البيع,سعر التكلفة,الكمية الافتتاحية
1011,1011001,شاي أخضر صيني 250 جم,16.50,12.00,50
1012,1012002,قهوة عربية فاخرة 500 جم,48.00,38.00,30
1013,1013003,زبدة طبيعية 200 جم,9.50,7.20,100
1014,1014004,جبنة بيضاء كريمية 500 جم,14.00,10.50,40
'''.trim();
    } else if (_selectedEntity == MigrationEntityType.customers) {
      _csvController.text = '''
كود العميل,اسم العميل,رقم الهاتف,الرقم الضريبي,الرصيد الافتتاحي
C-101,شركة الأمل الحديثة,0501234567,310987654300003,500.00
C-102,مؤسسة النور للتوريدات,0559876543,300123456700003,1200.00
'''.trim();
    } else {
      _csvController.text = '''
كود المورد,اسم المورد,رقم الهاتف,الرقم الضريبي,الرصيد الافتتاحي
S-201,مصنع الخليج للبلاستيك,0114567890,300555555500003,3500.00
S-202,شركة الاستيراد المتحدة,0119876543,310666666600003,8200.00
'''.trim();
    }

    _parseAndAutoMap();
  }

  void _parseAndAutoMap() {
    final parsed = CsvMigrationParser.parse(_csvController.text);
    final mappings = <String, String>{};

    if (_selectedEntity == MigrationEntityType.products) {
      for (final h in parsed.headers) {
        if (h.contains('كود') || h.toLowerCase().contains('sku')) mappings['sku'] = h;
        if (h.contains('باركود') || h.toLowerCase().contains('barcode')) mappings['barcode'] = h;
        if (h.contains('اسم') || h.toLowerCase().contains('name')) mappings['name_ar'] = h;
        if (h.contains('بيع') || h.toLowerCase().contains('sale')) mappings['sale_price'] = h;
        if (h.contains('تكلفة') || h.toLowerCase().contains('cost')) mappings['cost_price'] = h;
        if (h.contains('كمية') || h.toLowerCase().contains('qty')) mappings['initial_quantity'] = h;
      }
    } else {
      for (final h in parsed.headers) {
        if (h.contains('كود') || h.toLowerCase().contains('code')) mappings['code'] = h;
        if (h.contains('اسم') || h.toLowerCase().contains('name')) mappings['name'] = h;
        if (h.contains('هاتف') || h.toLowerCase().contains('phone')) mappings['phone'] = h;
        if (h.contains('ضريب') || h.toLowerCase().contains('tax')) mappings['tax_number'] = h;
        if (h.contains('رصيد') || h.toLowerCase().contains('balance')) mappings['current_balance'] = h;
      }
    }

    setState(() {
      _parsedData = parsed;
      _fieldMappings = mappings;
      _validationResult = null;
    });
  }

  String _getCompanyId() {
    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    return compResult.isNotEmpty ? compResult.first['id'] as String : 'DEFAULT_COMPANY';
  }

  String _getWarehouseId() {
    final db = ref.read(databaseServiceProvider);
    final whResult = db.select('SELECT id FROM warehouses LIMIT 1');
    return whResult.isNotEmpty ? whResult.first['id'] as String : 'wh_main';
  }

  void _runDryRunValidation() {
    if (_parsedData == null || _parsedData!.rows.isEmpty) return;

    final db = ref.read(databaseServiceProvider);
    final importer = DataMigrationImporter(db);
    final companyId = _getCompanyId();

    final result = importer.validate(
      entityType: _selectedEntity,
      csvData: _parsedData!,
      fieldMappings: _fieldMappings,
      companyId: companyId,
    );

    setState(() {
      _validationResult = result;
      _statusMessage = result.isValid
          ? 'تم التحقق بنجاح! جميع الصفوف (${result.validRowsCount}) صالحة كلياً للاستيراد.'
          : 'تنبيه: تم العثور على ${result.errors.length} خطأ في البيانات. يرجى مراجعتها أدناه.';
    });
  }

  void _executeActualImport() {
    if (_validationResult == null || !_validationResult!.isValid) return;

    setState(() => _isProcessing = true);
    final db = ref.read(databaseServiceProvider);
    final importer = DataMigrationImporter(db);
    final companyId = _getCompanyId();
    final warehouseId = _getWarehouseId();

    final result = importer.executeImport(
      entityType: _selectedEntity,
      validatedRecords: _validationResult!.preparedRecords,
      companyId: companyId,
      warehouseId: warehouseId,
    );

    setState(() {
      _isProcessing = false;
      if (result.success) {
        _statusMessage = 'تم استيراد وتثبيت ${result.importedCount} سجل بنجاح في قاعدة البيانات المحلية!';
        _csvController.clear();
        _parsedData = null;
        _validationResult = null;
      } else {
        _statusMessage = 'فشل الاستيراد: ${result.errorMessage}';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_statusMessage!),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز استيراد وترحيل البيانات — Legacy Data Migration Center'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1: Entity Selector
            Text('الخطوة 1: اختر نوع السجلات المراد استيرادها',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<MigrationEntityType>(
              segments: [
                ButtonSegment(value: MigrationEntityType.products, label: Text(MigrationEntityType.products.label)),
                ButtonSegment(value: MigrationEntityType.customers, label: Text(MigrationEntityType.customers.label)),
                ButtonSegment(value: MigrationEntityType.suppliers, label: Text(MigrationEntityType.suppliers.label)),
              ],
              selected: {_selectedEntity},
              onSelectionChanged: (set) {
                setState(() => _selectedEntity = set.first);
                _loadSampleCsv();
              },
            ),
            const SizedBox(height: 24),

            // Step 2: CSV Data Input
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('الخطوة 2: الصق أو اكتب بيانات CSV / Excel',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _loadSampleCsv,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة تحميل النموذج الافتراضي'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _csvController,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'الصق صفوف CSV مفصولة بفواصل أو فواصل منقوطة...',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _parseAndAutoMap(),
            ),
            const SizedBox(height: 16),

            // Step 3: Column Mapping & Validation Actions
            if (_parsedData != null && _parsedData!.headers.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.table_chart_rounded, color: AppColors.brandAccent),
                          const SizedBox(width: 8),
                          Text('الخطوة 3: مطابقة الحقول التلقائية (${_parsedData!.rows.length} صفوف مكتشفة)',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: _fieldMappings.entries.map((e) {
                          return Chip(
                            backgroundColor: AppColors.brandAccent.withValues(alpha: 0.1),
                            label: Text('${e.key} ➔ ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _runDryRunValidation,
                            icon: const Icon(Icons.fact_check_rounded),
                            label: const Text('فحص واختبار صحة البيانات (Dry-Run Test)'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandAccent),
                          ),
                          const SizedBox(width: 16),
                          if (_validationResult != null && _validationResult!.isValid)
                            ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _executeActualImport,
                              icon: _isProcessing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.cloud_upload_rounded),
                              label: const Text('بدء الاستيراد الفعلي والتثبيت الذري'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Step 4: Validation Results & Error Display
            if (_validationResult != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_validationResult!.isValid ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _validationResult!.isValid ? AppColors.success : AppColors.error),
                ),
                child: Row(
                  children: [
                    Icon(
                      _validationResult!.isValid ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: _validationResult!.isValid ? AppColors.success : AppColors.error,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _validationResult!.isValid ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_validationResult!.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _validationResult!.errors.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final err = _validationResult!.errors[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.error.withValues(alpha: 0.15),
                          child: Text('${err.rowIndex}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(err.message, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                        subtitle: Text('الحقل: ${err.field} | الصف رقم ${err.rowIndex} في الملف'),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
