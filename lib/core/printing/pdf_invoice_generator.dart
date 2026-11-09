import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'zatca_qr_codec.dart';

class InvoiceItemDto {
  final String productName;
  final String sku;
  final int quantity;
  final String unitName;
  final double unitPrice;
  final double taxAmount;
  final double lineTotal;

  const InvoiceItemDto({
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitName,
    required this.unitPrice,
    required this.taxAmount,
    required this.lineTotal,
  });
}

class InvoiceHeaderDto {
  final String companyName;
  final String taxNumber;
  final String crNumber;
  final String branchName;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String customerName;
  final String? customerTaxNumber;
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final String paymentMethod;

  const InvoiceHeaderDto({
    required this.companyName,
    required this.taxNumber,
    required this.crNumber,
    required this.branchName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.customerName,
    this.customerTaxNumber,
    required this.subtotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.paymentMethod,
  });
}

/// Professional Bilingual ZATCA-compliant A4 Tax Invoice Generator
class PdfInvoiceGenerator {
  const PdfInvoiceGenerator._();

  static Future<Uint8List> generateTaxInvoice({
    required InvoiceHeaderDto header,
    required List<InvoiceItemDto> items,
  }) async {
    final pdf = pw.Document();

    // Generate ZATCA Base64 TLV QR Code
    final zatcaPayload = ZatcaQrCodec.generateBase64Tlv(
      sellerName: header.companyName,
      vatRegistrationNumber: header.taxNumber,
      timestamp: header.invoiceDate,
      invoiceTotal: header.grandTotal,
      vatTotal: header.taxTotal,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header Section: Company Info & ZATCA QR Code
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        header.companyName,
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('الفرع: ${header.branchName}', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('الرقم الضريبي (VAT): ${header.taxNumber}', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('السجل التجاري (CR): ${header.crNumber}', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: zatcaPayload,
                        width: 90,
                        height: 90,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('رمز الاستجابة السريع (فاتورة)', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1.5, color: PdfColors.blue900),
              pw.SizedBox(height: 8),

              // 2. Invoice & Customer Meta Bar
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('رقم الفاتورة: ${header.invoiceNumber}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text('التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(header.invoiceDate)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('العميل: ${header.customerName}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text('طريقة الدفع: ${header.paymentMethod}', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // 3. Line Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.6), // #
                  1: pw.FlexColumnWidth(3.0), // Description
                  2: pw.FlexColumnWidth(1.0), // Qty
                  3: pw.FlexColumnWidth(1.2), // Unit Price
                  4: pw.FlexColumnWidth(1.2), // VAT (15%)
                  5: pw.FlexColumnWidth(1.4), // Line Total
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                    children: [
                      _headerCell('#'),
                      _headerCell('الصنف والوصف (Item Description)'),
                      _headerCell('الكمية (Qty)'),
                      _headerCell('السعر (Price)'),
                      _headerCell('الضريبة (VAT)'),
                      _headerCell('الإجمالي (Total)'),
                    ],
                  ),
                  ...List.generate(items.length, (idx) {
                    final item = items[idx];
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: idx % 2 == 1 ? PdfColors.grey50 : PdfColors.white,
                      ),
                      children: [
                        _dataCell('${idx + 1}', align: pw.TextAlign.center),
                        _dataCell('${item.productName} (${item.sku})'),
                        _dataCell('${item.quantity} ${item.unitName}', align: pw.TextAlign.center),
                        _dataCell(item.unitPrice.toStringAsFixed(2), align: pw.TextAlign.right),
                        _dataCell(item.taxAmount.toStringAsFixed(2), align: pw.TextAlign.right),
                        _dataCell(item.lineTotal.toStringAsFixed(2), align: pw.TextAlign.right, isBold: true),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 16),

              // 4. Totals Summary Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 250,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.TableBorder.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      children: [
                        _summaryRow('المجموع الخاضع للضريبة:', '${header.subtotal.toStringAsFixed(2)} SAR'),
                        pw.SizedBox(height: 4),
                        _summaryRow('ضريبة القيمة المضافة (15%):', '${header.taxTotal.toStringAsFixed(2)} SAR'),
                        pw.Divider(color: PdfColors.grey300),
                        _summaryRow(
                          'المجموع الكلي النهائي:',
                          '${header.grandTotal.toStringAsFixed(2)} SAR',
                          isBold: true,
                          fontSize: 14,
                          color: PdfColors.blue900,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              // 5. Footer & ZATCA Compliance Notice
              pw.Divider(color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('فاتورة ضريبية مبسطة صادرة إلكترونياً وفق نظام هيئة الزكاة والضريبة والجمارك (ZATCA)',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text('نظام الفا سوفت — ALFA SOFT ERP',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _headerCell(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _dataCell(String text, {pw.TextAlign align = pw.TextAlign.left, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 10, PdfColor? color}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      ],
    );
  }

  /// Compact ESC/POS-compatible 80mm/58mm Thermal Receipt Generator
  static Future<Uint8List> generateThermalReceipt({
    required InvoiceHeaderDto header,
    required List<InvoiceItemDto> items,
    String copyLabel = 'نسخة العميل — Customer Copy',
    bool is80mm = true,
  }) async {
    final pdf = pw.Document();
    final pageFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;

    final zatcaPayload = ZatcaQrCodec.generateBase64Tlv(
      sellerName: header.companyName,
      vatRegistrationNumber: header.taxNumber,
      timestamp: header.invoiceDate,
      invoiceTotal: header.grandTotal,
      vatTotal: header.taxTotal,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              pw.Center(
                child: pw.Text(
                  header.companyName,
                  style: pw.TextStyle(fontSize: is80mm ? 13 : 11, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  'الفرع: ${header.branchName}',
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'الرقم الضريبي: ${header.taxNumber}',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),

              // 2. Dual-copy Badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '[ $copyLabel ]',
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.SizedBox(height: 4),

              // 3. Invoice Meta
              pw.Text('رقم الفاتورة: ${header.invoiceNumber}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('التاريخ: ${dateFormat.format(header.invoiceDate)}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('العميل: ${header.customerName}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('طريقة الدفع: ${header.paymentMethod}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

              // 4. Line Items Table
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text('الصنف', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 2, child: pw.Text('الكمية', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 2, child: pw.Text('السعر', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 2, child: pw.Text('الإجمالي', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.Divider(thickness: 0.5),

              ...items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(
                          '${item.productName} (${item.unitName})',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('${item.quantity}', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(item.unitPrice.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(item.lineTotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 5. Financial Summary
              _thermalSummaryRow('المجموع قبل الضريبة:', '${header.subtotal.toStringAsFixed(2)} SAR'),
              _thermalSummaryRow('ضريبة القيمة المضافة (15%):', '${header.taxTotal.toStringAsFixed(2)} SAR'),
              pw.Divider(thickness: 0.5),
              _thermalSummaryRow('الإجمالي النهائي:', '${header.grandTotal.toStringAsFixed(2)} SAR', isBold: true, fontSize: 9.5),
              pw.SizedBox(height: 6),

              // 6. ZATCA QR
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: zatcaPayload,
                  width: is80mm ? 70 : 55,
                  height: is80mm ? 70 : 55,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  'شكراً لزيارتكم • البضاعة المباعة تستبدل خلال 3 أيام',
                  style: const pw.TextStyle(fontSize: 6.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'نظام الفا سوفت — ALFA SOFT POS',
                  style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _thermalSummaryRow(String label, String value, {bool isBold = false, double fontSize = 7.5}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }
}
