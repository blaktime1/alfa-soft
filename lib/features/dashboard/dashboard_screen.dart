import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        SELECT al.action, al.entity_name, al.timestamp, al.user_id, al.new_state,
               COALESCE(u.full_name, u.username, 'مستخدم النظام') as user_name
        FROM audit_logs al
        LEFT JOIN users u ON al.user_id = u.id
        ORDER BY al.timestamp DESC 
        LIMIT 6
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
                              final userName = log['user_name'] as String? ?? 'مستخدم';
                              final timestamp = log['timestamp'] as String? ?? '';
                              final newState = log['new_state'] as String? ?? '';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(
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
                                          Text(
                                            '${_getActionArabicTitle(action)} (${_getEntityArabicTitle(entity)})',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          if (newState.isNotEmpty)
                                            Text(
                                              newState.replaceAll('Invoice: ', 'فاتورة: ').replaceAll('Total: ', 'الإجمالي: '),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.75)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          Text(
                                            '$timestamp • المستخدم: $userName',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.5)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
    if (upper == 'PURCHASE_GRN') return 'استلام بضاعة (GRN)';
    if (upper == 'POST_JOURNAL_ENTRY') return 'ترحيل قيد محاسبي';
    if (upper == 'REVERSE_JOURNAL_ENTRY') return 'عكس قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER' || upper == 'POST_EXPENSE' || upper == 'CREATE_EXPENSE') return 'سند صرف مصروفات';
    if (upper == 'SALARY_ADVANCE' || upper == 'POST_ADVANCE' || upper == 'CREATE_ADVANCE') return 'صرف سلفة موظف';
    if (upper == 'PAYROLL' || upper == 'GENERATE_PAYROLL') return 'توليد مسير رواتب';
    if (upper == 'APPROVE_PAYROLL') return 'اعتماد مسير رواتب';
    if (upper == 'POST_PAYROLL') return 'ترحيل مسير رواتب';
    if (upper == 'SALE_ISSUE') return 'صرف مخزني لمبيعات';
    if (upper == 'TRANSFER_DISPATCH') return 'إرسال تحويل مخزني';
    if (upper == 'TRANSFER_RECEIPT') return 'استلام تحويل مخزني';
    if (upper == 'CREATE_USER') return 'إضافة مستخدم جديد';
    if (upper == 'UPDATE_USER') return 'تعديل مستخدم';
    if (upper == 'BACKUP_DATABASE') return 'نسخ احتياطي للبيانات';
    if (upper == 'LAN_SYNC_PUSH') return 'مزامنة شبكة محلية (إرسال)';
    if (upper == 'LAN_SYNC_PULL') return 'مزامنة شبكة محلية (استقبال)';
    return action;
  }

  String _getEntityArabicTitle(String entity) {
    final upper = entity.toUpperCase();
    if (upper == 'SALES_INVOICE' || upper == 'INVOICE') return 'فاتورة مبيعات';
    if (upper == 'PURCHASE_INVOICE') return 'فاتورة مشتريات';
    if (upper == 'PURCHASE_GRN') return 'استلام بضاعة (GRN)';
    if (upper == 'JOURNAL_ENTRY') return 'قيد محاسبي';
    if (upper == 'EXPENSE_VOUCHER') return 'سند صرف';
    if (upper == 'SALARY_ADVANCE') return 'سلفة موظف';
    if (upper == 'PAYROLL_RUN') return 'مسير رواتب';
    if (upper == 'PRODUCT') return 'منتج / صنف';
    if (upper == 'USER') return 'مستخدم';
    if (upper == 'CUSTOMER') return 'عميل';
    if (upper == 'SUPPLIER') return 'مورد';
    if (upper == 'EMPLOYEE') return 'موظف';
    if (upper == 'SYSTEM_SETTINGS' || upper == 'SETTINGS') return 'إعدادات النظام';
    return entity;
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
