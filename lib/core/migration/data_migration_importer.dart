import 'package:uuid/uuid.dart';
import '../../data/local/database_service.dart';
import '../sync/outbox_manager.dart';
import 'csv_migration_parser.dart';

enum MigrationEntityType {
  products('منتجات وأصناف ومخزون افتتاحي'),
  customers('عملاء وأرصدة افتتاحية'),
  suppliers('موردون وأرصدة افتتاحية'),
  chartOfAccounts('شجرة ودليل الحسابات');

  final String label;
  const MigrationEntityType(this.label);
}

class ValidationError {
  final int rowIndex;
  final String field;
  final String message;

  const ValidationError({
    required this.rowIndex,
    required this.field,
    required this.message,
  });
}

class MigrationValidationResult {
  final int totalRows;
  final int validRowsCount;
  final List<ValidationError> errors;
  final List<Map<String, dynamic>> preparedRecords;

  const MigrationValidationResult({
    required this.totalRows,
    required this.validRowsCount,
    required this.errors,
    required this.preparedRecords,
  });

  bool get isValid => errors.isEmpty;
}

class MigrationImportResult {
  final int importedCount;
  final bool success;
  final String? errorMessage;

  const MigrationImportResult({
    required this.importedCount,
    required this.success,
    this.errorMessage,
  });
}

/// Data Migration & Import Pipeline with Dry-Run Validation and Transactional Execution
class DataMigrationImporter {
  final DatabaseService _db;
  final OutboxManager _outbox;

  DataMigrationImporter(this._db, [OutboxManager? outbox])
      : _outbox = outbox ?? OutboxManager(_db);

  /// Validates raw parsed CSV data against entity mapping before importing
  MigrationValidationResult validate({
    required MigrationEntityType entityType,
    required ParsedCsvData csvData,
    required Map<String, String> fieldMappings, // e.g. {'sku': 'كود الصنف', 'name_ar': 'اسم المنتج'}
    required String companyId,
  }) {
    final List<ValidationError> errors = [];
    final List<Map<String, dynamic>> prepared = [];

    final existingCodes = _loadExistingCodes(entityType, companyId);
    final seenCodesInFile = <String>{};

    for (int i = 0; i < csvData.rows.length; i++) {
      final row = csvData.rows[i];
      final rowMap = <String, String>{};

      for (int c = 0; c < csvData.headers.length; c++) {
        rowMap[csvData.headers[c]] = row[c];
      }

      final record = <String, dynamic>{};
      bool hasRowError = false;

      // Extract values according to mappings
      fieldMappings.forEach((targetField, sourceHeader) {
        final val = rowMap[sourceHeader]?.trim() ?? '';
        record[targetField] = val;
      });

      // Business validation per entity type
      if (entityType == MigrationEntityType.products) {
        final sku = record['sku']?.toString() ?? '';
        final nameAr = record['name_ar']?.toString() ?? '';
        final salePriceStr = record['sale_price']?.toString() ?? '0';
        final costPriceStr = record['cost_price']?.toString() ?? '0';

        if (sku.isEmpty) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'sku', message: 'كود الصنف (SKU) مطلوب ولا يمكن أن يكون فارغاً'));
          hasRowError = true;
        } else if (existingCodes.contains(sku)) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'sku', message: 'كود الصنف ($sku) مسجل مسبقاً في قاعدة البيانات'));
          hasRowError = true;
        } else if (seenCodesInFile.contains(sku)) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'sku', message: 'كود الصنف ($sku) مكرر في نفس ملف الاستيراد'));
          hasRowError = true;
        } else {
          seenCodesInFile.add(sku);
        }

        if (nameAr.isEmpty) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'name_ar', message: 'اسم الصنف بالعربية مطلوب'));
          hasRowError = true;
        }

        final salePrice = double.tryParse(salePriceStr);
        final costPrice = double.tryParse(costPriceStr);

        if (salePrice == null || salePrice < 0) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'sale_price', message: 'سعر البيع يجب أن يكون رقماً موجباً'));
          hasRowError = true;
        }
        if (costPrice == null || costPrice < 0) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'cost_price', message: 'سعر التكلفة يجب أن يكون رقماً موجباً'));
          hasRowError = true;
        }

        if (!hasRowError) {
          record['sale_price_cents'] = ((salePrice ?? 0) * 100).round();
          record['cost_price_cents'] = ((costPrice ?? 0) * 100).round();
          record['initial_qty'] = int.tryParse(record['initial_quantity']?.toString() ?? '0') ?? 0;
          prepared.add(record);
        }
      } else if (entityType == MigrationEntityType.customers || entityType == MigrationEntityType.suppliers) {
        final code = record['code']?.toString() ?? '';
        final name = record['name']?.toString() ?? '';

        if (code.isEmpty) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'code', message: 'كود الشريك مطلوب'));
          hasRowError = true;
        } else if (existingCodes.contains(code) || seenCodesInFile.contains(code)) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'code', message: 'كود الشريك ($code) مكرر'));
          hasRowError = true;
        } else {
          seenCodesInFile.add(code);
        }

        if (name.isEmpty) {
          errors.add(ValidationError(rowIndex: i + 1, field: 'name', message: 'اسم الشريك مطلوب'));
          hasRowError = true;
        }

        if (!hasRowError) {
          final balance = double.tryParse(record['current_balance']?.toString() ?? '0') ?? 0;
          record['current_balance_cents'] = (balance * 100).round();
          prepared.add(record);
        }
      } else {
        if (!hasRowError) prepared.add(record);
      }
    }

    return MigrationValidationResult(
      totalRows: csvData.rows.length,
      validRowsCount: prepared.length,
      errors: errors,
      preparedRecords: prepared,
    );
  }

  Set<String> _loadExistingCodes(MigrationEntityType entityType, String companyId) {
    if (entityType == MigrationEntityType.products) {
      final res = _db.select('SELECT sku FROM products WHERE company_id = ?', [companyId]);
      return res.map((r) => r['sku'] as String).toSet();
    } else if (entityType == MigrationEntityType.customers) {
      final res = _db.select('SELECT code FROM customers WHERE company_id = ?', [companyId]);
      return res.map((r) => r['code'] as String).toSet();
    } else if (entityType == MigrationEntityType.suppliers) {
      final res = _db.select('SELECT code FROM suppliers WHERE company_id = ?', [companyId]);
      return res.map((r) => r['code'] as String).toSet();
    } else {
      final res = _db.select('SELECT code FROM chart_of_accounts WHERE company_id = ?', [companyId]);
      return res.map((r) => r['code'] as String).toSet();
    }
  }

  /// Executes atomic batch import inside a single database transaction
  MigrationImportResult executeImport({
    required MigrationEntityType entityType,
    required List<Map<String, dynamic>> validatedRecords,
    required String companyId,
    String? warehouseId,
    String? userId,
  }) {
    if (validatedRecords.isEmpty) {
      return const MigrationImportResult(importedCount: 0, success: true);
    }

    const uuid = Uuid();

    try {
      _db.transaction((tx) {
        if (entityType == MigrationEntityType.products) {
          // Ensure default unit exists
          final unitCheck = tx.select('SELECT id FROM units WHERE company_id = ? LIMIT 1', [companyId]);
          final unitId = unitCheck.isNotEmpty ? unitCheck.first['id'] as String : 'unit_pcs';

          for (final item in validatedRecords) {
            final productId = 'prod_${uuid.v4()}';
            final sku = item['sku'] as String;
            final barcode = item['barcode']?.toString().isNotEmpty == true ? item['barcode'] as String : sku;
            final nameAr = item['name_ar'] as String;
            final saleCents = item['sale_price_cents'] as int;
            final costCents = item['cost_price_cents'] as int;
            final initialQty = item['initial_qty'] as int? ?? 0;

            tx.execute('''
              INSERT INTO products (
                id, company_id, base_unit_id, sku, barcode, name_ar,
                sale_price, cost_price, is_active, version
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)
            ''', [
              productId,
              companyId,
              unitId,
              sku,
              barcode,
              nameAr,
              saleCents,
              costCents,
            ]);

            // If initial stock quantity provided, initialize inventory balance
            if (initialQty > 0 && warehouseId != null) {
              tx.execute('''
                INSERT INTO inventory_balances (warehouse_id, product_id, quantity, average_cost, updated_at)
                VALUES (?, ?, ?, ?, datetime('now'))
              ''', [warehouseId, productId, initialQty, costCents]);

              tx.execute('''
                INSERT INTO inventory_movements (
                  id, company_id, warehouse_id, product_id, movement_type,
                  quantity, unit_cost, total_cost, reference_document_type,
                  reference_document_id, created_by_user_id
                ) VALUES (?, ?, ?, ?, 'OPENING_BALANCE', ?, ?, ?, 'MIGRATION', 'MIGRATION_INIT', ?)
              ''', [
                'mov_${uuid.v4()}',
                companyId,
                warehouseId,
                productId,
                initialQty,
                costCents,
                initialQty * costCents,
                userId ?? 'SYSTEM',
              ]);
            }

            // Enqueue outbox change
            _outbox.enqueue(
              entityType: 'PRODUCT',
              entityId: productId,
              operation: SyncOperation.create,
              payload: {
                'id': productId,
                'sku': sku,
                'name_ar': nameAr,
                'sale_price': saleCents,
                'cost_price': costCents,
                'version': 1,
              },
            );
          }
        } else if (entityType == MigrationEntityType.customers) {
          for (final item in validatedRecords) {
            final custId = 'cust_${uuid.v4()}';
            final code = item['code'] as String;
            final name = item['name'] as String;
            final phone = item['phone'] as String?;
            final taxNo = item['tax_number'] as String?;
            final balance = item['current_balance_cents'] as int? ?? 0;

            tx.execute('''
              INSERT INTO customers (
                id, company_id, code, name, phone, tax_number, current_balance, is_active
              ) VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ''', [custId, companyId, code, name, phone, taxNo, balance]);

            _outbox.enqueue(
              entityType: 'CUSTOMER',
              entityId: custId,
              operation: SyncOperation.create,
              payload: {'id': custId, 'code': code, 'name': name, 'balance': balance},
            );
          }
        } else if (entityType == MigrationEntityType.suppliers) {
          for (final item in validatedRecords) {
            final suppId = 'supp_${uuid.v4()}';
            final code = item['code'] as String;
            final name = item['name'] as String;
            final phone = item['phone'] as String?;
            final taxNo = item['tax_number'] as String?;
            final balance = item['current_balance_cents'] as int? ?? 0;

            tx.execute('''
              INSERT INTO suppliers (
                id, company_id, code, name, phone, tax_number, current_balance, is_active
              ) VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ''', [suppId, companyId, code, name, phone, taxNo, balance]);

            _outbox.enqueue(
              entityType: 'SUPPLIER',
              entityId: suppId,
              operation: SyncOperation.create,
              payload: {'id': suppId, 'code': code, 'name': name, 'balance': balance},
            );
          }
        }
      });

      return MigrationImportResult(
        importedCount: validatedRecords.length,
        success: true,
      );
    } catch (e) {
      return MigrationImportResult(
        importedCount: 0,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}
