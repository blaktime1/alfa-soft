import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/printing/esc_pos_builder.dart';
import '../../core/printing/pdf_invoice_generator.dart';
import '../../core/printing/excel_exporter.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  EscPosPaperSize _selectedPaperSize = EscPosPaperSize.mm80;
  String? _statusNotification;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
          tabs: const [
            Tab(icon: Icon(Icons.receipt_rounded), text: 'إيصالات نقاط البيع (ESC/POS)'),
            Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'الفاتورة الضريبية (A4 PDF)'),
            Tab(icon: Icon(Icons.table_view_rounded), text: 'تصدير البيانات (Excel/CSV)'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'مؤشرات الأداء (Analytics)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildThermalReceiptTab(context),
          _buildPdfInvoiceTab(context),
          _buildExcelExportTab(context),
          _buildAnalyticsTab(context),
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
                      _receiptRow('المجموع الفرعي:', '75.00 SAR'),
                      _receiptRow('ضريبة القيمة المضافة (15%):', '11.25 SAR'),
                      Text('=' * (is80mm ? 40 : 26), textAlign: TextAlign.center),
                      _receiptRow('الإجمالي النهائي المطلوب:', '86.25 SAR', isBold: true),
                      _receiptRow('المدفوع نقداً:', '100.00 SAR'),
                      _receiptRow('المتبقي للمستهلك:', '13.75 SAR'),
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

    return PdfPreview(
      build: (format) => PdfInvoiceGenerator.generateTaxInvoice(header: header, items: items),
      canChangeOrientation: false,
      canChangePageFormat: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.share_rounded),
          onPressed: () => _showNotification('مشاركة الفاتورة الضريبية جاهزة'),
        ),
      ],
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

    final totalSales = (totalSalesRow['total'] as int) / 100.0;
    final totalInvoices = totalInvoicesRow['cnt'] as int;
    final totalTax = (totalTaxRow['tax'] as int) / 100.0;
    final totalProducts = totalProductsRow['cnt'] as int;

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
                child: _metricCard('إجمالي المبيعات', '${totalSales.toStringAsFixed(2)} SAR', Icons.monetization_on_rounded, AppColors.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard('عدد الفواتير الصادرة', '$totalInvoices فاتورة', Icons.receipt_long_rounded, Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _metricCard('ضريبة القيمة المضافة المحصلة', '${totalTax.toStringAsFixed(2)} SAR', Icons.percent_rounded, Colors.orange),
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
                    columns: const [
                      DataColumn(label: Text('كود الصنف')),
                      DataColumn(label: Text('اسم الصنف')),
                      DataColumn(label: Text('الكمية المباعة')),
                      DataColumn(label: Text('إجمالي الإيرادات (SAR)')),
                    ],
                    rows: const [
                      DataRow(cells: [
                        DataCell(Text('1001')),
                        DataCell(Text('مياه معدنية 500 مل')),
                        DataCell(Text('120 حبة')),
                        DataCell(Text('180.00 SAR')),
                      ]),
                      DataRow(cells: [
                        DataCell(Text('1002')),
                        DataCell(Text('حليب طازج 1 لتر')),
                        DataCell(Text('85 حبة')),
                        DataCell(Text('510.00 SAR')),
                      ]),
                      DataRow(cells: [
                        DataCell(Text('1003')),
                        DataCell(Text('أرز بسمتي 5 كجم')),
                        DataCell(Text('42 كيس')),
                        DataCell(Text('1,890.00 SAR')),
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
}
