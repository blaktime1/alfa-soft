import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  final String currencyCode;
  final String language; // 'AR', 'EN', 'BILINGUAL'
  final String? cashierName;
  final bool showLogo;
  final bool showZatcaQr;
  final bool show1DBarcode;
  final bool showCashierName;
  final bool showTaxBreakdown;
  final String? customHeader;
  final String? customFooter;
  final String? phone;
  final String? address;

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
    this.currencyCode = 'SAR',
    this.language = 'AR',
    this.cashierName,
    this.showLogo = true,
    this.showZatcaQr = true,
    this.show1DBarcode = true,
    this.showCashierName = true,
    this.showTaxBreakdown = true,
    this.customHeader,
    this.customFooter,
    this.phone,
    this.address,
  });

  InvoiceHeaderDto copyWith({
    String? companyName,
    String? taxNumber,
    String? crNumber,
    String? branchName,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? customerName,
    String? customerTaxNumber,
    double? subtotal,
    double? taxTotal,
    double? grandTotal,
    String? paymentMethod,
    String? currencyCode,
    String? language,
    String? cashierName,
    bool? showLogo,
    bool? showZatcaQr,
    bool? show1DBarcode,
    bool? showCashierName,
    bool? showTaxBreakdown,
    String? customHeader,
    String? customFooter,
    String? phone,
    String? address,
  }) {
    return InvoiceHeaderDto(
      companyName: companyName ?? this.companyName,
      taxNumber: taxNumber ?? this.taxNumber,
      crNumber: crNumber ?? this.crNumber,
      branchName: branchName ?? this.branchName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      customerName: customerName ?? this.customerName,
      customerTaxNumber: customerTaxNumber ?? this.customerTaxNumber,
      subtotal: subtotal ?? this.subtotal,
      taxTotal: taxTotal ?? this.taxTotal,
      grandTotal: grandTotal ?? this.grandTotal,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      currencyCode: currencyCode ?? this.currencyCode,
      language: language ?? this.language,
      cashierName: cashierName ?? this.cashierName,
      showLogo: showLogo ?? this.showLogo,
      showZatcaQr: showZatcaQr ?? this.showZatcaQr,
      show1DBarcode: show1DBarcode ?? this.show1DBarcode,
      showCashierName: showCashierName ?? this.showCashierName,
      showTaxBreakdown: showTaxBreakdown ?? this.showTaxBreakdown,
      customHeader: customHeader ?? this.customHeader,
      customFooter: customFooter ?? this.customFooter,
      phone: phone ?? this.phone,
      address: address ?? this.address,
    );
  }
}

/// Professional Multilingual ZATCA-compliant Tax Invoice & Thermal Receipt Generator
class PdfInvoiceGenerator {
  const PdfInvoiceGenerator._();

  static pw.Font? _cachedRegularFont;
  static pw.Font? _cachedBoldFont;

  /// Loads true Unicode Arabic font to prevent square/tofu artifacts on printers
  static Future<pw.ThemeData> getInvoiceTheme() async {
    if (_cachedRegularFont != null && _cachedBoldFont != null) {
      return pw.ThemeData.withFont(
        base: _cachedRegularFont!,
        bold: _cachedBoldFont!,
        fontFallback: [_cachedRegularFont!, _cachedBoldFont!],
      );
    }

    try {
      Uint8List? regBytes;
      Uint8List? boldBytes;

      // 1. Try Flutter asset rootBundle
      try {
        final regData = await rootBundle.load('assets/fonts/arabic_regular.ttf');
        final boldData = await rootBundle.load('assets/fonts/arabic_bold.ttf');
        regBytes = regData.buffer.asUint8List();
        boldBytes = boldData.buffer.asUint8List();
      } catch (_) {}

      // 2. If running outside asset bundle or in headless tests, try local assets directory
      if (regBytes == null) {
        final fReg = File('assets/fonts/arabic_regular.ttf');
        final fBold = File('assets/fonts/arabic_bold.ttf');
        if (fReg.existsSync() && fBold.existsSync()) {
          regBytes = await fReg.readAsBytes();
          boldBytes = await fBold.readAsBytes();
        }
      }

      // 3. Fallback to Windows system Arial fonts
      if (regBytes == null) {
        final winArial = File(r'C:\Windows\Fonts\arial.ttf');
        final winArialBd = File(r'C:\Windows\Fonts\arialbd.ttf');
        if (winArial.existsSync() && winArialBd.existsSync()) {
          regBytes = await winArial.readAsBytes();
          boldBytes = await winArialBd.readAsBytes();
        }
      }

      if (regBytes != null && boldBytes != null) {
        _cachedRegularFont = pw.Font.ttf(ByteData.sublistView(regBytes));
        _cachedBoldFont = pw.Font.ttf(ByteData.sublistView(boldBytes));

        return pw.ThemeData.withFont(
          base: _cachedRegularFont!,
          bold: _cachedBoldFont!,
          fontFallback: [_cachedRegularFont!, _cachedBoldFont!],
        );
      }
    } catch (e) {
      debugPrint('Warning: Could not load Arabic TTF font for PDF: $e');
    }

    return pw.ThemeData();
  }

  /// Formats monetary amount with localized currency symbol
  static String formatCurrency(double amount, String currencyCode, {String language = 'AR'}) {
    final amtStr = amount.toStringAsFixed(2);
    final isEn = language.toUpperCase() == 'EN';
    switch (currencyCode.toUpperCase()) {
      case 'USD':
        return isEn ? '\$$amtStr' : '$amtStr \$';
      case 'YER':
        return isEn ? '$amtStr YER' : '$amtStr ر.ي';
      case 'SAR':
      default:
        return isEn ? '$amtStr SAR' : '$amtStr ر.س';
    }
  }

  /// Generates Bilingual/Localized A4 Tax Invoice Document
  static Future<Uint8List> generateTaxInvoice({
    required InvoiceHeaderDto header,
    required List<InvoiceItemDto> items,
  }) async {
    final theme = await getInvoiceTheme();
    final pdf = pw.Document(theme: theme);

    final lang = header.language.toUpperCase();
    final isEn = lang == 'EN';
    final isBi = lang == 'BILINGUAL';

    // Generate ZATCA Base64 TLV QR Code
    final zatcaPayload = ZatcaQrCodec.generateBase64Tlv(
      sellerName: header.companyName,
      vatRegistrationNumber: header.taxNumber,
      timestamp: header.invoiceDate,
      invoiceTotal: header.grandTotal,
      vatTotal: header.taxTotal,
    );

    final cur = header.currencyCode;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Directionality(
            textDirection: isEn ? pw.TextDirection.ltr : pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // 1. Header Section
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
                        pw.Text(
                          isEn ? 'Branch: ${header.branchName}' : 'الفرع: ${header.branchName}',
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          isEn ? 'VAT Number: ${header.taxNumber}' : 'الرقم الضريبي (VAT): ${header.taxNumber}',
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        if (header.crNumber.isNotEmpty)
                          pw.Text(
                            isEn ? 'CR Number: ${header.crNumber}' : 'السجل التجاري (CR): ${header.crNumber}',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                        if (header.phone != null && header.phone!.isNotEmpty)
                          pw.Text(
                            isEn ? 'Phone: ${header.phone}' : 'الهاتف: ${header.phone}',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                    if (header.showZatcaQr)
                      pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: zatcaPayload,
                          width: 85,
                          height: 85,
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 1.5, color: PdfColors.blue900),
                pw.SizedBox(height: 8),

                // 2. Invoice Meta Details
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
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
                          pw.Text(
                            isEn ? 'INVOICE NUMBER: ${header.invoiceNumber}' : (isBi ? 'رقم الفاتورة / Invoice #: ${header.invoiceNumber}' : 'رقم الفاتورة: ${header.invoiceNumber}'),
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            isEn ? 'DATE: ${DateFormat('yyyy-MM-dd HH:mm').format(header.invoiceDate)}' : 'التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(header.invoiceDate)}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            isEn ? 'PAYMENT: ${header.paymentMethod}' : 'طريقة السداد: ${header.paymentMethod}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            isEn ? 'CUSTOMER: ${header.customerName}' : 'العميل: ${header.customerName}',
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                          if (header.customerTaxNumber != null) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                              isEn ? 'Customer VAT: ${header.customerTaxNumber}' : 'الرقم الضريبي للعميل: ${header.customerTaxNumber}',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ],
                          if (header.showCashierName && header.cashierName != null) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                              isEn ? 'Cashier: ${header.cashierName}' : 'الكاشير: ${header.cashierName}',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                // 3. Line Items Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4), // Item
                    1: const pw.FlexColumnWidth(2), // SKU
                    2: const pw.FlexColumnWidth(1.5), // Unit
                    3: const pw.FlexColumnWidth(1.2), // Qty
                    4: const pw.FlexColumnWidth(1.8), // Price
                    5: const pw.FlexColumnWidth(1.5), // Tax
                    6: const pw.FlexColumnWidth(2), // Total
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                      children: [
                        _tableHeader(isEn ? 'Item Description' : (isBi ? 'الصنف / Item' : 'بيان الصنف')),
                        _tableHeader(isEn ? 'SKU' : 'الكود'),
                        _tableHeader(isEn ? 'Unit' : 'الوحدة'),
                        _tableHeader(isEn ? 'Qty' : 'الكمية'),
                        _tableHeader(isEn ? 'Unit Price' : 'سعر الوحدة'),
                        _tableHeader(isEn ? 'VAT (15%)' : 'الضريبة'),
                        _tableHeader(isEn ? 'Total' : 'الإجمالي'),
                      ],
                    ),
                    ...items.map(
                      (item) => pw.TableRow(
                        children: [
                          _tableCell(item.productName, align: pw.TextAlign.start),
                          _tableCell(item.sku),
                          _tableCell(item.unitName),
                          _tableCell(item.quantity.toString()),
                          _tableCell(formatCurrency(item.unitPrice, cur, language: lang)),
                          _tableCell(formatCurrency(item.taxAmount, cur, language: lang)),
                          _tableCell(formatCurrency(item.lineTotal, cur, language: lang), isBold: true),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),

                // 4. Financial Summary
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // 1D Barcode
                    if (header.show1DBarcode && header.invoiceNumber.isNotEmpty)
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.code128(),
                            data: header.invoiceNumber,
                            width: 140,
                            height: 40,
                            drawText: true,
                          ),
                        ],
                      )
                    else
                      pw.SizedBox(width: 100),

                    // Totals
                    pw.Container(
                      width: 250,
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        children: [
                          _summaryRow(isEn ? 'Subtotal' : 'المجموع الفرعي (قبل الضريبة)', formatCurrency(header.subtotal, cur, language: lang)),
                          pw.SizedBox(height: 4),
                          if (header.taxTotal > 0)
                            _summaryRow(
                              isEn ? 'VAT (${header.subtotal > 0 ? (header.taxTotal / header.subtotal * 100.0).round() : 15}%)' : 'ضريبة القيمة المضافة (${header.subtotal > 0 ? (header.taxTotal / header.subtotal * 100.0).round() : 15}%)',
                              formatCurrency(header.taxTotal, cur, language: lang),
                            )
                          else
                            _summaryRow(
                              isEn ? 'VAT (0% - Exempt)' : 'ضريبة القيمة المضافة (0% - معفى)',
                              formatCurrency(0.0, cur, language: lang),
                            ),
                          pw.Divider(thickness: 1, color: PdfColors.grey400),
                          _summaryRow(isEn ? 'Grand Total' : 'المجموع الكلي المستحق', formatCurrency(header.grandTotal, cur, language: lang), isBold: true, fontSize: 13, color: PdfColors.blue900),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.Spacer(),

                // 5. Custom Footer
                if (header.customFooter != null && header.customFooter!.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      header.customFooter!,
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text(
                    isEn ? 'Generated securely by ALFA SOFT Enterprise ERP System' : 'تم استخراج هذه الفاتورة رسمياً من نظام الفا سوفت المالي المتكامل — ALFA SOFT',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Compact ESC/POS-compatible 80mm/58mm Thermal Receipt Generator with Arabic/English localization
  static Future<Uint8List> generateThermalReceipt({
    required InvoiceHeaderDto header,
    required List<InvoiceItemDto> items,
    String copyLabel = 'نسخة العميل — Customer Copy',
    bool is80mm = true,
  }) async {
    final theme = await getInvoiceTheme();
    final pdf = pw.Document(theme: theme);
    final pageFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;

    final lang = header.language.toUpperCase();
    final isEn = lang == 'EN';
    final isBi = lang == 'BILINGUAL';
    final cur = header.currencyCode;

    final zatcaPayload = ZatcaQrCodec.generateBase64Tlv(
      sellerName: header.companyName,
      vatRegistrationNumber: header.taxNumber,
      timestamp: header.invoiceDate,
      invoiceTotal: header.grandTotal,
      vatTotal: header.taxTotal,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    // Language-aware label dictionary
    final titleText = isEn
        ? 'SIMPLIFIED TAX INVOICE'
        : (isBi ? 'فاتورة ضريبية مبسطة | Tax Invoice' : 'فاتورة ضريبية مبسطة');

    final invoiceNumLabel = isEn ? 'Invoice #:' : (isBi ? 'رقم الفاتورة / Inv #:' : 'رقم الفاتورة:');
    final dateLabel = isEn ? 'Date:' : (isBi ? 'التاريخ / Date:' : 'التاريخ:');
    final customerLabel = isEn ? 'Customer:' : (isBi ? 'العميل / Customer:' : 'العميل:');
    final cashierLabel = isEn ? 'Cashier:' : (isBi ? 'الكاشير / Cashier:' : 'الكاشير:');
    final paymentLabel = isEn ? 'Payment:' : (isBi ? 'طريقة الدفع / Payment:' : 'طريقة الدفع:');

    final colItem = isEn ? 'Item' : (isBi ? 'الصنف / Item' : 'الصنف');
    final colQty = isEn ? 'Qty' : (isBi ? 'الكمية / Qty' : 'الكمية');
    final colPrice = isEn ? 'Price' : (isBi ? 'السعر / Price' : 'السعر');
    final colTotal = isEn ? 'Total' : (isBi ? 'الإجمالي / Total' : 'الإجمالي');

    final subtotalLabel = isEn ? 'Subtotal:' : (isBi ? 'المجموع قبل الضريبة / Subtotal:' : 'المجموع قبل الضريبة:');
    final taxRateCalc = header.subtotal > 0 ? (header.taxTotal / header.subtotal * 100.0).round() : 0;
    final vatLabel = header.taxTotal > 0
        ? (isEn ? 'VAT ($taxRateCalc%):' : (isBi ? 'ضريبة القيمة المضافة / VAT ($taxRateCalc%):' : 'ضريبة القيمة المضافة ($taxRateCalc%):'))
        : (isEn ? 'VAT (0% - Exempt):' : (isBi ? 'الضريبة / VAT (0%):' : 'ضريبة القيمة المضافة (0% - معفى):'));
    final grandTotalLabel = isEn ? 'Grand Total:' : (isBi ? 'الإجمالي النهائي / Grand Total:' : 'الإجمالي النهائي:');

    final copyBadge = isEn
        ? (copyLabel.contains('Store') || copyLabel.contains('المحل') || copyLabel.contains('الكاشير') ? 'Store Copy' : 'Customer Copy')
        : (isBi ? copyLabel : (copyLabel.contains('Store') || copyLabel.contains('المحل') || copyLabel.contains('الكاشير') ? 'نسخة المحل' : 'نسخة العميل'));

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        build: (context) {
          return pw.Directionality(
            textDirection: isEn ? pw.TextDirection.ltr : pw.TextDirection.rtl,
            child: pw.Column(
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
                    titleText,
                    style: pw.TextStyle(fontSize: is80mm ? 9.5 : 8.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                if (header.customHeader != null && header.customHeader!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.Text(
                      header.customHeader!.trim(),
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
                pw.Center(
                  child: pw.Text(
                    isEn ? 'Branch: ${header.branchName}' : 'الفرع: ${header.branchName}',
                    style: const pw.TextStyle(fontSize: 8.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                if (header.taxNumber.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      isEn ? 'VAT No: ${header.taxNumber}' : 'الرقم الضريبي: ${header.taxNumber}',
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                if (header.phone != null && header.phone!.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      isEn ? 'Tel: ${header.phone}' : 'هاتف: ${header.phone}',
                      style: const pw.TextStyle(fontSize: 7.5),
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
                      '[ $copyBadge ]',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),

                // 3. Invoice Meta
                pw.Text('$invoiceNumLabel ${header.invoiceNumber}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('$dateLabel ${dateFormat.format(header.invoiceDate)}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('$customerLabel ${header.customerName}', style: const pw.TextStyle(fontSize: 8)),
                if (header.showCashierName && header.cashierName != null && header.cashierName!.isNotEmpty)
                  pw.Text('$cashierLabel ${header.cashierName}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('$paymentLabel ${header.paymentMethod}', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 3),
                pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

                // 4. Line Items Table
                pw.Row(
                  children: [
                    pw.Expanded(flex: 5, child: pw.Text(colItem, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text(colQty, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 2, child: pw.Text(colPrice, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 3, child: pw.Text(colTotal, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: isEn ? pw.TextAlign.right : pw.TextAlign.left)),
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
                            item.unitName.isNotEmpty ? '${item.productName} (${item.unitName})' : item.productName,
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
                          flex: 3,
                          child: pw.Text(
                            formatCurrency(item.lineTotal, cur, language: lang),
                            style: const pw.TextStyle(fontSize: 7),
                            textAlign: isEn ? pw.TextAlign.right : pw.TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 2),

                // 5. Financial Summary
                if (header.showTaxBreakdown) ...[
                  _thermalSummaryRow(subtotalLabel, formatCurrency(header.subtotal, cur, language: lang)),
                  _thermalSummaryRow(vatLabel, formatCurrency(header.taxTotal, cur, language: lang)),
                  pw.Divider(thickness: 0.5),
                ],
                _thermalSummaryRow(grandTotalLabel, formatCurrency(header.grandTotal, cur, language: lang), isBold: true, fontSize: 9.5),
                pw.SizedBox(height: 6),

                // 6. ZATCA QR
                if (header.showZatcaQr) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: zatcaPayload,
                      width: is80mm ? 70 : 55,
                      height: is80mm ? 70 : 55,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                ],

                // 7. 1D Barcode (Code128)
                if (header.show1DBarcode && header.invoiceNumber.isNotEmpty) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: header.invoiceNumber,
                      width: is80mm ? 120 : 95,
                      height: 24,
                      drawText: true,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                ],

                // 8. Custom Footer & App Signature
                pw.Center(
                  child: pw.Text(
                    header.customFooter?.trim().isNotEmpty == true
                        ? header.customFooter!.trim()
                        : (isEn ? 'Thank you for your visit • Goods returnable within 3 days' : 'شكراً لتعاملكم معنا • البضاعة المباعة تستبدل خلال 3 أيام'),
                    style: const pw.TextStyle(fontSize: 6.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    isEn ? 'ALFA SOFT POS' : 'نظام الفا سوفت — ALFA SOFT POS',
                    style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.center, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 10, PdfColor color = PdfColors.black}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      ],
    );
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
