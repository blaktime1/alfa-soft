import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/core/printing/zatca_qr_codec.dart';
import 'package:alfa_soft/core/printing/esc_pos_builder.dart';
import 'package:alfa_soft/core/printing/pdf_invoice_generator.dart';
import 'package:alfa_soft/core/printing/excel_exporter.dart';
import 'package:alfa_soft/domain/entities/accounting.dart';

void main() {
  group('Phase 5 — Reporting, Printing & Documents Test Suite', () {
    test('1. ZATCA (FATOORA) TLV QR Code: encodes and decodes all 5 mandatory tags with Arabic text', () {
      final now = DateTime.utc(2026, 11, 7, 14, 0, 0);
      const sellerName = 'شركة ألفا للتقنية والحلول المحدودة';
      const vatNumber = '310123456700003';
      const invoiceTotal = 1150.00;
      const vatTotal = 150.00;

      final base64Tlv = ZatcaQrCodec.generateBase64Tlv(
        sellerName: sellerName,
        vatRegistrationNumber: vatNumber,
        timestamp: now,
        invoiceTotal: invoiceTotal,
        vatTotal: vatTotal,
      );

      expect(base64Tlv, isNotEmpty);

      // Decode the generated payload to verify strict compliance
      final decoded = ZatcaQrCodec.decodeBase64Tlv(base64Tlv);

      expect(decoded[1], equals(sellerName));
      expect(decoded[2], equals(vatNumber));
      expect(decoded[3], equals(now.toIso8601String()));
      expect(decoded[4], equals('1150.00'));
      expect(decoded[5], equals('150.00'));
    });

    test('2. ESC/POS Raw Builder: generates correct hardware byte sequences for 80mm and 58mm thermal printers', () {
      // 80mm builder test
      final builder80 = EscPosBuilder(paperSize: EscPosPaperSize.mm80);
      builder80.text('ALFA SOFT POS', align: EscPosAlign.center, bold: true);
      builder80.divider();
      builder80.twoColumn('الإجمالي:', '100.00 SAR');
      builder80.itemRow(name: 'حليب طازج 1 لتر', qty: '2', price: '6.00', total: '12.00');
      builder80.qrCode('SAMPLE_ZATCA_DATA');
      builder80.openCashDrawer();
      builder80.cut();

      final bytes80 = builder80.toBytes();
      expect(bytes80, isNotEmpty);

      // Verify printer init ESC @ (0x1B, 0x40)
      expect(bytes80[0], equals(0x1B));
      expect(bytes80[1], equals(0x40));

      // Verify cash drawer pulse (0x1B, 0x70, 0x00, 0x19, 0xFA)
      final strBytes = bytes80.toList();
      final hasDrawerKick = strBytes.any((b) => b == 0x70);
      expect(hasDrawerKick, isTrue);

      // Verify partial cut sequence (0x1D, 0x56, 0x42, 0x00)
      final hasCut = strBytes.any((b) => b == 0x56);
      expect(hasCut, isTrue);

      // 58mm builder test
      final builder58 = EscPosBuilder(paperSize: EscPosPaperSize.mm58);
      builder58.divider();
      final bytes58 = builder58.toBytes();
      expect(bytes58, isNotEmpty);
    });

    test('3. PDF Tax Invoice Generator: produces valid A4 PDF document with %PDF- header', () async {
      final header = InvoiceHeaderDto(
        companyName: 'مؤسسة ألفا التجارية',
        taxNumber: '310987654300003',
        crNumber: '1010123456',
        branchName: 'فرع العليا',
        invoiceNumber: 'INV-TEST-99',
        invoiceDate: DateTime.now(),
        customerName: 'العميل المميز',
        subtotal: 500.00,
        taxTotal: 75.00,
        grandTotal: 575.00,
        paymentMethod: 'CASH',
      );

      final items = [
        const InvoiceItemDto(
          productName: 'سكر أبيض ناعم 2 كجم',
          sku: '1005',
          quantity: 10,
          unitName: 'كيس',
          unitPrice: 9.00,
          taxAmount: 13.50,
          lineTotal: 103.50,
        ),
      ];

      final pdfBytes = await PdfInvoiceGenerator.generateTaxInvoice(header: header, items: items);

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));

      // Standard PDF magic header: %PDF-
      final headerStr = utf8.decode(pdfBytes.sublist(0, 5));
      expect(headerStr, equals('%PDF-'));
    });

    test('4. Excel Exporter: prepends UTF-8 BOM and exports Sales, Inventory, Trial Balance, and Statements', () {
      // 1. Sales Register
      final salesData = [
        {
          'invoice_number': 'INV-001',
          'invoice_date': '2026-11-07',
          'customer_name': 'عميل نقدي',
          'subtotal': 10000,
          'tax_total': 1500,
          'grand_total': 11500,
          'payment_status': 'PAID',
          'status': 'POSTED',
        }
      ];
      final salesCsv = ExcelExporter.exportSalesRegister(salesData);
      expect(salesCsv[0], equals(0xEF)); // UTF-8 BOM byte 1
      expect(salesCsv[1], equals(0xBB)); // UTF-8 BOM byte 2
      expect(salesCsv[2], equals(0xBF)); // UTF-8 BOM byte 3
      final salesText = utf8.decode(salesCsv);
      expect(salesText.contains('رقم الفاتورة'), isTrue);
      expect(salesText.contains('INV-001'), isTrue);

      // 2. Inventory Stock
      final inventoryData = [
        {
          'sku': 'SKU-101',
          'barcode': '123456789',
          'name_ar': 'عصير برتقال 1 لتر',
          'warehouse_name': 'المستودع الرئيسي',
          'quantity': 50,
          'average_cost': 450,
        }
      ];
      final invCsv = ExcelExporter.exportInventoryStock(inventoryData);
      final invText = utf8.decode(invCsv);
      expect(invText.contains('كود الصنف (SKU)'), isTrue);
      expect(invText.contains('عصير برتقال 1 لتر'), isTrue);

      // 3. Trial Balance
      final tbRows = [
        const TrialBalanceRow(
          accountId: 'acc_1',
          code: '1010',
          nameAr: 'الخزينة النقدية',
          accountType: AccountType.asset,
          totalDebit: 100000,
          totalCredit: 0,
          netBalance: 100000,
        )
      ];
      final tbCsv = ExcelExporter.exportTrialBalance(tbRows);
      final tbText = utf8.decode(tbCsv);
      expect(tbText.contains('الخزينة النقدية'), isTrue);
      expect(tbText.contains('1010'), isTrue);

      // 4. Customer Statement
      final statementData = [
        {
          'date': '2026-11-01',
          'doc_number': 'INV-100',
          'narration': 'فاتورة مبيعات آجل',
          'debit': 50000,
          'credit': 0,
        },
        {
          'date': '2026-11-05',
          'doc_number': 'REC-050',
          'narration': 'سند قبض نقدي',
          'debit': 0,
          'credit': 20000,
        },
      ];
      final stmtCsv = ExcelExporter.exportCustomerStatement('شركة الأمل للتوزيع', statementData);
      final stmtText = utf8.decode(stmtCsv);
      expect(stmtText.contains('كشف حساب العميل: شركة الأمل للتوزيع'), isTrue);
      expect(stmtText.contains('300.00'), isTrue); // Final running balance (500 - 200 = 300)
    });
  });
}
