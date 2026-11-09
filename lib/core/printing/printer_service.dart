import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../data/local/database_service.dart';
import 'pdf_invoice_generator.dart';

/// Service managing printer hardware selection, POS auto-printing,
/// and dual-copy (Customer Copy / Cashier Copy) configurations.
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
    return false; // Default Cashier Copy OFF (optional as requested: "نقدر نطفي النسختين او نشغلها")
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
          header: header,
          items: items,
          copyLabel: 'نسخة العميل — Customer Copy',
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
          header: header,
          items: items,
          copyLabel: 'نسخة الكاشير / المحل — Store Copy',
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
