import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/printing/printer_service.dart';
import 'package:alfa_soft/core/printing/pdf_invoice_generator.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';

void main() {
  late DatabaseService db;
  late PrinterService printerService;
  late CatalogRepository catalogRepo;

  setUp(() {
    db = DatabaseService.inMemory();
    printerService = PrinterService(db);
    catalogRepo = CatalogRepository(db);

    db.execute('''
      INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code)
      VALUES ('comp_print_test', 'شركة الطباعة والوحدات', 'الفا سوفت', '300000000000003', 'SAR');
    ''');
  });

  tearDown(() {
    db.dispose();
  });

  group('1. إصلاح استعلام عميل الكاشير النقدي (WALK_IN Query Bug Fix)', () {
    test('استعلام عميل الكاشير ينجح دون استثناء SqliteException', () {
      final compRows = db.select('SELECT id FROM companies LIMIT 1');
      final companyId = compRows.first['id'] as String;

      // Ensure no crash when querying with bound parameter
      final custCheck = db.select(
        'SELECT id FROM customers WHERE company_id = ? AND code = ?',
        [companyId, 'WALK_IN'],
      );
      expect(custCheck, isEmpty);

      // Insert customer
      db.execute('''
        INSERT INTO customers (id, company_id, code, name, is_active)
        VALUES ('cust_walk_in', ?, 'WALK_IN', 'عميل نقدي عابر', 1)
      ''', [companyId]);

      final resolved = db.select(
        'SELECT id FROM customers WHERE company_id = ? AND code = ?',
        [companyId, 'WALK_IN'],
      );
      expect(resolved.isNotEmpty, isTrue);
      expect(resolved.first['id'], 'cust_walk_in');
    });
  });

  group('2. إدارة إعدادات الطابعات والنسخ المزدوجة (PrinterService)', () {
    test('حفظ واسترجاع اسم الطابعة المحددة والتفضيلات', () {
      expect(printerService.getSelectedPrinter(), isNull);
      expect(printerService.isAutoPrintEnabled(), isTrue);
      expect(printerService.isCustomerCopyEnabled(), isTrue);
      expect(printerService.isCashierCopyEnabled(), isFalse);

      // Set printer name
      printerService.setSelectedPrinter('XP-80C Thermal Printer');
      expect(printerService.getSelectedPrinter(), 'XP-80C Thermal Printer');

      // Toggle copies
      printerService.setCashierCopyEnabled(true);
      expect(printerService.isCashierCopyEnabled(), isTrue);

      printerService.setCustomerCopyEnabled(false);
      expect(printerService.isCustomerCopyEnabled(), isFalse);

      printerService.setAutoPrintEnabled(false);
      expect(printerService.isAutoPrintEnabled(), isFalse);

      printerService.setPaperSize('58mm');
      expect(printerService.getPaperSize(), '58mm');
    });

    test('توليد الإيصال الحراري مع وسم نسخة العميل ونسخة الكاشير', () async {
      final header = InvoiceHeaderDto(
        companyName: 'سوبرماركت النخبة',
        taxNumber: '300000000000003',
        crNumber: '1010000000',
        branchName: 'فرع العليا',
        invoiceNumber: 'INV-99001',
        invoiceDate: DateTime.now(),
        customerName: 'عميل نقدي عابر',
        subtotal: 100.0,
        taxTotal: 15.0,
        grandTotal: 115.0,
        paymentMethod: 'CASH',
      );

      final items = [
        const InvoiceItemDto(
          productName: 'أرز هندي بسمتي',
          sku: 'RICE-5K',
          quantity: 2,
          unitName: 'كيس',
          unitPrice: 50.0,
          taxAmount: 7.5,
          lineTotal: 57.5,
        ),
      ];

      // Customer Copy receipt
      final customerBytes = await PdfInvoiceGenerator.generateThermalReceipt(
        header: header,
        items: items,
        copyLabel: 'نسخة العميل — Customer Copy',
        is80mm: true,
      );
      expect(customerBytes, isNotEmpty);

      // Cashier / Store Copy receipt
      final cashierBytes = await PdfInvoiceGenerator.generateThermalReceipt(
        header: header,
        items: items,
        copyLabel: 'نسخة الكاشير / المحل — Store Copy',
        is80mm: false,
      );
      expect(cashierBytes, isNotEmpty);
    });
  });

  group('3. إدارة وحدات القياس والبيع وتفعيلها (Units Management)', () {
    test('توليد الوحدات القياسية تلقائياً (حبة، كرتون، كيلو، لتر، درزن، باكت، كيس...)', () {
      final units = catalogRepo.getUnits('comp_print_test');
      final codes = units.map((u) => u.code).toSet();

      expect(codes, containsAll(['PCS', 'CTN', 'KG', 'G', 'L', 'DZN', 'BAG', 'PCK', 'M']));
      expect(units.any((u) => u.name == 'كرتون جملة'), isTrue);
      expect(units.any((u) => u.name == 'كيلو جرام (كجم)'), isTrue);
    });

    test('إضافة وتعديل وحذف وحدة قياس مخصصة', () {
      // 1. Create unit
      final newUnit = catalogRepo.createUnit(
        companyId: 'comp_print_test',
        code: 'BOX',
        name: 'صندوق خشبي',
      );
      expect(newUnit.code, 'BOX');

      // 2. Update unit
      catalogRepo.updateUnit(
        id: newUnit.id,
        code: 'BOX-XL',
        name: 'صندوق خشبي كبير',
      );
      final updatedList = catalogRepo.getUnits('comp_print_test');
      final updatedUnit = updatedList.firstWhere((u) => u.id == newUnit.id);
      expect(updatedUnit.code, 'BOX-XL');
      expect(updatedUnit.name, 'صندوق خشبي كبير');

      // 3. Delete unit
      catalogRepo.deleteUnit(newUnit.id);
      final afterDelete = catalogRepo.getUnits('comp_print_test');
      expect(afterDelete.any((u) => u.id == newUnit.id), isFalse);
    });

    test('منع حذف الوحدة إذا كانت مستخدمة في أصناف مسجلة', () {
      final kgUnit = catalogRepo.getUnits('comp_print_test').firstWhere((u) => u.code == 'KG');

      // Create product using KG as base unit
      catalogRepo.createProduct(
        companyId: 'comp_print_test',
        baseUnitId: kgUnit.id,
        sku: 'SUGAR-RAW',
        nameAr: 'سكر سائب بالكيلو',
        salePriceCents: 500,
      );

      // Attempt deletion must throw ArgumentError
      expect(
        () => catalogRepo.deleteUnit(kgUnit.id),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
