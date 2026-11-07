import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/sync/outbox_manager.dart';
import 'package:alfa_soft/core/migration/csv_migration_parser.dart';
import 'package:alfa_soft/core/migration/data_migration_importer.dart';

void main() {
  late DatabaseService db;
  late OutboxManager outbox;
  late DataMigrationImporter importer;

  const testCompanyId = 'comp_mig_test';
  const testWarehouseId = 'wh_mig_test';

  setUp(() {
    db = DatabaseService.inMemory();
    outbox = OutboxManager(db);
    importer = DataMigrationImporter(db, outbox);

    db.execute("INSERT INTO companies (id, legal_name, trade_name) VALUES (?, 'شركة الاستيراد التجريبية', 'الفا سوفت')", [testCompanyId]);
    db.execute("INSERT INTO units (id, company_id, code, name) VALUES ('unit_pcs', ?, 'PCS', 'حبة')", [testCompanyId]);
    db.execute("INSERT INTO branches (id, company_id, code, name) VALUES ('br_1', ?, 'BR01', 'الفرع الرئيسي')", [testCompanyId]);
    db.execute("INSERT INTO warehouses (id, branch_id, code, name) VALUES (?, 'br_1', 'WH01', 'المستودع الرئيسي')", [testWarehouseId]);
  });

  tearDown(() {
    db.dispose();
  });

  group('Phase 7 — Data Import & Migration Center Test Suite', () {
    test('1. CSV Parser: handles commas, semicolons, tabs, quotes, and UTF-8 BOM', () {
      // 1. Standard comma CSV with quotes and BOM
      const commaCsv = '\uFEFF"كود الصنف",اسم الصنف,السعر\n1001,"شاي أحمر، فرط",14.50\n1002,سكر أبيض,9.00';
      final parsedComma = CsvMigrationParser.parse(commaCsv);
      expect(parsedComma.headers.length, equals(3));
      expect(parsedComma.rows.length, equals(2));
      expect(parsedComma.rows[0][1], equals('شاي أحمر، فرط')); // preserved embedded comma inside quotes
      expect(parsedComma.delimiter, equals(','));

      // 2. Semicolon-delimited CSV
      const semicolonCsv = 'Code;Name;Price\nP1;Milk;6.00\nP2;Bread;2.50';
      final parsedSemi = CsvMigrationParser.parse(semicolonCsv);
      expect(parsedSemi.delimiter, equals(';'));
      expect(parsedSemi.rows.length, equals(2));
      expect(parsedSemi.rows[0][0], equals('P1'));

      // 3. Tab-delimited TSV
      const tsv = 'SKU\tName\tQty\n101\tWater\t100';
      final parsedTsv = CsvMigrationParser.parse(tsv);
      expect(parsedTsv.delimiter, equals('\t'));
      expect(parsedTsv.rows.length, equals(1));
    });

    test('2. Dry-Run Validation: catches missing SKUs, invalid prices, and duplicate keys', () {
      // Seed existing product in database
      db.execute('''
        INSERT INTO products (id, company_id, base_unit_id, sku, barcode, name_ar, sale_price, cost_price)
        VALUES ('p_existing', ?, 'unit_pcs', 'SKU-DUPLICATE', 'SKU-DUPLICATE', 'صنف مسجل مسبقاً', 1000, 800)
      ''', [testCompanyId]);

      const testCsv = '''
كود الصنف,اسم الصنف,سعر البيع,سعر التكلفة,الكمية الافتتاحية
,صنف بدون كود,10.00,8.00,5
SKU-DUPLICATE,صنف مكرر مع قاعدة البيانات,20.00,15.00,10
SKU-99,صنف بسعر بيع سالب,-5.00,4.00,0
SKU-SAME,صنف مكرر 1,30.00,20.00,10
SKU-SAME,صنف مكرر 2,30.00,20.00,10
SKU-VALID,صنف صحيح 100%,25.00,18.00,50
''';

      final parsed = CsvMigrationParser.parse(testCsv);
      final validation = importer.validate(
        entityType: MigrationEntityType.products,
        csvData: parsed,
        fieldMappings: {
          'sku': 'كود الصنف',
          'name_ar': 'اسم الصنف',
          'sale_price': 'سعر البيع',
          'cost_price': 'سعر التكلفة',
          'initial_quantity': 'الكمية الافتتاحية',
        },
        companyId: testCompanyId,
      );

      expect(validation.isValid, isFalse);
      expect(validation.totalRows, equals(6));
      expect(validation.validRowsCount, equals(2)); // Row 4 (first SKU-SAME) and Row 6 (SKU-VALID)
      expect(validation.errors.length, greaterThanOrEqualTo(4));

      // Assert error contents
      expect(validation.errors.any((e) => e.rowIndex == 1 && e.field == 'sku'), isTrue); // Empty SKU
      expect(validation.errors.any((e) => e.rowIndex == 2 && e.message.contains('مسجل مسبقاً')), isTrue); // DB Duplicate
      expect(validation.errors.any((e) => e.rowIndex == 3 && e.field == 'sale_price'), isTrue); // Negative price
      expect(validation.errors.any((e) => e.rowIndex == 5 && e.message.contains('مكرر في نفس ملف')), isTrue); // In-file duplicate
    });

    test('3. Atomic Batch Import: inserts products, initializes opening stock, and triggers sync outbox', () {
      const validCsv = '''
كود,اسم,بيع,تكلفة,كمية
SKU-1001,أرز بسمتي فاخر,45.00,38.00,100
SKU-1002,زيت نباتي نقي,18.00,14.50,50
SKU-1003,حليب طازج نقي,6.00,4.50,80
''';

      final parsed = CsvMigrationParser.parse(validCsv);
      final validation = importer.validate(
        entityType: MigrationEntityType.products,
        csvData: parsed,
        fieldMappings: {
          'sku': 'كود',
          'name_ar': 'اسم',
          'sale_price': 'بيع',
          'cost_price': 'تكلفة',
          'initial_quantity': 'كمية',
        },
        companyId: testCompanyId,
      );

      expect(validation.isValid, isTrue);
      expect(validation.preparedRecords.length, equals(3));

      // Execute actual transactional import
      final importResult = importer.executeImport(
        entityType: MigrationEntityType.products,
        validatedRecords: validation.preparedRecords,
        companyId: testCompanyId,
        warehouseId: testWarehouseId,
        userId: 'admin_user',
      );

      expect(importResult.success, isTrue);
      expect(importResult.importedCount, equals(3));

      // Assert products table has records with correct cents
      final products = db.select('SELECT * FROM products WHERE company_id = ? ORDER BY sku ASC', [testCompanyId]);
      expect(products.length, equals(3));
      expect(products[0]['sku'], equals('SKU-1001'));
      expect(products[0]['sale_price'], equals(4500)); // 45.00 SAR in cents
      expect(products[0]['cost_price'], equals(3800)); // 38.00 SAR in cents

      // Assert opening inventory balances and movements
      final balances = db.select('SELECT * FROM inventory_balances WHERE warehouse_id = ?', [testWarehouseId]);
      expect(balances.length, equals(3));
      expect(balances.any((b) => b['quantity'] == 100), isTrue);

      final movements = db.select('SELECT * FROM inventory_movements WHERE movement_type = "OPENING_BALANCE"');
      expect(movements.length, equals(3));

      // Assert outbox queue items were generated for sync
      final outboxItems = outbox.getPendingBatch();
      expect(outboxItems.length, equals(3));
      expect(outboxItems.every((i) => i.entityType == 'PRODUCT'), isTrue);
    });

    test('4. Partner Migration: imports customers with opening balance and outbox events', () {
      const customerCsv = '''
Code,Name,Phone,TaxNumber,Balance
C-01,شركة النجم للتجارة,0501112233,310000000000003,1500.00
C-02,مؤسسة الفجر للمقاولات,0554445566,310111111100003,3200.50
''';

      final parsed = CsvMigrationParser.parse(customerCsv);
      final validation = importer.validate(
        entityType: MigrationEntityType.customers,
        csvData: parsed,
        fieldMappings: {
          'code': 'Code',
          'name': 'Name',
          'phone': 'Phone',
          'tax_number': 'TaxNumber',
          'current_balance': 'Balance',
        },
        companyId: testCompanyId,
      );

      expect(validation.isValid, isTrue);

      final result = importer.executeImport(
        entityType: MigrationEntityType.customers,
        validatedRecords: validation.preparedRecords,
        companyId: testCompanyId,
      );

      expect(result.success, isTrue);
      expect(result.importedCount, equals(2));

      final custs = db.select('SELECT * FROM customers WHERE company_id = ? ORDER BY code ASC', [testCompanyId]);
      expect(custs.length, equals(2));
      expect(custs[0]['code'], equals('C-01'));
      expect(custs[0]['current_balance'], equals(150000)); // 1500.00 in cents
      expect(custs[1]['current_balance'], equals(320050)); // 3200.50 in cents
    });
  });
}
