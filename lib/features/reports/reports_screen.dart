import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/providers/app_state_provider.dart';
import '../../data/local/database_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/printing/esc_pos_builder.dart';
import '../../core/printing/pdf_invoice_generator.dart';
import '../../core/printing/excel_exporter.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/printing/printer_service.dart';


class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  EscPosPaperSize _selectedPaperSize = EscPosPaperSize.mm80;
  String? _statusNotification;

  // System Operations & Audit Log Filters
  String _auditDateFilter = 'ALL'; // 'ALL', 'TODAY', 'WEEK', 'MONTH', 'CUSTOM'
  DateTime? _auditFromDate;
  DateTime? _auditToDate;
  String _auditCategoryFilter = 'ALL';
  String? _auditSelectedUserId;
  final _auditSearchController = TextEditingController();

  // Annual Audit & Financial Report State
  String _selectedAuditYear = '2026';
  String _annualAuditSubTab = 'RECEIVABLE'; // 'RECEIVABLE', 'PAYABLE', 'INVENTORY'
  final _debtSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _auditSearchController.dispose();
    _debtSearchController.dispose();
    super.dispose();
  }

  void _showNotification(String msg, {bool isSuccess = true}) {
    setState(() => _statusNotification = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? AppColors.success : AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير والمستندات والطباعة — Reporting & Printing Hub'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.assessment_rounded), text: 'الجرد السنوي الشامل والمركز المالي (Annual Audit)'),
            Tab(icon: Icon(Icons.history_edu_rounded), text: 'سجل حركات وعمليات النظام (System Operations Log)'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'مؤشرات الأداء (Analytics)'),
            Tab(icon: Icon(Icons.table_view_rounded), text: 'تصدير البيانات (Excel/CSV)'),
            Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'الفاتورة الضريبية (A4 PDF)'),
            Tab(icon: Icon(Icons.receipt_rounded), text: 'إيصالات نقاط البيع (ESC/POS)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnnualAuditTab(context),
          _buildInvoiceAuditReportTab(context),
          _buildAnalyticsTab(context),
          _buildExcelExportTab(context),
          _buildPdfInvoiceTab(context),
          _buildThermalReceiptTab(context),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: ESC/POS THERMAL RECEIPT
  // -------------------------------------------------------------
  Widget _buildThermalReceiptTab(BuildContext context) {
    final theme = Theme.of(context);
    final is80mm = _selectedPaperSize == EscPosPaperSize.mm80;

    return Row(
      children: [
        // Control & Configuration Panel
        Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(left: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إعدادات الطابعة الحرارية',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('مقاس ورق الإيصال:'),
              const SizedBox(height: 8),
              SegmentedButton<EscPosPaperSize>(
                segments: const [
                  ButtonSegment(value: EscPosPaperSize.mm80, label: Text('80 مم (قياسي)')),
                  ButtonSegment(value: EscPosPaperSize.mm58, label: Text('58 مم (مدمج)')),
                ],
                selected: {_selectedPaperSize},
                onSelectionChanged: (set) {
                  setState(() => _selectedPaperSize = set.first);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final builder = EscPosBuilder(paperSize: _selectedPaperSize);
                  builder.text('ALFA SOFT ERP', align: EscPosAlign.center, bold: true, doubleSize: true);
                  builder.text('اختبار الطباعة الحرارية المباشرة', align: EscPosAlign.center);
                  builder.divider();
                  builder.twoColumn('التاريخ:', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
                  builder.twoColumn('حالة المنفذ:', 'جاهز (USB/LAN OK)');
                  builder.divider();
                  builder.text('شكراً لزيارتكم', align: EscPosAlign.center, bold: true);
                  builder.cut();

                  final bytes = builder.toBytes();
                  _showNotification('تم توليد أوامر ESC/POS بنجاح (${bytes.length} بايت)');
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('طباعة إيصال تجريبي (ESC/POS)'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  final builder = EscPosBuilder(paperSize: _selectedPaperSize);
                  builder.openCashDrawer();
                  final bytes = builder.toBytes();
                  _showNotification('تم إرسال أمر نبض فتح درج النقدية (${bytes.length} بايت)');
                },
                icon: const Icon(Icons.point_of_sale_rounded),
                label: const Text('فتح درج النقدية (Pulse Pin 2)'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
              const Spacer(),
              if (_statusNotification != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusNotification!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
        ),

        // Visual Paper Receipt Tape Preview
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Container(
                width: is80mm ? 360 : 270,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.black, fontSize: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ALFA SOFT ERP',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                      const Text('شركة ألفا للتقنية والحلول البرمجية', textAlign: TextAlign.center),
                      const Text('الفرع الرئيسي — هاتف: 0112345678', textAlign: TextAlign.center),
                      const Text('الرقم الضريبي: 310123456700003', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('-' * (is80mm ? 40 : 26), textAlign: TextAlign.center),
                      _receiptRow('رقم الفاتورة:', 'INV-2026-0891'),
                      _receiptRow('التاريخ:', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
                      _receiptRow('الكاشير:', 'أحمد المدير'),
                      _receiptRow('العميل:', 'عميل نقدي عابر'),
                      Text('-' * (is80mm ? 40 : 26), textAlign: TextAlign.center),
                      _receiptItem('حليب طازج 1 لتر', '2', '6.00', '12.00'),
                      _receiptItem('زيت نباتي 1.5 لتر', '1', '18.00', '18.00'),
                      _receiptItem('أرز بسمتي 5 كجم', '1', '45.00', '45.00'),
                      Text('-' * (is80mm ? 40 : 26), textAlign: TextAlign.center),
                      _receiptRow('المجموع الفرعي:', '75.00 ${PrinterService.defaultCurrency}'),
                      _receiptRow('ضريبة القيمة المضافة (15%):', '11.25 ${PrinterService.defaultCurrency}'),
                      Text('=' * (is80mm ? 40 : 26), textAlign: TextAlign.center),
                      _receiptRow('الإجمالي النهائي المطلوب:', '86.25 ${PrinterService.defaultCurrency}', isBold: true),
                      _receiptRow('المدفوع نقداً:', '100.00 ${PrinterService.defaultCurrency}'),
                      _receiptRow('المتبقي للمستهلك:', '13.75 ${PrinterService.defaultCurrency}'),
                      const SizedBox(height: 16),
                      // Mock QR Box
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
                        child: const Center(
                          child: Icon(Icons.qr_code_2_rounded, size: 76, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('فاتورة ضريبية مبسطة (ZATCA)', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
                      const Text('شكراً لتعاملكم معنا!', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _receiptRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _receiptItem(String name, String qty, String price, String total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 3, child: Text(name, overflow: TextOverflow.ellipsis)),
          Expanded(child: Text('x$qty', textAlign: TextAlign.center)),
          Expanded(child: Text(price, textAlign: TextAlign.right)),
          Expanded(child: Text(total, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: A4 PDF TAX INVOICE
  // -------------------------------------------------------------
  Widget _buildPdfInvoiceTab(BuildContext context) {
    final header = InvoiceHeaderDto(
      companyName: 'شركة ألفا للتقنية والحلول البرمجية',
      taxNumber: '310123456700003',
      crNumber: '1010987654',
      branchName: 'الفرع المالي الرئيسي (الرياض)',
      invoiceNumber: 'INV-2026-0042',
      invoiceDate: DateTime.now(),
      customerName: 'شركة الوفاق للتجارة والاستيراد',
      customerTaxNumber: '300987654300003',
      subtotal: 1000.00,
      taxTotal: 150.00,
      grandTotal: 1150.00,
      paymentMethod: 'تحويل بنكي / مدى (ELECTRONIC)',
    );

    final items = [
      const InvoiceItemDto(
        productName: 'حليب طازج نقي 1 لتر',
        sku: '1002',
        quantity: 50,
        unitName: 'حبة',
        unitPrice: 6.00,
        taxAmount: 45.00,
        lineTotal: 345.00,
      ),
      const InvoiceItemDto(
        productName: 'أرز بسمتي فاخر 5 كجم',
        sku: '1003',
        quantity: 10,
        unitName: 'كيس',
        unitPrice: 45.00,
        taxAmount: 67.50,
        lineTotal: 517.50,
      ),
      const InvoiceItemDto(
        productName: 'زيت نباتي نقي 1.5 لتر',
        sku: '1004',
        quantity: 15,
        unitName: 'حبة',
        unitPrice: 18.00,
        taxAmount: 40.50,
        lineTotal: 310.50,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(header.companyName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('الرقم الضريبي: ${header.taxNumber}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          Text('الفرع: ${header.branchName}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success),
                        ),
                        child: const Text('ZATCA Phase-2 متوافق',
                            style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Customer & Invoice Details
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('فاتورة إلى (العميل):', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(header.customerName),
                          Text('الرقم الضريبي: ${header.customerTaxNumber}'),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('رقم الفاتورة: ${header.invoiceNumber}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(header.invoiceDate)}'),
                          Text('طريقة السداد: ${header.paymentMethod}'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Table
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: const [
                          Padding(padding: EdgeInsets.all(8), child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('الضريبة', style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ...items.map((it) => TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(it.productName)),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${it.quantity} ${it.unitName}')),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${it.unitPrice.toStringAsFixed(2)} ${PrinterService.defaultCurrency}')),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${it.taxAmount.toStringAsFixed(2)} ${PrinterService.defaultCurrency}')),
                          Padding(padding: const EdgeInsets.all(8), child: Text('${it.lineTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}')),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Financial Totals
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المجموع الخاضع للضريبة:'),
                              Text('${header.subtotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ضريبة القيمة المضافة (15%):'),
                              Text('${header.taxTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}'),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('المبلغ الإجمالي المستحق:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('${header.grandTotal.toStringAsFixed(2)} ${PrinterService.defaultCurrency}',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.brandAccent)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Export Action Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('تصدير وحفظ الفاتورة بصيغة PDF مع رمز ZATCA QR',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      try {
                        final bytes = await PdfInvoiceGenerator.generateTaxInvoice(header: header, items: items);
                        final dir = await getApplicationDocumentsDirectory();
                        final file = File('${dir.path}/INV_${header.invoiceNumber}.pdf');
                        await file.writeAsBytes(bytes);
                        _showNotification('تم تصدير الفاتورة بنجاح: ${file.path}');
                      } catch (e) {
                        _showNotification('خطأ في تصدير الفاتورة: $e', isSuccess: false);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: EXCEL / CSV EXPORT
  // -------------------------------------------------------------
  Widget _buildExcelExportTab(BuildContext context) {
    final db = ref.read(databaseServiceProvider);
    final repo = ref.read(accountingRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مركز تصدير البيانات إلى Excel و CSV',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'يتم تصدير جميع الملفات بصيغة UTF-8 BOM المتوافقة كلياً مع Microsoft Excel لدعم اللغة العربية دون أي تشوه في النصوص.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _exportCard(
                  title: 'سجل المبيعات والفواتير',
                  icon: Icons.point_of_sale_rounded,
                  color: Colors.blue,
                  description: 'تصدير شامل لجميع فواتير المبيعات مع تفاصيل العميل والضريبة والإجماليات.',
                  onExport: () {
                    final sales = db.select('SELECT * FROM sales_invoices ORDER BY created_at DESC');
                    final bytes = ExcelExporter.exportSalesRegister(
                      sales.map((s) => Map<String, dynamic>.from(s)).toList(),
                    );
                    _showNotification('تم تصدير سجل المبيعات بنجاح (${bytes.length} بايت - ${sales.length} فاتورة)');
                  },
                ),
                _exportCard(
                  title: 'أرصدة وتقييم المخزون',
                  icon: Icons.inventory_2_rounded,
                  color: Colors.green,
                  description: 'تصدير جرد المستودعات مع الكميات الحالية ومتوسط التكلفة وقيمة المخزون.',
                  onExport: () {
                    final items = db.select('''
                      SELECT p.sku, p.barcode, p.name_ar, ib.quantity, ib.average_cost 
                      FROM inventory_balances ib
                      JOIN products p ON ib.product_id = p.id
                    ''');
                    final bytes = ExcelExporter.exportInventoryStock(
                      items.map((i) => Map<String, dynamic>.from(i)).toList(),
                    );
                    _showNotification('تم تصدير جرد المخزون بنجاح (${bytes.length} بايت)');
                  },
                ),
                _exportCard(
                  title: 'ميزان المراجعة المحاسبي',
                  icon: Icons.balance_rounded,
                  color: Colors.purple,
                  description: 'تصدير شجرة الحسابات وأرصدة ميزان المراجعة متوازنة للتحليل المالي.',
                  onExport: () {
                    final compRow = db.select('SELECT id FROM companies LIMIT 1');
                    final compId = compRow.isNotEmpty ? compRow.first['id'] as String : '';
                    final tb = repo.getTrialBalance(compId);
                    final bytes = ExcelExporter.exportTrialBalance(tb);
                    _showNotification('تم تصدير ميزان المراجعة بنجاح (${bytes.length} بايت - ${tb.length} حساب)');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportCard({
    required String title,
    required IconData icon,
    required Color color,
    required String description,
    required VoidCallback onExport,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
            const Divider(),
            ElevatedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded),
              label: const Text('تصدير فوري إلى Excel (CSV)'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                backgroundColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 4: ANALYTICS & KEY METRICS
  // -------------------------------------------------------------
  Widget _buildAnalyticsTab(BuildContext context) {
    final db = ref.read(databaseServiceProvider);

    final totalSalesRow = db.select('SELECT COALESCE(SUM(grand_total), 0) as total FROM sales_invoices').first;
    final totalInvoicesRow = db.select('SELECT COUNT(*) as cnt FROM sales_invoices').first;
    final totalTaxRow = db.select('SELECT COALESCE(SUM(tax_total), 0) as tax FROM sales_invoices').first;
    final totalProductsRow = db.select('SELECT COUNT(*) as cnt FROM products WHERE is_active = 1').first;

    final totalSales = ((totalSalesRow['total'] as num?)?.toDouble() ?? 0.0) / 100.0;
    final totalInvoices = (totalInvoicesRow['cnt'] as num?)?.toInt() ?? 0;
    final totalTax = ((totalTaxRow['tax'] as num?)?.toDouble() ?? 0.0) / 100.0;
    final totalProducts = (totalProductsRow['cnt'] as num?)?.toInt() ?? 0;

    final cur = PrinterService.defaultCurrency;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('لوحة التحليلات ومؤشرات الأداء الرئيسية',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _metricCard('إجمالي المبيعات', '${totalSales.toStringAsFixed(2)} $cur', Icons.monetization_on_rounded, AppColors.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard('عدد الفواتير الصادرة', '$totalInvoices فاتورة', Icons.receipt_long_rounded, Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard('ضريبة القيمة المضافة المحصلة', '${totalTax.toStringAsFixed(2)} $cur', Icons.percent_rounded, Colors.orange),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard('إجمالي الأصناف النشطة', '$totalProducts صنف', Icons.category_rounded, Colors.purple),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('أعلى الأصناف مبيعاً (Top Selling Products)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  DataTable(
                    columns: [
                      const DataColumn(label: Text('كود الصنف')),
                      const DataColumn(label: Text('اسم الصنف')),
                      const DataColumn(label: Text('الكمية المباعة')),
                      DataColumn(label: Text('إجمالي الإيرادات ($cur)')),
                    ],
                    rows: [
                      DataRow(cells: [
                        const DataCell(Text('1001')),
                        const DataCell(Text('مياه معدنية 500 مل')),
                        const DataCell(Text('120 حبة')),
                        DataCell(Text('180.00 $cur')),
                      ]),
                      DataRow(cells: [
                        const DataCell(Text('1002')),
                        const DataCell(Text('حليب طازج 1 لتر')),
                        const DataCell(Text('85 حبة')),
                        DataCell(Text('510.00 $cur')),
                      ]),
                      DataRow(cells: [
                        const DataCell(Text('1003')),
                        const DataCell(Text('أرز بسمتي 5 كجم')),
                        const DataCell(Text('42 كيس')),
                        DataCell(Text('1,890.00 $cur')),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 5: COMPREHENSIVE SYSTEM OPERATIONS & AUDIT REPORT
  // -------------------------------------------------------------
  Widget _buildInvoiceAuditReportTab(BuildContext context) {
    final db = ref.watch(databaseServiceProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    final companyId = compResult.isNotEmpty ? compResult.first['id'] as String : '';

    final operations = _fetchSystemOperations(
      db,
      companyId: companyId,
      dateFilter: _auditDateFilter,
      fromDate: _auditFromDate,
      toDate: _auditToDate,
      categoryFilter: _auditCategoryFilter,
      selectedUserId: _auditSelectedUserId,
      query: _auditSearchController.text.trim(),
    );

    // Fetch active users for filter dropdown
    List<Map<String, dynamic>> systemUsers = [];
    try {
      final uRows = db.select('SELECT id, username, full_name FROM users WHERE company_id = ? ORDER BY full_name ASC', [companyId]);
      systemUsers = uRows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {}

    // Metrics counters
    final totalOps = operations.length;
    final todayOps = operations.where((o) {
      final ts = o['timestamp'] as String? ?? '';
      return ts.startsWith(DateTime.now().toIso8601String().substring(0, 10));
    }).length;
    final salesOps = operations.where((o) => (o['action'] as String? ?? '').contains('SALE')).length;
    final editVoidOps = operations.where((o) {
      final act = (o['action'] as String? ?? '').toUpperCase();
      return act.contains('EDIT') || act.contains('VOID') || act.contains('REVERSE');
    }).length;

    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Overview
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_edu_rounded, color: AppColors.brandPrimary, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سجل الرقابة والعمليات الشامل لكافة حركات النظام (System Operations Audit Log)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'مراقبة وفلترة دقيقة لكافة الأحداث والعمليات (مبيعات، مشتريات، تعديل وإلغاء، قيود محاسبية، حركات مخزنية، مستخدمين) باللغة العربية.',
                      style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Top Statistics Cards
          Row(
            children: [
              _buildAuditStatCard('إجمالي العمليات المعروضة', '$totalOps عملية', Icons.list_alt_rounded, AppColors.brandPrimary),
              const SizedBox(width: 12),
              _buildAuditStatCard('عمليات اليوم', '$todayOps اليوم', Icons.today_rounded, AppColors.brandSecondary),
              const SizedBox(width: 12),
              _buildAuditStatCard('فواتير ومبيعات الكاشير', '$salesOps حركة بيع', Icons.point_of_sale_rounded, AppColors.success),
              const SizedBox(width: 12),
              _buildAuditStatCard('تعديل وإلغاء فواتير', '$editVoidOps عملية حساسة', Icons.warning_amber_rounded, AppColors.danger),
            ],
          ),
          const SizedBox(height: 16),

          // Search and Filters Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightBgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lightBorderSubtle),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Search Field
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _auditSearchController,
                        decoration: InputDecoration(
                          hintText: 'بحث في العمليات باسم المستخدم، رقم المستند، البيان أو السبب...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _auditSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => setState(() => _auditSearchController.clear()),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Category Filter Dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _auditCategoryFilter,
                        decoration: InputDecoration(
                          labelText: 'نوع وحزمة العمليات',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('جميع العمليات (All)')),
                          DropdownMenuItem(value: 'SALES', child: Text('مبيعات ونقاط البيع (Sales & POS)')),
                          DropdownMenuItem(value: 'EDITS_VOIDS', child: Text('تعديل وإلغاء فواتير (Edits & Voids)')),
                          DropdownMenuItem(value: 'PURCHASES', child: Text('مشتريات وتوريدات (Purchases)')),
                          DropdownMenuItem(value: 'ACCOUNTING', child: Text('حسابات وقيود يومية (Accounting)')),
                          DropdownMenuItem(value: 'INVENTORY', child: Text('حركات مخزنية وتسويات (Inventory)')),
                          DropdownMenuItem(value: 'SYSTEM', child: Text('مستخدمين وأمان ونظام (System & Security)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _auditCategoryFilter = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // User Filter Dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _auditSelectedUserId ?? 'ALL',
                        decoration: InputDecoration(
                          labelText: 'تصفية بالمستخدم',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'ALL', child: Text('كافة المستخدمين')),
                          ...systemUsers.map((u) => DropdownMenuItem(
                                value: u['id'] as String,
                                child: Text('${u['full_name']} (${u['username']})'),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() => _auditSelectedUserId = (val == 'ALL' ? null : val));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick Date Filters
                Row(
                  children: [
                    const Text('الفترة الزمنية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('الكل (All)'),
                      selected: _auditDateFilter == 'ALL',
                      onSelected: (sel) => setState(() => _auditDateFilter = 'ALL'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('اليوم (Today)'),
                      selected: _auditDateFilter == 'TODAY',
                      onSelected: (sel) => setState(() => _auditDateFilter = 'TODAY'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('آخر 7 أيام (Week)'),
                      selected: _auditDateFilter == 'WEEK',
                      onSelected: (sel) => setState(() => _auditDateFilter = 'WEEK'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('هذا الشهر (Month)'),
                      selected: _auditDateFilter == 'MONTH',
                      onSelected: (sel) => setState(() => _auditDateFilter = 'MONTH'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(_auditDateFilter == 'CUSTOM' && _auditFromDate != null
                          ? '${DateFormat('yyyy-MM-dd').format(_auditFromDate!)} إلى ${DateFormat('yyyy-MM-dd').format(_auditToDate ?? DateTime.now())}'
                          : 'تحديد فترة مخصصة (Custom Range)...'),
                      selected: _auditDateFilter == 'CUSTOM',
                      avatar: const Icon(Icons.date_range_rounded, size: 14),
                      onSelected: (sel) async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDateRange: _auditFromDate != null && _auditToDate != null
                              ? DateTimeRange(start: _auditFromDate!, end: _auditToDate!)
                              : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
                        );
                        if (picked != null) {
                          setState(() {
                            _auditDateFilter = 'CUSTOM';
                            _auditFromDate = picked.start;
                            _auditToDate = picked.end;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Operations List
          Expanded(
            child: Card(
              elevation: 1,
              child: operations.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: AppColors.lightTextSecondary),
                          SizedBox(height: 12),
                          Text('لا توجد أي حركات أو عمليات مطابقة لمعايير البحث المحددة',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: operations.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = operations[index];
                        final action = log['action'] as String? ?? 'UNKNOWN';
                        final actionTitle = _getActionArabicTitle(action);
                        final userName = log['user_name'] as String? ?? 'مستخدم';
                        final branchName = log['branch_name'] as String? ?? 'الفرع';
                        final entityName = log['entity_name'] as String? ?? '';
                        final entityId = log['entity_id'] as String? ?? '';
                        final newState = log['new_state'] as String? ?? '';
                        final reason = log['reason'] as String? ?? '';
                        final timestamp = log['timestamp'] as String? ?? '';
                        final deviceId = log['device_id'] as String? ?? 'LOCAL';

                        final isVoid = action.contains('VOID') || action.contains('REVERSE');
                        final isEdit = action.contains('EDIT');
                        final isSale = action.contains('SALE');
                        final isPurchase = action.contains('PURCHASE') || action.contains('GRN');

                        Color badgeColor = AppColors.brandPrimary;
                        IconData icon = Icons.info_outline_rounded;
                        if (isVoid) {
                          badgeColor = AppColors.danger;
                          icon = Icons.cancel_rounded;
                        } else if (isEdit) {
                          badgeColor = Colors.amber.shade800;
                          icon = Icons.edit_note_rounded;
                        } else if (isSale) {
                          badgeColor = AppColors.success;
                          icon = Icons.shopping_cart_checkout_rounded;
                        } else if (isPurchase) {
                          badgeColor = Colors.teal;
                          icon = Icons.inventory_2_rounded;
                        }

                        return ListTile(
                          onTap: () => _showOperationDetailsDialog(context, log),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor: badgeColor.withValues(alpha: 0.15),
                            child: Icon(icon, color: badgeColor, size: 22),
                          ),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  actionTitle,
                                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _formatCleanArabicReference(entityName, entityId),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Text(
                                timestamp.isNotEmpty
                                    ? DateFormat('yyyy/MM/dd • hh:mm a').format(DateTime.tryParse(timestamp) ?? DateTime.now())
                                    : '',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _cleanArabicAuditState(newState.isNotEmpty ? newState : (reason.isNotEmpty ? reason : 'تم تنفيذ العملية بنجاح')),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.person_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text('المستخدم: $userName', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(width: 16),
                                    Icon(Icons.store_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text('الفرع: $branchName', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(width: 16),
                                    Icon(Icons.computer_rounded, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text('الجهاز: $deviceId', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 20, color: AppColors.brandPrimary),
                            tooltip: 'عرض التفاصيل الكاملة للعملية',
                            onPressed: () => _showOperationDetailsDialog(context, log),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              radius: 18,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _fetchSystemOperations(
    DatabaseService db, {
    required String companyId,
    required String dateFilter,
    DateTime? fromDate,
    DateTime? toDate,
    required String categoryFilter,
    String? selectedUserId,
    required String query,
  }) {
    final whereClauses = <String>['al.company_id = ?'];
    final params = <dynamic>[companyId];

    if (dateFilter == 'TODAY') {
      whereClauses.add("date(al.timestamp) = date('now', 'localtime')");
    } else if (dateFilter == 'WEEK') {
      whereClauses.add("date(al.timestamp) >= date('now', '-7 days', 'localtime')");
    } else if (dateFilter == 'MONTH') {
      whereClauses.add("date(al.timestamp) >= date('now', '-30 days', 'localtime')");
    } else if (dateFilter == 'CUSTOM') {
      if (fromDate != null) {
        whereClauses.add("date(al.timestamp) >= date(?)");
        params.add(fromDate.toIso8601String().substring(0, 10));
      }
      if (toDate != null) {
        whereClauses.add("date(al.timestamp) <= date(?)");
        params.add(toDate.toIso8601String().substring(0, 10));
      }
    }

    if (categoryFilter == 'SALES') {
      whereClauses.add("(al.action LIKE '%SALE%' OR al.action LIKE '%INVOICE%') AND al.action NOT LIKE '%VOID%' AND al.action NOT LIKE '%EDIT%'");
    } else if (categoryFilter == 'EDITS_VOIDS') {
      whereClauses.add("(al.action LIKE '%EDIT%' OR al.action LIKE '%VOID%' OR al.action LIKE '%REVERSE%')");
    } else if (categoryFilter == 'PURCHASES') {
      whereClauses.add("(al.action LIKE '%PURCHASE%' OR al.action LIKE '%GRN%')");
    } else if (categoryFilter == 'ACCOUNTING') {
      whereClauses.add("(al.action LIKE '%JOURNAL%' OR al.action LIKE '%PAYMENT%')");
    } else if (categoryFilter == 'INVENTORY') {
      whereClauses.add("(al.action LIKE '%INVENTORY%' OR al.action LIKE '%STOCK%' OR al.action LIKE '%TRANSFER%')");
    } else if (categoryFilter == 'SYSTEM') {
      whereClauses.add("(al.action LIKE '%USER%' OR al.action LIKE '%ROLE%' OR al.action LIKE '%BACKUP%' OR al.action LIKE '%OPTIMIZE%' OR al.action LIKE '%LICENSE%')");
    }

    if (selectedUserId != null && selectedUserId.isNotEmpty && selectedUserId != 'ALL') {
      whereClauses.add("al.user_id = ?");
      params.add(selectedUserId);
    }

    if (query.isNotEmpty) {
      whereClauses.add('''
        (al.action LIKE ? OR al.entity_name LIKE ? OR al.entity_id LIKE ? 
         OR al.new_state LIKE ? OR al.previous_state LIKE ? OR al.reason LIKE ?
         OR u.full_name LIKE ? OR u.username LIKE ?)
      ''');
      final q = '%$query%';
      params.addAll([q, q, q, q, q, q, q, q]);
    }

    final sql = '''
      SELECT 
        al.id,
        al.company_id,
        al.branch_id,
        al.user_id,
        al.device_id,
        al.action,
        al.entity_name,
        al.entity_id,
        al.previous_state,
        al.new_state,
        al.timestamp,
        al.ip_address,
        al.reason,
        COALESCE(u.full_name, u.username, 'مستخدم النظام') as user_name,
        COALESCE(b.name, 'الفرع الرئيسي') as branch_name
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN branches b ON al.branch_id = b.id
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY al.timestamp DESC
      LIMIT 250
    ''';

    try {
      final rows = db.select(sql, params);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  String _getActionArabicTitle(String action) {
    final upper = action.toUpperCase();
    if (upper == 'POST_SALE') return 'اعتماد فاتورة مبيعات';
    if (upper == 'EDIT_SALES_INVOICE' || upper == 'EDIT_SALE') return 'تعديل فاتورة مبيعات';
    if (upper == 'VOID_SALES_INVOICE' || upper == 'VOID_SALE') return 'إلغاء فاتورة مبيعات';
    if (upper == 'POST_PURCHASE') return 'تسجيل فاتورة مشتريات';
    if (upper == 'VOID_PURCHASE') return 'إلغاء فاتورة مشتريات';
    if (upper == 'PURCHASE_GRN' || upper == 'RECEIVE_GOODS') return 'سند استلام بضاعة (GRN)';
    if (upper == 'CREATE_PURCHASE_ORDER') return 'إنشاء أمر شراء';
    if (upper == 'POST_JOURNAL_ENTRY') return 'ترحيل قيد محاسبي';
    if (upper == 'REVERSE_JOURNAL_ENTRY') return 'عكس قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER' || upper == 'POST_EXPENSE' || upper == 'CREATE_EXPENSE') return 'تسجيل سند صرف مصروفات';
    if (upper == 'SALARY_ADVANCE' || upper == 'POST_ADVANCE' || upper == 'CREATE_ADVANCE') return 'صرف سلفة موظف';
    if (upper == 'RECEIPT_VOUCHER' || upper == 'POST_RECEIPT') return 'سند قبض / إيداع إيراد';
    if (upper == 'PAYROLL' || upper == 'GENERATE_PAYROLL') return 'توليد مسير رواتب';
    if (upper == 'APPROVE_PAYROLL') return 'اعتماد مسير رواتب';
    if (upper == 'POST_PAYROLL') return 'ترحيل مسير رواتب';
    if (upper == 'SALE_ISSUE') return 'صرف مخزني لمبيعات';
    if (upper == 'TRANSFER_DISPATCH') return 'إرسال تحويل مخزني';
    if (upper == 'TRANSFER_RECEIPT') return 'استلام تحويل مخزني';
    if (upper == 'CREATE_USER') return 'إضافة مستخدم جديد';
    if (upper == 'UPDATE_USER') return 'تعديل مستخدم';
    if (upper == 'BACKUP_DATABASE') return 'نسخ احتياطي للبيانات';
    if (upper == 'OPTIMIZE_DATABASE') return 'تحسين وضغط البيانات';
    if (upper == 'RESTORE_DATABASE') return 'استعادة نسخة احتياطية';
    if (upper == 'OPEN_POS_SHIFT') return 'فتح وردية كاشير';
    if (upper == 'CLOSE_POS_SHIFT') return 'إغلاق وردية كاشير';
    if (upper == 'LAN_SYNC_PUSH') return 'مزامنة شبكة محلية (إرسال)';
    if (upper == 'LAN_SYNC_PULL') return 'مزامنة شبكة محلية (استقبال)';
    return action;
  }

  String _getEntityArabicTitle(String entity) {
    final upper = entity.toUpperCase();
    if (upper == 'SALES_INVOICE' || upper == 'INVOICE') return 'فاتورة مبيعات';
    if (upper == 'PURCHASE_INVOICE') return 'فاتورة مشتريات';
    if (upper == 'PURCHASE_ORDER') return 'أمر شراء';
    if (upper == 'PURCHASE_GRN' || upper == 'GRN') return 'سند توريد مخزني';
    if (upper == 'JOURNAL_ENTRY') return 'قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER') return 'سند صرف مصروف';
    if (upper == 'SALARY_ADVANCE') return 'سلفة موظف';
    if (upper == 'RECEIPT_VOUCHER') return 'سند قبض / إيداع';
    if (upper == 'PAYROLL_RUN') return 'مسير رواتب';
    if (upper == 'PRODUCT') return 'منتج / صنف';
    if (upper == 'USER') return 'مستخدم';
    if (upper == 'CUSTOMER') return 'عميل';
    if (upper == 'SUPPLIER') return 'مورد';
    if (upper == 'EMPLOYEE') return 'موظف';
    if (upper == 'WAREHOUSE') return 'مستودع';
    if (upper == 'BRANCH') return 'فرع';
    if (upper == 'SHIFT') return 'وردية كاشير';
    if (upper == 'SYSTEM_SETTINGS' || upper == 'SETTINGS') return 'إعدادات النظام';
    return entity;
  }

  String _formatCleanArabicReference(String entityName, String entityId) {
    if (entityId.isEmpty) return _getEntityArabicTitle(entityName);
    if (entityId.startsWith('INV-')) {
      return 'فاتورة مبيعات #${entityId.replaceFirst('INV-', '')}';
    }
    if (entityId.startsWith('PINV-')) {
      return 'فاتورة مشتريات #${entityId.replaceFirst('PINV-', '')}';
    }
    if (entityId.startsWith('PO-')) {
      return 'أمر شراء #${entityId.replaceFirst('PO-', '')}';
    }
    if (entityId.startsWith('GRN-')) {
      return 'إذن توريد #${entityId.replaceFirst('GRN-', '')}';
    }
    if (entityId.startsWith('ADV-')) {
      return 'سلفة موظف #${entityId.replaceFirst('ADV-', '')}';
    }
    if (entityId.startsWith('EXP-')) {
      return 'سند صرف #${entityId.replaceFirst('EXP-', '')}';
    }
    if (entityId.startsWith('RCT-')) {
      return 'سند إيداع #${entityId.replaceFirst('RCT-', '')}';
    }
    if (entityId.startsWith('JE-')) {
      return 'قيد يومية #${entityId.replaceFirst('JE-', '')}';
    }
    if (entityId.contains('-') && entityId.length >= 24) {
      return '${_getEntityArabicTitle(entityName)} #${entityId.substring(entityId.length - 6)}';
    }
    return '${_getEntityArabicTitle(entityName)} #$entityId';
  }

  String _cleanArabicAuditState(String raw) {
    if (raw.trim().isEmpty) return 'تم تنفيذ العملية واعتمادها بنجاح';
    String res = raw;
    res = res.replaceAll('POST_SALE:', 'اعتماد فاتورة مبيعات:');
    res = res.replaceAll('POST_SALE', 'اعتماد مبيعات');
    res = res.replaceAll('POST_PURCHASE:', 'فاتورة مشتريات:');
    res = res.replaceAll('POST_PURCHASE', 'مشتريات');
    res = res.replaceAll('RECEIVE_GOODS', 'استلام وتوريد مخزني');
    res = res.replaceAll('Invoice: ', 'فاتورة: #');
    res = res.replaceAll('PO: ', 'أمر شراء: #');
    res = res.replaceAll('GRN: ', 'إذن توريد: #');
    res = res.replaceAll('Total: ', 'الإجمالي: ');
    res = res.replaceAll('Cost: ', 'التكلفة: ');
    res = res.replaceAll('Lines: ', 'عدد الأصناف: ');
    res = res.replaceAll('isCash: true', 'نقداً');
    res = res.replaceAll('isCash: false', 'آجل');
    res = res.replaceAll('Starting Cash: ', 'رصيد فتح الصندوق: ');
    res = res.replaceAll('SAR', 'ريال');
    res = res.replaceAll('YER', 'ريال يمني');
    res = res.replaceAll('USD', 'دولار');
    res = res.replaceAll('Customer: ', 'العميل: ');
    res = res.replaceAll('Supplier: ', 'المورد: ');
    res = res.replaceAll('Reason: ', 'السبب: ');
    res = res.replaceAll('DESKTOP_POS', 'نقطة بيع');
    res = res.replaceAll('DESKTOP_ERP', 'المنظومة');
    return res;
  }

  void _showOperationDetailsDialog(BuildContext context, Map<String, dynamic> log) {
    final action = log['action'] as String? ?? '';
    final entityName = log['entity_name'] as String? ?? '';
    final entityId = log['entity_id'] as String? ?? '';
    final userName = log['user_name'] as String? ?? 'مستخدم';
    final branchName = log['branch_name'] as String? ?? 'الفرع';
    final deviceId = log['device_id'] as String? ?? 'LOCAL';
    final timestamp = log['timestamp'] as String? ?? '';
    final reason = log['reason'] as String? ?? '';
    final newState = log['new_state'] as String? ?? '';
    final prevState = log['previous_state'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: AppColors.brandPrimary),
            const SizedBox(width: 8),
            Text('تفاصيل العملية: ${_getActionArabicTitle(action)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('نوع الحركة / العملية:', _getActionArabicTitle(action)),
                _detailRow('المرجع في النظام:', _formatCleanArabicReference(entityName, entityId)),
                _detailRow('التصنيف:', _getEntityArabicTitle(entityName)),
                _detailRow('المستخدم المنفذ:', userName),
                _detailRow('الفرع:', branchName),
                _detailRow('الجهاز / المحطة:', deviceId),
                _detailRow('وقت العملية:', timestamp.isNotEmpty ? DateFormat('yyyy/MM/dd • hh:mm a').format(DateTime.tryParse(timestamp) ?? DateTime.now()) : '-'),
                const Divider(height: 20),
                if (reason.isNotEmpty) ...[
                  const Text('السبب / مبرر العملية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(reason, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('بيان وحالة العملية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lightBgSubtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.lightBorderSubtle),
                  ),
                  child: Text(
                    _cleanArabicAuditState(newState),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                if (entityId.isNotEmpty || newState.isNotEmpty || prevState.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('المعرفات البرمجية والبيانات التقنية المتقدمة',
                        style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                    children: [
                      if (entityId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: SelectableText('المعرف (ID): $entityId', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                tooltip: 'نسخ المعرف',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: entityId));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المعرف بنجاح')));
                                },
                              ),
                            ],
                          ),
                        ),
                      if (newState.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Align(alignment: Alignment.centerRight, child: Text('Payload / Raw State:', style: TextStyle(fontSize: 10, color: Colors.grey))),
                        SelectableText(newState, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      ],
                      if (prevState.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Align(alignment: Alignment.centerRight, child: Text('Previous State:', style: TextStyle(fontSize: 10, color: Colors.grey))),
                        SelectableText(prevState, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق النافذة')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 6: COMPREHENSIVE ANNUAL PHYSICAL & FINANCIAL AUDIT
  // -------------------------------------------------------------
  Widget _buildAnnualAuditTab(BuildContext context) {
    final db = ref.read(databaseServiceProvider);
    final cur = PrinterService.defaultCurrency;

    final compRow = db.select('SELECT id, trade_name, legal_name, tax_number FROM companies LIMIT 1');
    final companyId = compRow.isNotEmpty ? compRow.first['id'] as String : '';
    final companyName = compRow.isNotEmpty
        ? ((compRow.first['trade_name'] ?? compRow.first['legal_name'] ?? 'شركة ألفا سوفت') as String)
        : 'شركة ألفا سوفت';
    final companyTax = compRow.isNotEmpty ? (compRow.first['tax_number'] as String? ?? '') : '';
    String companyPhone = '';
    try {
      final brRow = db.select('SELECT phone FROM branches WHERE company_id = ? LIMIT 1', [companyId]);
      if (brRow.isNotEmpty && brRow.first['phone'] != null) {
        companyPhone = brRow.first['phone'] as String;
      }
    } catch (_) {}

    final isAllYears = _selectedAuditYear == 'ALL';

    int totalSalesCents = 0;
    int salesCount = 0;
    int totalPurchasesCents = 0;
    int purchasesCount = 0;
    int totalExpensesCents = 0;
    int expensesCount = 0;
    int totalPayrollCents = 0;
    int payrollCount = 0;
    List<Map<String, dynamic>> stockRows = [];
    int totalStockCostCents = 0;
    int totalStockRetailCents = 0;
    int totalStockQuantity = 0;
    List<Map<String, dynamic>> custRows = [];
    int totalReceivablesCents = 0;
    List<Map<String, dynamic>> suppRows = [];
    int totalPayablesCents = 0;

    try {
      // 1. Sales & Inflow
      final salesQuery = isAllYears
          ? "SELECT COALESCE(SUM(grand_total), 0) as total, COALESCE(SUM(paid_total), 0) as paid, COUNT(*) as cnt FROM sales_invoices WHERE company_id = ? AND status != 'VOID'"
          : "SELECT COALESCE(SUM(grand_total), 0) as total, COALESCE(SUM(paid_total), 0) as paid, COUNT(*) as cnt FROM sales_invoices WHERE company_id = ? AND status != 'VOID' AND strftime('%Y', created_at) = '$_selectedAuditYear'";
      final salesResult = db.select(salesQuery, [companyId]);
      if (salesResult.isNotEmpty) {
        totalSalesCents = (salesResult.first['total'] as num?)?.toInt() ?? 0;
        salesCount = (salesResult.first['cnt'] as num?)?.toInt() ?? 0;
      }

      // 2. Purchases
      final poQuery = isAllYears
          ? "SELECT COALESCE(SUM(grand_total), 0) as total, COUNT(*) as cnt FROM purchase_orders WHERE company_id = ? AND status != 'CANCELLED'"
          : "SELECT COALESCE(SUM(grand_total), 0) as total, COUNT(*) as cnt FROM purchase_orders WHERE company_id = ? AND status != 'CANCELLED' AND strftime('%Y', created_at) = '$_selectedAuditYear'";
      final poResult = db.select(poQuery, [companyId]);
      if (poResult.isNotEmpty) {
        totalPurchasesCents = (poResult.first['total'] as num?)?.toInt() ?? 0;
        purchasesCount = (poResult.first['cnt'] as num?)?.toInt() ?? 0;
      }

      // 3. Operating Expenses
      final expQuery = isAllYears
          ? "SELECT COALESCE(SUM(amount_cents), 0) as total, COUNT(*) as cnt FROM expense_vouchers WHERE company_id = ? AND (status IS NULL OR status != 'CANCELLED')"
          : "SELECT COALESCE(SUM(amount_cents), 0) as total, COUNT(*) as cnt FROM expense_vouchers WHERE company_id = ? AND (status IS NULL OR status != 'CANCELLED') AND strftime('%Y', created_at) = '$_selectedAuditYear'";
      final expResult = db.select(expQuery, [companyId]);
      if (expResult.isNotEmpty) {
        totalExpensesCents = (expResult.first['total'] as num?)?.toInt() ?? 0;
        expensesCount = (expResult.first['cnt'] as num?)?.toInt() ?? 0;
      }

      // 4. Payroll Runs
      final prQuery = isAllYears
          ? "SELECT COALESCE(SUM(total_net), 0) as total, COUNT(*) as cnt FROM payroll_runs WHERE company_id = ? AND status != 'CANCELLED'"
          : "SELECT COALESCE(SUM(total_net), 0) as total, COUNT(*) as cnt FROM payroll_runs WHERE company_id = ? AND status != 'CANCELLED' AND period_month LIKE '$_selectedAuditYear-%'";
      final prResult = db.select(prQuery, [companyId]);
      if (prResult.isNotEmpty) {
        totalPayrollCents = (prResult.first['total'] as num?)?.toInt() ?? 0;
        payrollCount = (prResult.first['cnt'] as num?)?.toInt() ?? 0;
      }

      // 5. Stock Valuation
      final stockQuery = '''
        SELECT 
          p.id, p.barcode, p.sku, p.name_ar,
          COALESCE(SUM(ib.quantity), 0) as quantity,
          COALESCE(AVG(ib.average_cost), p.cost_price, 0) as cost_price_cents,
          p.sale_price as unit_price_cents
        FROM products p
        LEFT JOIN inventory_balances ib ON ib.product_id = p.id
        WHERE p.company_id = ? AND p.is_active = 1
        GROUP BY p.id
        ORDER BY p.name_ar ASC
      ''';
      stockRows = db.select(stockQuery, [companyId]).map((r) => Map<String, dynamic>.from(r)).toList();
      for (final s in stockRows) {
        final qty = (s['quantity'] as num?)?.toInt() ?? 0;
        final cost = (s['cost_price_cents'] as num?)?.toInt() ?? 0;
        final retail = (s['unit_price_cents'] as num?)?.toInt() ?? 0;
        totalStockCostCents += (qty * cost);
        totalStockRetailCents += (qty * retail);
        totalStockQuantity += qty;
      }

      // 6. Customers (Receivables - الديون التي لنا)
      final custQuery = '''
        SELECT id, code, name, phone, tax_number, credit_limit, current_balance
        FROM customers
        WHERE company_id = ? AND current_balance > 0
        ORDER BY current_balance DESC
      ''';
      custRows = db.select(custQuery, [companyId]).map((r) => Map<String, dynamic>.from(r)).toList();
      for (final c in custRows) {
        totalReceivablesCents += ((c['current_balance'] as num?)?.toInt() ?? 0);
      }

      // 7. Suppliers (Payables - الديون التي علينا)
      final suppQuery = '''
        SELECT id, code, name, phone, tax_number, current_balance
        FROM suppliers
        WHERE company_id = ? AND current_balance > 0
        ORDER BY current_balance DESC
      ''';
      suppRows = db.select(suppQuery, [companyId]).map((r) => Map<String, dynamic>.from(r)).toList();
      for (final s in suppRows) {
        totalPayablesCents += ((s['current_balance'] as num?)?.toInt() ?? 0);
      }
    } catch (e) {
      debugPrint('Error calculating annual audit report: $e');
    }

    // Profit calculation:
    final totalOutflowCents = totalPurchasesCents + totalExpensesCents + totalPayrollCents;
    final netProfitCents = totalSalesCents - totalOutflowCents;

    // Search query filtering
    final query = _debtSearchController.text.trim().toLowerCase();
    final filteredCustRows = custRows.where((c) {
      if (query.isEmpty) return true;
      final name = (c['name'] as String? ?? '').toLowerCase();
      final phone = (c['phone'] as String? ?? '').toLowerCase();
      final code = (c['code'] as String? ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query) || code.contains(query);
    }).toList();

    final filteredSuppRows = suppRows.where((s) {
      if (query.isEmpty) return true;
      final name = (s['name'] as String? ?? '').toLowerCase();
      final phone = (s['phone'] as String? ?? '').toLowerCase();
      final code = (s['code'] as String? ?? '').toLowerCase();
      return name.contains(query) || phone.contains(query) || code.contains(query);
    }).toList();

    final filteredStockRows = stockRows.where((st) {
      if (query.isEmpty) return true;
      final name = (st['name_ar'] as String? ?? '').toLowerCase();
      final barcode = (st['barcode'] as String? ?? '').toLowerCase();
      final sku = (st['sku'] as String? ?? '').toLowerCase();
      return name.contains(query) || barcode.contains(query) || sku.contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.15),
                    radius: 22,
                    child: const Icon(Icons.assessment_rounded, color: AppColors.brandPrimary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الجرد السنوي الشامل والتقرير المالي الختامي',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('كشف التدفقات النقدية، تقييم المخزون، وسجل الديون والالتزامات المالية بدقة تامة',
                            style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                  // Financial Year Selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedAuditYear,
                        items: const [
                          DropdownMenuItem(value: '2026', child: Text('السنة المالية 2026')),
                          DropdownMenuItem(value: '2025', child: Text('السنة المالية 2025')),
                          DropdownMenuItem(value: '2024', child: Text('السنة المالية 2024')),
                          DropdownMenuItem(value: 'ALL', child: Text('كافة الفترات والسنوات')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedAuditYear = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('طباعة وتصدير التقرير (PDF)'),
                    onPressed: () => _printAnnualAuditReport(
                      context: context,
                      companyName: companyName,
                      companyTax: companyTax,
                      companyPhone: companyPhone,
                      selectedYear: _selectedAuditYear,
                      totalSalesCents: totalSalesCents,
                      salesCount: salesCount,
                      totalPurchasesCents: totalPurchasesCents,
                      purchasesCount: purchasesCount,
                      totalExpensesCents: totalExpensesCents,
                      expensesCount: expensesCount,
                      totalPayrollCents: totalPayrollCents,
                      payrollCount: payrollCount,
                      totalStockCostCents: totalStockCostCents,
                      totalStockRetailCents: totalStockRetailCents,
                      totalStockQuantity: totalStockQuantity,
                      totalReceivablesCents: totalReceivablesCents,
                      totalPayablesCents: totalPayablesCents,
                      netProfitCents: netProfitCents,
                      custRows: custRows,
                      suppRows: suppRows,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Key Financial Metric Cards
          Row(
            children: [
              _buildAuditKpiCard(
                title: 'إجمالي الأموال الداخلة (المبيعات)',
                value: '${(totalSalesCents / 100.0).toStringAsFixed(2)} $cur',
                subtitle: '$salesCount فاتورة مبيعات معتمدة',
                icon: Icons.payments_rounded,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              _buildAuditKpiCard(
                title: 'إجمالي المصروفات والرواتب',
                value: '${((totalExpensesCents + totalPayrollCents) / 100.0).toStringAsFixed(2)} $cur',
                subtitle: 'مصاريف: ${(totalExpensesCents / 100.0).toStringAsFixed(0)} | رواتب: ${(totalPayrollCents / 100.0).toStringAsFixed(0)}',
                icon: Icons.trending_down_rounded,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 12),
              _buildAuditKpiCard(
                title: 'إجمالي المشتريات والتوريد',
                value: '${(totalPurchasesCents / 100.0).toStringAsFixed(2)} $cur',
                subtitle: '$purchasesCount أمر شراء وتوريد',
                icon: Icons.local_shipping_rounded,
                color: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAuditKpiCard(
                title: 'قيمة بضاعة المخزون (بالتكلفة)',
                value: '${(totalStockCostCents / 100.0).toStringAsFixed(2)} $cur',
                subtitle: 'القيمة بالبيع: ${(totalStockRetailCents / 100.0).toStringAsFixed(2)} $cur',
                icon: Icons.inventory_2_rounded,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 12),
              _buildAuditKpiCard(
                title: 'الديون التي لنا (العملاء المدينون)',
                value: '${(totalReceivablesCents / 100.0).toStringAsFixed(2)} $cur',
                subtitle: '${custRows.length} عميل مستحق عليهم ديون',
                icon: Icons.account_balance_wallet_rounded,
                color: Colors.amber.shade800,
              ),
              const SizedBox(width: 12),
              _buildAuditKpiCard(
                title: 'الديون التي علينا (الموردون والدائنون)',
                value: '${(totalPayablesCents / 100.0).toStringAsFixed(2)} $cur',
                subtitle: '${suppRows.length} مورد مستحق لهم ديون',
                icon: Icons.receipt_long_rounded,
                color: Colors.purple.shade700,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Net Profit / Operating Result Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: (netProfitCents >= 0 ? AppColors.success : AppColors.danger).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (netProfitCents >= 0 ? AppColors.success : AppColors.danger).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  netProfitCents >= 0 ? Icons.check_circle_rounded : Icons.warning_rounded,
                  color: netProfitCents >= 0 ? AppColors.success : AppColors.danger,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صافي الأرباح التقديرية للفترة: ${(netProfitCents / 100.0).toStringAsFixed(2)} $cur',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: netProfitCents >= 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'تم احتساب الأرباح وفق المعادلة: إجمالي المبيعات - (المشتريات وتكلفة البضاعة + المصروفات التشغيلية + الرواتب)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Sub-Tab Switcher & Search Bar
          Row(
            children: [
              ChoiceChip(
                label: Text('الديون التي لنا (العملاء المدينون) [${custRows.length}]'),
                selected: _annualAuditSubTab == 'RECEIVABLE',
                onSelected: (sel) => setState(() => _annualAuditSubTab = 'RECEIVABLE'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('الديون التي علينا (الموردون والدائنون) [${suppRows.length}]'),
                selected: _annualAuditSubTab == 'PAYABLE',
                onSelected: (sel) => setState(() => _annualAuditSubTab = 'PAYABLE'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('جرد وتقييم المخزون الحالي [${stockRows.length}]'),
                selected: _annualAuditSubTab == 'INVENTORY',
                onSelected: (sel) => setState(() => _annualAuditSubTab = 'INVENTORY'),
              ),
              const Spacer(),
              // Search Field
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _debtSearchController,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم، الكود، أو الهاتف...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _debtSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => setState(() => _debtSearchController.clear()),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sub-Tab Content
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSubTabTable(cur, filteredCustRows, filteredSuppRows, filteredStockRows),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              radius: 20,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const SizedBox(height: 3),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabTable(
    String cur,
    List<Map<String, dynamic>> custRows,
    List<Map<String, dynamic>> suppRows,
    List<Map<String, dynamic>> stockRows,
  ) {
    if (_annualAuditSubTab == 'RECEIVABLE') {
      if (custRows.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.success),
                SizedBox(height: 10),
                Text('لا توجد أي ديون مسجلة على العملاء (كافة الحسابات مسددة بالكامل)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary)),
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.people_rounded, size: 18, color: Colors.amber),
              const SizedBox(width: 6),
              const Text('كشف العملاء المدينين ومبالغ الديون المستحقة لنا:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('عدد المدينين: ${custRows.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
              columns: [
                const DataColumn(label: Text('كود العميل', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('اسم العميل', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('الرقم الضريبي', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('المبلغ المستحق لنا ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: custRows.map((c) {
                final bal = (((c['current_balance'] as num?)?.toDouble() ?? 0.0) / 100.0);
                return DataRow(cells: [
                  DataCell(Text(c['code'] as String? ?? '-', style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(c['name'] as String? ?? '-')),
                  DataCell(Text(c['phone'] as String? ?? '-')),
                  DataCell(Text(c['tax_number'] as String? ?? '-')),
                  DataCell(Text('${bal.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Text('مدين لنا', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ],
      );
    } else if (_annualAuditSubTab == 'PAYABLE') {
      if (suppRows.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.success),
                SizedBox(height: 10),
                Text('لا توجد أي التزامات أو ديون مستحقة للموردين حالياً',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.lightTextSecondary)),
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 18, color: Colors.purple),
              const SizedBox(width: 6),
              const Text('كشف الموردين والدائنين ومبالغ الالتزامات المستحقة عليهم:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('عدد الدائنين: ${suppRows.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
              columns: [
                const DataColumn(label: Text('كود المورد', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('اسم المورد / الشركة', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('الرقم الضريبي', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('المبلغ المستحق له ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: suppRows.map((s) {
                final bal = (((s['current_balance'] as num?)?.toDouble() ?? 0.0) / 100.0);
                return DataRow(cells: [
                  DataCell(Text(s['code'] as String? ?? '-', style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(s['name'] as String? ?? '-')),
                  DataCell(Text(s['phone'] as String? ?? '-')),
                  DataCell(Text(s['tax_number'] as String? ?? '-')),
                  DataCell(Text('${bal.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Text('دائن علينا', style: TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ],
      );
    } else {
      // INVENTORY
      if (stockRows.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('لا توجد أي أصناف مسجلة في المخزن'),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 18, color: Colors.blue),
              const SizedBox(width: 6),
              const Text('جرد بضاعة المستودعات وتقييم التكلفة والبيع:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('عدد الأصناف: ${stockRows.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
              columns: [
                const DataColumn(label: Text('الباركود / SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('اسم الصنف', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text('الكمية بالمخزن', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('سعر التكلفة ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('سعر البيع ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('إجمالي التكلفة ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('إجمالي البيع ($cur)', style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: stockRows.take(50).map((st) {
                final qty = (st['quantity'] as num?)?.toInt() ?? 0;
                final cost = ((st['cost_price_cents'] as num?)?.toDouble() ?? 0.0) / 100.0;
                final retail = ((st['unit_price_cents'] as num?)?.toDouble() ?? 0.0) / 100.0;
                final totalCost = (qty * cost);
                final totalRetail = (qty * retail);
                return DataRow(cells: [
                  DataCell(Text(st['barcode'] ?? st['sku'] ?? '-', style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text(st['name_ar'] as String? ?? '-')),
                  DataCell(Text('$qty وحدة', style: TextStyle(fontWeight: FontWeight.bold, color: qty > 0 ? Colors.green : Colors.red))),
                  DataCell(Text(cost.toStringAsFixed(2))),
                  DataCell(Text(retail.toStringAsFixed(2))),
                  DataCell(Text('${totalCost.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text('${totalRetail.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                ]);
              }).toList(),
            ),
          ),
          if (stockRows.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('* تم عرض أول 50 صنفاً للاستعراض السريع. لطباعة الجرد الكامل، اضغط على زر طباعة وتصدير التقرير أعلاه.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
            ),
        ],
      );
    }
  }

  Future<void> _printAnnualAuditReport({
    required BuildContext context,
    required String companyName,
    required String companyTax,
    required String companyPhone,
    required String selectedYear,
    required int totalSalesCents,
    required int salesCount,
    required int totalPurchasesCents,
    required int purchasesCount,
    required int totalExpensesCents,
    required int expensesCount,
    required int totalPayrollCents,
    required int payrollCount,
    required int totalStockCostCents,
    required int totalStockRetailCents,
    required int totalStockQuantity,
    required int totalReceivablesCents,
    required int totalPayablesCents,
    required int netProfitCents,
    required List<Map<String, dynamic>> custRows,
    required List<Map<String, dynamic>> suppRows,
  }) async {
    final theme = await PdfInvoiceGenerator.getInvoiceTheme();
    final cur = PrinterService.defaultCurrency;

    await Printing.layoutPdf(
      name: 'annual_audit_report_$selectedYear.pdf',
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document(theme: theme);
        final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
        final yearTitle = selectedYear == 'ALL' ? 'كافة السنوات المالية' : 'السنة المالية $selectedYear';

        doc.addPage(
          pw.MultiPage(
            pageFormat: format,
            textDirection: pw.TextDirection.rtl,
            header: (pw.Context ctx) => pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                        if (companyTax.isNotEmpty) pw.Text('الرقم الضريبي: $companyTax', style: const pw.TextStyle(fontSize: 10)),
                        if (companyPhone.isNotEmpty) pw.Text('الهاتف: $companyPhone', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('تقرير الجرد السنوي والمركز المالي الختامي', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text(yearTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text('تاريخ التقرير: $dateStr', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 10),
              ],
            ),
            footer: (pw.Context ctx) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('منظومة ألفا سوفت لإدارة المبيعات والمحاسبة والمخازن', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            build: (pw.Context ctx) => [
              pw.Text('أولاً: ملخص المؤشرات المالية والتدفقات النقدية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('البند المالي / البيان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('القيمة المالية ($cur)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('عدد العمليات / الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('إجمالي المبيعات والإيرادات')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalSalesCents / 100.0).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$salesCount فاتورة مبيعات')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('إجمالي المشتريات وتوريد البضاعة')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalPurchasesCents / 100.0).toStringAsFixed(2)} $cur')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$purchasesCount أمر شراء')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('المصروفات التشغيلية والعمومية')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalExpensesCents / 100.0).toStringAsFixed(2)} $cur')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$expensesCount سند صرف')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('مسيرات الرواتب والأجور')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalPayrollCents / 100.0).toStringAsFixed(2)} $cur')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$payrollCount مسير رواتب')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('قيمة بضاعة المخزون (بسعر التكلفة)')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalStockCostCents / 100.0).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('إجمالي الكميات: $totalStockQuantity وحدة')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('قيمة بضاعة المخزون (بسعر البيع)')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalStockRetailCents / 100.0).toStringAsFixed(2)} $cur')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('القيمة البيعية المتوقعة')),
                    ],
                  ),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('صافي الربح التقديري للفترة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(netProfitCents / 100.0).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(netProfitCents >= 0 ? 'أرباح تشغيلية محققة' : 'عجز / خسارة تشغيلية')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('إجمالي الديون التي لنا (العملاء المدينون)')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalReceivablesCents / 100.0).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${custRows.length} عميل مدين')),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('إجمالي الديون التي علينا (الموردون والدائنون)')),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${(totalPayablesCents / 100.0).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${suppRows.length} مورد دائن')),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              pw.Text('ثانياً: بيان الديون المستحقة لنا على العملاء (Accounts Receivable)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 4),
              if (custRows.isEmpty)
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('لا توجد أي ديون مستحقة على العملاء حالياً.', style: const pw.TextStyle(fontSize: 10)))
              else
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('كود العميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('اسم العميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('رقم الهاتف', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('المبلغ المستحق لنا ($cur)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      ],
                    ),
                    ...custRows.take(15).map((c) => pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${c['code']}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${c['name']}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${c['phone'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${((((c['current_balance'] as num?)?.toDouble() ?? 0.0) / 100.0)).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                          ],
                        )),
                  ],
                ),
              pw.SizedBox(height: 16),

              pw.Text('ثالثاً: بيان الديون المستحقة للموردين علينا (Accounts Payable)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 4),
              if (suppRows.isEmpty)
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('لا توجد أي التزامات أو ديون للموردين حالياً.', style: const pw.TextStyle(fontSize: 10)))
              else
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('كود المورد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('اسم المورد / الشركة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('رقم الهاتف', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('المبلغ المستحق للمورد ($cur)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      ],
                    ),
                    ...suppRows.take(15).map((s) => pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${s['code']}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${s['name']}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${s['phone'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${((((s['current_balance'] as num?)?.toDouble() ?? 0.0) / 100.0)).toStringAsFixed(2)} $cur', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                          ],
                        )),
                  ],
                ),
              pw.SizedBox(height: 24),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('المحاسب المسؤول / مدقق الجرد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 35),
                      pw.Text('التوقيع: ........................................', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('المدير العام / الاعتماد والختم الرسمي', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 35),
                      pw.Text('التوقيع والختم: ........................................', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        return doc.save();
      },
    );
  }
}
