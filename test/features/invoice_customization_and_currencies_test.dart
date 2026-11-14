import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/printing/printer_service.dart';
import 'package:alfa_soft/core/printing/pdf_invoice_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late PrinterService printerService;

  setUp(() {
    db = DatabaseService.inMemory();
    printerService = PrinterService(db);
  });

  tearDown(() {
    db.dispose();
  });

  group('1. اختبارات إعدادات تخصيص الفاتورة واللغات والعملات (PrinterService)', () {
    test('تخزين واسترجاع خيارات لغة الفاتورة (AR, EN, BILINGUAL)', () {
      expect(printerService.getInvoiceLanguage(), equals('AR'));

      printerService.setInvoiceLanguage('EN');
      expect(printerService.getInvoiceLanguage(), equals('EN'));

      printerService.setInvoiceLanguage('BILINGUAL');
      expect(printerService.getInvoiceLanguage(), equals('BILINGUAL'));
    });

    test('تخزين واسترجاع العملات المتعددة وأسعار الصرف (SAR, USD, YER)', () {
      expect(printerService.getDefaultCurrency(), equals('SAR'));
      expect(printerService.getExchangeRate('SAR'), equals(1.0));
      expect(printerService.getExchangeRate('USD'), equals(3.75));
      expect(printerService.getExchangeRate('YER'), equals(0.007));

      printerService.setDefaultCurrency('USD');
      expect(printerService.getDefaultCurrency(), equals('USD'));

      printerService.setExchangeRate('USD', 3.80);
      expect(printerService.getExchangeRate('USD'), equals(3.80));

      printerService.setExchangeRate('YER', 0.0075);
      expect(printerService.getExchangeRate('YER'), equals(0.0075));
    });

    test('تخزين واسترجاع خيارات عناصر الفاتورة والترويسة والتذييل', () {
      expect(printerService.isShowZatcaQr(), isTrue);
      expect(printerService.isShow1DBarcode(), isTrue);
      expect(printerService.isShowCashierName(), isTrue);
      expect(printerService.isShowTaxBreakdown(), isTrue);

      printerService.setShow1DBarcode(false);
      expect(printerService.isShow1DBarcode(), isFalse);

      printerService.setShowCashierName(false);
      expect(printerService.isShowCashierName(), isFalse);

      printerService.setShowTaxBreakdown(false);
      expect(printerService.isShowTaxBreakdown(), isFalse);

      printerService.setReceiptHeader('مؤسسة ألفا للتجارة');
      expect(printerService.getReceiptHeader(), equals('مؤسسة ألفا للتجارة'));

      printerService.setReceiptFooter('سياسة الاستبدال خلال 7 أيام');
      expect(printerService.getReceiptFooter(), equals('سياسة الاستبدال خلال 7 أيام'));
    });
  });

  group('2. تنسيق العملات وتوليد الفواتير (PdfInvoiceGenerator)', () {
    test('تنسيق العملات formatCurrency يدعم SAR و USD و YER بالعربية والإنجليزية', () {
      expect(PdfInvoiceGenerator.formatCurrency(150.0, 'SAR', language: 'AR'), contains('ر.س'));
      expect(PdfInvoiceGenerator.formatCurrency(150.0, 'SAR', language: 'EN'), contains('SAR'));

      expect(PdfInvoiceGenerator.formatCurrency(40.0, 'USD', language: 'AR'), contains('\$'));
      expect(PdfInvoiceGenerator.formatCurrency(40.0, 'USD', language: 'EN'), contains('\$'));

      expect(PdfInvoiceGenerator.formatCurrency(25000.0, 'YER', language: 'AR'), contains('ر.ي'));
      expect(PdfInvoiceGenerator.formatCurrency(25000.0, 'YER', language: 'EN'), contains('YER'));
    });

    test('توليد إيصال حراري عربي وإنجليزي وثنائي اللغة بنجاح مع الباركود والعملات المختلفة', () async {
      final headerAr = InvoiceHeaderDto(
        companyName: 'شركة تجريبية',
        taxNumber: '300000000000003',
        crNumber: '1010000000',
        branchName: 'الفرع الرئيسي',
        invoiceNumber: 'INV-2026-001',
        invoiceDate: DateTime.now(),
        customerName: 'عميل نقدي',
        cashierName: 'أحمد الكاشير',
        subtotal: 100.0,
        taxTotal: 15.0,
        grandTotal: 115.0,
        paymentMethod: 'نقداً',
        currencyCode: 'SAR',
        language: 'AR',
        show1DBarcode: true,
        showCashierName: true,
        showTaxBreakdown: true,
        showZatcaQr: true,
        customHeader: 'أهلاً بكم',
        customFooter: 'شكراً لزيارتكم',
      );

      final items = [
        const InvoiceItemDto(
          productName: 'حليب نادك 1 لتر',
          sku: '6281000123456',
          quantity: 2,
          unitName: 'حبة',
          unitPrice: 50.0,
          taxAmount: 7.5,
          lineTotal: 57.5,
        ),
      ];

      // 1. Arabic Receipt
      final pdfBytesAr = await PdfInvoiceGenerator.generateThermalReceipt(
        header: headerAr,
        items: items,
        is80mm: true,
        copyLabel: 'نسخة العميل',
      );
      expect(pdfBytesAr, isNotEmpty);
      expect(pdfBytesAr.length, greaterThan(1000));

      // 2. English Receipt with USD
      final headerEn = headerAr.copyWith(
        language: 'EN',
        currencyCode: 'USD',
        companyName: 'Alfa Soft International',
        customerName: 'Walk-in Customer',
        cashierName: 'John Cashier',
      );
      final pdfBytesEn = await PdfInvoiceGenerator.generateThermalReceipt(
        header: headerEn,
        items: items,
        is80mm: true,
        copyLabel: 'Store Copy',
      );
      expect(pdfBytesEn, isNotEmpty);
      expect(pdfBytesEn.length, greaterThan(1000));

      // 3. Bilingual Receipt with YER
      final headerBi = headerAr.copyWith(
        language: 'BILINGUAL',
        currencyCode: 'YER',
      );
      final pdfBytesBi = await PdfInvoiceGenerator.generateThermalReceipt(
        header: headerBi,
        items: items,
        is80mm: true,
      );
      expect(pdfBytesBi, isNotEmpty);
      expect(pdfBytesBi.length, greaterThan(1000));
    });
  });
}
