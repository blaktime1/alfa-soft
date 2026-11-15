import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenPos;

  const DashboardScreen({super.key, required this.onOpenPos});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _productCount = 0;
  int _customerCount = 0;
  int _invoiceCount = 0;
  double _todaySalesTotal = 0.0;
  List<Map<String, dynamic>> _recentAuditLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  void _loadDashboardData() {
    final db = ref.read(databaseServiceProvider);

    try {
      // 1. Products count
      final prodResult = db.select('SELECT COUNT(*) as cnt FROM products');
      _productCount = prodResult.first['cnt'] as int;

      // 2. Customers count
      final custResult = db.select('SELECT COUNT(*) as cnt FROM customers');
      _customerCount = custResult.first['cnt'] as int;

      // 3. Invoices count & sales total
      final invResult = db.select('''
        SELECT COUNT(*) as cnt, COALESCE(SUM(grand_total), 0) as total 
        FROM sales_invoices 
        WHERE date(created_at) = date('now')
      ''');
      _invoiceCount = invResult.first['cnt'] as int;
      _todaySalesTotal = (invResult.first['total'] as int) / 100.0;

      // 4. Recent Audit Logs
      final auditResult = db.select('''
        SELECT al.id, al.action, al.entity_name, al.entity_id, al.timestamp, al.user_id, al.new_state,
               COALESCE(u.full_name, u.username, 'مستخدم النظام') as user_name
        FROM audit_logs al
        LEFT JOIN users u ON al.user_id = u.id
        ORDER BY al.timestamp DESC 
        LIMIT 8
      ''');
      _recentAuditLogs = auditResult.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      // Handle gracefully
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Welcome & Quick POS Action
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'لوحة التحكم والعمليات المباشرة',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مؤشرات الأداء اللحظية، حركة الخزينة، والمبيعات لليوم',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: widget.onOpenPos,
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('شاشة الكاشير السريعة (POS)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    backgroundColor: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Metrics Cards Row
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                final cards = [
                  _MetricCard(
                    title: 'مبيعات اليوم',
                    value: '${_todaySalesTotal.toStringAsFixed(2)} SAR',
                    icon: Icons.payments_rounded,
                    color: AppColors.brandAccent,
                  ),
                  _MetricCard(
                    title: 'فواتير اليوم المعتمدة',
                    value: '$_invoiceCount فاتورة',
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.info,
                  ),
                  _MetricCard(
                    title: 'المنتجات المسجلة',
                    value: '$_productCount صنف',
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.warning,
                  ),
                  _MetricCard(
                    title: 'قاعدة العملاء',
                    value: '$_customerCount عميل',
                    icon: Icons.people_alt_rounded,
                    color: AppColors.success,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: cards
                        .map((c) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: c,
                              ),
                            ))
                        .toList(),
                  );
                }

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map((c) => SizedBox(
                            width: (constraints.maxWidth - 12) / 2,
                            child: c,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 32),

            // Operational Details Split View
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Action Shortcuts
                Expanded(
                  flex: 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.flash_on_rounded, color: AppColors.brandAccent),
                              const SizedBox(width: 8),
                              Text('العمليات السريعة',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.brandAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.point_of_sale_rounded,
                                  color: AppColors.brandAccent),
                            ),
                            title: const Text('بدء عملية بيع فورية (POS)'),
                            subtitle: const Text('البيع بالباركود، الدفع المتعدد، والطباعة الفورية'),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                            onTap: widget.onOpenPos,
                          ),
                          const Divider(),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add_box_rounded,
                                  color: AppColors.warning),
                            ),
                            title: const Text('إضافة صنف جديد للكتالوج'),
                            subtitle: const Text('تسجيل الباركود، وحدات القياس، وأسعار البيع والتكلفة'),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                            onTap: () {},
                          ),
                          const Divider(),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.account_balance_rounded,
                                  color: AppColors.info),
                            ),
                            title: const Text('دليل الحسابات والقيود اليومية'),
                            subtitle: const Text('متابعة شجرة الحسابات العامة ومطابقة القيود المزدوجة'),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Live Audit Log Trail
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.history_rounded, color: AppColors.info),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('سجل التدقيق الحي (Audit Log)',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_recentAuditLogs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('لا توجد عمليات مسجلة حتى الآن',
                                    style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5))),
                              ),
                            )
                          else
                            ..._recentAuditLogs.map((log) {
                              final action = log['action'] as String? ?? '';
                              final entity = log['entity_name'] as String? ?? '';
                              final entityId = log['entity_id'] as String? ?? '';
                              final userName = log['user_name'] as String? ?? 'مستخدم';
                              final timestamp = log['timestamp'] as String? ?? '';
                              final newState = log['new_state'] as String? ?? '';
                              final cleanDesc = _cleanArabicAuditState(newState);
                              final refLabel = _formatCleanArabicReference(entity, entityId);

                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _showAuditDetailsDialog(context, log),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 5),
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.brandAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  _getActionArabicTitle(action),
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                if (refLabel.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.brandPrimary.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      refLabel,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppColors.brandPrimary,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              cleanDesc,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'بواسطة: $userName • ${_formatTimestamp(timestamp)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_left_rounded, size: 16, color: AppColors.lightTextSecondary),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getActionArabicTitle(String action) {
    final upper = action.toUpperCase();
    if (upper == 'POST_SALE') return 'اعتماد فاتورة مبيعات';
    if (upper == 'EDIT_SALES_INVOICE' || upper == 'EDIT_SALE') return 'تعديل فاتورة مبيعات';
    if (upper == 'VOID_SALES_INVOICE' || upper == 'VOID_SALE') return 'إلغاء فاتورة مبيعات';
    if (upper == 'POST_PURCHASE') return 'تسجيل فاتورة مشتريات';
    if (upper == 'VOID_PURCHASE') return 'إلغاء فاتورة مشتريات';
    if (upper == 'PURCHASE_GRN' || upper == 'RECEIVE_GOODS') return 'استلام وتوريد بضاعة للمخزن';
    if (upper == 'CREATE_PURCHASE_ORDER') return 'إنشاء أمر شراء';
    if (upper == 'POST_JOURNAL_ENTRY') return 'ترحيل قيد محاسبي';
    if (upper == 'REVERSE_JOURNAL_ENTRY') return 'عكس قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER' || upper == 'POST_EXPENSE' || upper == 'CREATE_EXPENSE') return 'سند صرف مصروفات';
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
    if (upper == 'PURCHASE_GRN' || upper == 'GRN') return 'إذن توريد مخزني';
    if (upper == 'JOURNAL_ENTRY') return 'قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER') return 'سند صرف';
    if (upper == 'SALARY_ADVANCE') return 'سلفة موظف';
    if (upper == 'RECEIPT_VOUCHER') return 'سند قبض / إيداع';
    if (upper == 'PAYROLL_RUN') return 'مسير رواتب';
    if (upper == 'PRODUCT') return 'منتج / صنف';
    if (upper == 'USER') return 'مستخدم';
    if (upper == 'CUSTOMER') return 'عميل';
    if (upper == 'SUPPLIER') return 'مورد';
    if (upper == 'EMPLOYEE') return 'موظف';
    if (upper == 'SHIFT') return 'وردية كاشير';
    if (upper == 'SYSTEM_SETTINGS' || upper == 'SETTINGS') return 'إعدادات النظام';
    return entity;
  }

  void _showAuditDetailsDialog(BuildContext context, Map<String, dynamic> log) {
    final action = log['action'] as String? ?? '';
    final entity = log['entity_name'] as String? ?? '';
    final entityId = log['entity_id'] as String? ?? '';
    final userName = log['user_name'] as String? ?? 'مستخدم';
    final timestamp = log['timestamp'] as String? ?? '';
    final newState = log['new_state'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.history_edu_rounded, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('تفاصيل حركة التدقيق المسجلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuditDetailRow('نوع الحركة / العملية:', _getActionArabicTitle(action)),
              _buildAuditDetailRow('التصنيف:', _getEntityArabicTitle(entity)),
              if (entityId.isNotEmpty)
                _buildAuditDetailRow('الرقم المرجعي المختصر:', _formatCleanArabicReference(entity, entityId)),
              _buildAuditDetailRow('المستخدم المنفذ:', userName),
              _buildAuditDetailRow('وقت العملية:', _formatTimestamp(timestamp)),
              const Divider(height: 24),
              const Text('بيان وتفاصيل العملية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
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
              if (entityId.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('المعرف التقني للنظام (معلومات متقدمة)', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                  children: [
                    Row(
                      children: [
                        Expanded(child: SelectableText('معرف السجل: $entityId', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: entityId));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المعرف التقني')));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildAuditDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.lightTextSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      return DateFormat('yyyy/MM/dd • hh:mm a').format(dt);
    } catch (_) {
      return ts;
    }
  }

  String _formatCleanArabicReference(String entityName, String entityId) {
    if (entityId.isEmpty) return '';
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
      return 'حركة #${entityId.substring(entityId.length - 6)}';
    }
    return '#$entityId';
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
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
