import 'dart:convert';
import 'dart:typed_data';
import '../../domain/entities/accounting.dart';

/// High-Performance CSV/Excel Exporter with UTF-8 BOM for Arabic Windows compatibility
class ExcelExporter {
  const ExcelExporter._();

  /// Prepends UTF-8 BOM (\uFEFF) so Microsoft Excel opens Arabic text flawlessly
  static Uint8List _createCsvBytes(List<List<String>> rows) {
    final buffer = StringBuffer();
    // UTF-8 Byte Order Mark
    buffer.write('\uFEFF');

    for (final row in rows) {
      final line = row.map(_escapeCsvValue).join(',');
      buffer.writeln(line);
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static String _escapeCsvValue(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Exports Sales Invoices Register
  static Uint8List exportSalesRegister(List<Map<String, dynamic>> sales) {
    final rows = <List<String>>[
      [
        'رقم الفاتورة',
        'تاريخ الفاتورة',
        'اسم العميل',
        'المجموع الفرعي (SAR)',
        'ضريبة القيمة المضافة (SAR)',
        'الإجمالي النهائي (SAR)',
        'طريقة الدفع',
        'حالة الفاتورة'
      ]
    ];

    for (final s in sales) {
      final subtotal = ((s['subtotal'] as int? ?? 0) / 100.0).toStringAsFixed(2);
      final tax = ((s['tax_total'] as int? ?? 0) / 100.0).toStringAsFixed(2);
      final grand = ((s['grand_total'] as int? ?? 0) / 100.0).toStringAsFixed(2);

      rows.add([
        s['invoice_number']?.toString() ?? '',
        s['invoice_date']?.toString() ?? '',
        s['customer_name']?.toString() ?? 'عميل نقدي',
        subtotal,
        tax,
        grand,
        s['payment_status']?.toString() ?? 'PAID',
        s['status']?.toString() ?? 'POSTED',
      ]);
    }

    return _createCsvBytes(rows);
  }

  /// Exports Product Inventory Stock Balances
  static Uint8List exportInventoryStock(List<Map<String, dynamic>> items) {
    final rows = <List<String>>[
      [
        'كود الصنف (SKU)',
        'الباركود',
        'اسم الصنف',
        'المستودع',
        'الكمية الحالية',
        'متوسط التكلفة (SAR)',
        'إجمالي القيمة المخزنية (SAR)'
      ]
    ];

    for (final item in items) {
      final qty = item['quantity'] as int? ?? 0;
      final avgCostCents = item['average_cost'] as int? ?? 0;
      final avgCost = (avgCostCents / 100.0).toStringAsFixed(2);
      final totalValue = ((qty * avgCostCents) / 100.0).toStringAsFixed(2);

      rows.add([
        item['sku']?.toString() ?? '',
        item['barcode']?.toString() ?? '',
        item['name_ar']?.toString() ?? '',
        item['warehouse_name']?.toString() ?? 'المستودع الرئيسي',
        qty.toString(),
        avgCost,
        totalValue,
      ]);
    }

    return _createCsvBytes(rows);
  }

  /// Exports Trial Balance (ميزان المراجعة)
  static Uint8List exportTrialBalance(List<TrialBalanceRow> rows) {
    final csvRows = <List<String>>[
      [
        'رقم الحساب',
        'اسم الحساب',
        'نوع الحساب',
        'إجمالي المدين (SAR)',
        'إجمالي الدائن (SAR)',
        'الرصيد الصافي (SAR)'
      ]
    ];

    for (final r in rows) {
      csvRows.add([
        r.code,
        r.nameAr,
        r.accountType.labelAr,
        (r.totalDebit / 100.0).toStringAsFixed(2),
        (r.totalCredit / 100.0).toStringAsFixed(2),
        (r.netBalance / 100.0).toStringAsFixed(2),
      ]);
    }

    return _createCsvBytes(csvRows);
  }

  /// Exports Customer Statement of Account
  static Uint8List exportCustomerStatement(
    String customerName,
    List<Map<String, dynamic>> transactions,
  ) {
    final rows = <List<String>>[
      ['كشف حساب العميل: $customerName'],
      ['تاريخ التصدير: ${DateTime.now().toIso8601String()}'],
      [],
      [
        'التاريخ',
        'رقم المستند',
        'البيان',
        'مدين / مبيعات (SAR)',
        'دائن / سدادات (SAR)',
        'الرصيد التراكمي (SAR)'
      ]
    ];

    int runningBalance = 0;
    for (final t in transactions) {
      final debit = t['debit'] as int? ?? 0;
      final credit = t['credit'] as int? ?? 0;
      runningBalance += (debit - credit);

      rows.add([
        t['date']?.toString() ?? '',
        t['doc_number']?.toString() ?? '',
        t['narration']?.toString() ?? '',
        debit > 0 ? (debit / 100.0).toStringAsFixed(2) : '0.00',
        credit > 0 ? (credit / 100.0).toStringAsFixed(2) : '0.00',
        (runningBalance / 100.0).toStringAsFixed(2),
      ]);
    }

    return _createCsvBytes(rows);
  }
}
