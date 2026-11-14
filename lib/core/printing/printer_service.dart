import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../data/local/database_service.dart';
import 'pdf_invoice_generator.dart';

/// Service managing printer hardware selection, POS auto-printing,
/// invoice language, custom headers/footers, and dual-copy receipt configurations.
class PrinterService {
  final DatabaseService _db;

  const PrinterService(this._db);

  // =================== Settings Persistence ===================

  String? getSelectedPrinter() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'printer_selected_name' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.trim().isNotEmpty) return val.trim();
      }
    } catch (_) {}
    return null;
  }

  void setSelectedPrinter(String? printerName) {
    try {
      if (printerName == null || printerName.trim().isEmpty) {
        _db.execute("DELETE FROM system_settings WHERE key = 'printer_selected_name'");
      } else {
        _db.execute('''
          INSERT INTO system_settings (key, value, updated_at)
          VALUES ('printer_selected_name', ?, datetime('now'))
          ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now');
        ''', [printerName.trim()]);
      }
    } catch (_) {}
  }

  bool isAutoPrintEnabled() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'printer_auto_print' LIMIT 1");
      if (rows.isNotEmpty) {
        return (rows.first['value'] as String?) != '0';
      }
    } catch (_) {}
    return true; // Default auto-print ON
  }

  void setAutoPrintEnabled(bool enabled) {
    _setSetting('printer_auto_print', enabled ? '1' : '0');
  }

  bool isCustomerCopyEnabled() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'print_customer_copy' LIMIT 1");
      if (rows.isNotEmpty) {
        return (rows.first['value'] as String?) != '0';
      }
    } catch (_) {}
    return true; // Default Customer Copy ON
  }

  void setCustomerCopyEnabled(bool enabled) {
    _setSetting('print_customer_copy', enabled ? '1' : '0');
  }

  bool isCashierCopyEnabled() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'print_cashier_copy' LIMIT 1");
      if (rows.isNotEmpty) {
        return (rows.first['value'] as String?) == '1';
      }
    } catch (_) {}
    return false; // Default Cashier Copy OFF
  }

  void setCashierCopyEnabled(bool enabled) {
    _setSetting('print_cashier_copy', enabled ? '1' : '0');
  }

  String getPaperSize() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'printer_paper_size' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    return '80mm';
  }

  void setPaperSize(String size) {
    _setSetting('printer_paper_size', size);
  }

  // =================== Invoice Customization & Languages ===================

  /// Returns 'AR', 'EN', or 'BILINGUAL'
  String getInvoiceLanguage() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_language' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.isNotEmpty) return val.toUpperCase();
      }
    } catch (_) {}
    return 'AR';
  }

  void setInvoiceLanguage(String lang) {
    _setSetting('invoice_language', lang.toUpperCase());
  }

  String getDefaultCurrency() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'default_currency' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.isNotEmpty) return val.toUpperCase();
      }
    } catch (_) {}
    return 'SAR';
  }

  void setDefaultCurrency(String cur) {
    _setSetting('default_currency', cur.toUpperCase());
  }

  double getExchangeRate(String currency) {
    if (currency == 'SAR') return 1.0;
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = ? LIMIT 1", ['exchange_rate_${currency.toUpperCase()}']);
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null) return double.tryParse(val) ?? (currency.toUpperCase() == 'USD' ? 3.75 : 0.007);
      }
    } catch (_) {}
    return currency.toUpperCase() == 'USD' ? 3.75 : 0.007;
  }

  void setExchangeRate(String currency, double rate) {
    _setSetting('exchange_rate_${currency.toUpperCase()}', rate.toString());
  }

  bool isShowZatcaQr() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_show_zatca_qr' LIMIT 1");
      if (rows.isNotEmpty) return (rows.first['value'] as String?) != '0';
    } catch (_) {}
    return true;
  }

  void setShowZatcaQr(bool show) {
    _setSetting('invoice_show_zatca_qr', show ? '1' : '0');
  }

  bool isShow1DBarcode() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_show_1d_barcode' LIMIT 1");
      if (rows.isNotEmpty) return (rows.first['value'] as String?) != '0';
    } catch (_) {}
    return true;
  }

  void setShow1DBarcode(bool show) {
    _setSetting('invoice_show_1d_barcode', show ? '1' : '0');
  }

  bool isShowCashierName() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_show_cashier_name' LIMIT 1");
      if (rows.isNotEmpty) return (rows.first['value'] as String?) != '0';
    } catch (_) {}
    return true;
  }

  void setShowCashierName(bool show) {
    _setSetting('invoice_show_cashier_name', show ? '1' : '0');
  }

  bool isShowTaxBreakdown() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_show_tax_breakdown' LIMIT 1");
      if (rows.isNotEmpty) return (rows.first['value'] as String?) != '0';
    } catch (_) {}
    return true;
  }

  void setShowTaxBreakdown(bool show) {
    _setSetting('invoice_show_tax_breakdown', show ? '1' : '0');
  }

  String getReceiptHeader() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_receipt_header' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    return 'أهلاً بكم في منظومة ألفا سوفت';
  }

  void setReceiptHeader(String header) {
    _setSetting('invoice_receipt_header', header);
  }

  String getReceiptFooter() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'invoice_receipt_footer' LIMIT 1");
      if (rows.isNotEmpty) {
        final val = rows.first['value'] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (_) {}
    return 'شكراً لتعاملكم معنا • البضاعة المباعة تستبدل خلال 3 أيام';
  }

  void setReceiptFooter(String footer) {
    _setSetting('invoice_receipt_footer', footer);
  }

  void _setSetting(String key, String value) {
    try {
      _db.execute('''
        INSERT INTO system_settings (key, value, updated_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now');
      ''', [key, value]);
    } catch (_) {}
  }

  // =================== Hardware Discovery ===================

  Future<List<Printer>> getAvailablePrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (e) {
      debugPrint('Error listing printers: $e');
      return [];
    }
  }

  // =================== Execution ===================

  /// Prints receipt copies according to configuration.
  /// If [selectedPrinterName] matches an available system printer, it sends directly.
  /// Otherwise, it prompts with layout preview or system default.
  Future<void> printInvoice({
    required InvoiceHeaderDto header,
    required List<InvoiceItemDto> items,
    bool? overrideCustomerCopy,
    bool? overrideCashierCopy,
  }) async {
    final printCustomer = overrideCustomerCopy ?? isCustomerCopyEnabled();
    final printCashier = overrideCashierCopy ?? isCashierCopyEnabled();
    final paperSize = getPaperSize();
    final targetPrinterName = getSelectedPrinter();

    if (!printCustomer && !printCashier) return;

    // Enrich header with persisted settings
    final enrichedHeader = header.copyWith(
      language: header.language.isNotEmpty ? header.language : getInvoiceLanguage(),
      currencyCode: header.currencyCode.isNotEmpty ? header.currencyCode : getDefaultCurrency(),
      showZatcaQr: isShowZatcaQr(),
      show1DBarcode: isShow1DBarcode(),
      showCashierName: isShowCashierName(),
      showTaxBreakdown: isShowTaxBreakdown(),
      customHeader: header.customHeader ?? getReceiptHeader(),
      customFooter: header.customFooter ?? getReceiptFooter(),
    );

    Printer? matchedPrinter;
    if (targetPrinterName != null && targetPrinterName.isNotEmpty) {
      try {
        final printers = await Printing.listPrinters();
        matchedPrinter = printers.firstWhere(
          (p) => p.name.toLowerCase() == targetPrinterName.toLowerCase(),
          orElse: () => printers.firstWhere(
            (p) => p.isDefault,
            orElse: () => printers.isNotEmpty ? printers.first : const Printer(url: '', name: ''),
          ),
        );
        if (matchedPrinter.url.isEmpty && matchedPrinter.name.isEmpty) {
          matchedPrinter = null;
        }
      } catch (_) {}
    }

    final is80 = paperSize == '80mm';

    // 1. Print Customer Copy
    if (printCustomer) {
      try {
        final customerBytes = await PdfInvoiceGenerator.generateThermalReceipt(
          header: enrichedHeader,
          items: items,
          copyLabel: enrichedHeader.language == 'EN' ? 'Customer Copy' : 'نسخة العميل — Customer Copy',
          is80mm: is80,
        );

        if (matchedPrinter != null) {
          await Printing.directPrintPdf(
            printer: matchedPrinter,
            onLayout: (PdfPageFormat format) async => customerBytes,
            name: 'Invoice_${header.invoiceNumber}_Customer',
          );
        } else {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => customerBytes,
            name: 'Invoice_${header.invoiceNumber}_Customer',
          );
        }
      } catch (e) {
        debugPrint('Error printing customer copy: $e');
      }
    }

    // 2. Print Cashier Copy
    if (printCashier) {
      try {
        final cashierBytes = await PdfInvoiceGenerator.generateThermalReceipt(
          header: enrichedHeader,
          items: items,
          copyLabel: enrichedHeader.language == 'EN' ? 'Store Copy' : 'نسخة الكاشير / المحل — Store Copy',
          is80mm: is80,
        );

        if (matchedPrinter != null) {
          await Printing.directPrintPdf(
            printer: matchedPrinter,
            onLayout: (PdfPageFormat format) async => cashierBytes,
            name: 'Invoice_${header.invoiceNumber}_Cashier',
          );
        } else {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => cashierBytes,
            name: 'Invoice_${header.invoiceNumber}_Cashier',
          );
        }
      } catch (e) {
        debugPrint('Error printing cashier copy: $e');
      }
    }
  }
}
