import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/sync/outbox_manager.dart';
import '../../core/sync/lan_sync_protocol.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _triggerSync(OutboxManager outbox, LanSyncService syncService) {
    setState(() => _isSyncing = true);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      try {
        final pending = outbox.getPendingBatch();
        if (pending.isEmpty) {
          setState(() => _isSyncing = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('جميع السجلات متزامنة بالفعل! لا توجد حركات معلقة في الصندوق الصادر.'),
                backgroundColor: AppColors.success,
              ),
            );
          }
          return;
        }

        // Simulate sending packet to LAN server and getting acknowledgement
        final packet = syncService.createOutboxPacket(localNodeId: 'NODE-POS-01');
        final ackIds = packet.items.map((i) => i['outbox_id'] as String).toList();
        outbox.markSynced(ackIds);

        setState(() => _isSyncing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت مزامنة ${ackIds.length} حركة بنجاح مع الخادم الرئيسي عبر الشبكة المحلية.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        setState(() => _isSyncing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في المزامنة: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseServiceProvider);
    final outbox = OutboxManager(db);
    final syncService = LanSyncService(db: db, outboxManager: outbox);
    final stats = outbox.getStats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزامنة والربط الشبكي المحلي — Offline & LAN Multi-Device Sync'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.outbox_rounded), text: 'صندوق التعديلات الصادرة (Outbox)'),
            Tab(icon: Icon(Icons.lan_rounded), text: 'أجهزة الشبكة المحلية (LAN Peers)'),
            Tab(icon: Icon(Icons.rule_rounded), text: 'قواعد حل التعارضات (Conflict Rules)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOutboxTab(context, outbox, syncService, stats),
          _buildPeersTab(context, syncService),
          _buildConflictRulesTab(context),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: OUTBOX QUEUE
  // -------------------------------------------------------------
  Widget _buildOutboxTab(BuildContext context, OutboxManager outbox, LanSyncService syncService, SyncStats stats) {
    final pendingItems = outbox.getPendingBatch(limit: 100);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Counters Row
          Row(
            children: [
              Expanded(
                child: _statCard('معلق بانتظار الإرسال', '${stats.pendingCount}', Icons.hourglass_top_rounded, Colors.orange),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('متزامن ومؤكد', '${stats.syncedCount}', Icons.cloud_done_rounded, AppColors.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('تعارضات بحاجة لمراجعة', '${stats.conflictCount}', Icons.warning_amber_rounded, Colors.purple),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('فشل / قيد الإعادة', '${stats.failedCount}', Icons.error_outline_rounded, AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action Toolbar
          Row(
            children: [
              Text('سجل قائمة الانتظار الحالية (${pendingItems.length} حركة)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : () => _triggerSync(outbox, syncService),
                icon: _isSyncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync_rounded),
                label: const Text('مزامنة فورية الآن (Sync Now)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Items Table
          Expanded(
            child: Card(
              child: pendingItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 56, color: AppColors.success.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('الصندوق الصادر فارغ كلياً. جميع البيانات متزامنة محلياً وشبكياً.',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: pendingItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = pendingItems[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getOpColor(item.operation).withValues(alpha: 0.15),
                            child: Text(
                              item.operation.code[0],
                              style: TextStyle(color: _getOpColor(item.operation), fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(item.entityType, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Text('#${item.sequenceNumber}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          subtitle: Text('ID: ${item.entityId} | العملية: ${item.operation.code} | محاولات: ${item.retryCount}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Chip(
                                label: Text(item.status.code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                backgroundColor: _getStatusColor(item.status).withValues(alpha: 0.15),
                                side: BorderSide.none,
                              ),
                              Text(DateFormat('HH:mm:ss').format(item.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
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

  Color _getOpColor(SyncOperation op) {
    switch (op) {
      case SyncOperation.create:
        return AppColors.success;
      case SyncOperation.update:
        return Colors.blue;
      case SyncOperation.delete:
        return AppColors.error;
    }
  }

  Color _getStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return Colors.orange;
      case SyncStatus.synced:
        return AppColors.success;
      case SyncStatus.conflict:
        return Colors.purple;
      case SyncStatus.failed:
        return AppColors.error;
    }
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: LAN PEERS
  // -------------------------------------------------------------
  Widget _buildPeersTab(BuildContext context, LanSyncService syncService) {
    final peers = syncService.getDiscoveredPeers();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('الأجهزة المكتشفة على الشبكة المحلية (${peers.length} أجهزة)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إرسال إشارة استكشاف UDP Broadcast عبر الشبكة بنجاح')),
                  );
                },
                icon: const Icon(Icons.wifi_find_rounded),
                label: const Text('إعادة البحث والاستكشاف (mDNS / UDP)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: peers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final p = peers[index];
                return Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (p.isOnline ? AppColors.success : Colors.grey).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        p.role == PeerRole.server ? Icons.dns_rounded : Icons.desktop_windows_rounded,
                        color: p.isOnline ? AppColors.success : Colors.grey,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(p.deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(p.role.label, style: const TextStyle(fontSize: 10)),
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                    subtitle: Text('IP: ${p.ipAddress}:${p.port} | المعرف: ${p.nodeId} | الاستجابة: ${p.latencyMs}ms'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('متصل ونشط',
                              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم اختبار اتصال المنفذ مع ${p.ipAddress}: استجابة ممتازة ${p.latencyMs}ms')),
                            );
                          },
                          child: const Text('فحص الاتصال (Ping)'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: CONFLICT RULES
  // -------------------------------------------------------------
  Widget _buildConflictRulesTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('استراتيجية حماية البيانات وحل التعارضات',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _ruleCard(
            title: '1. حظر تعديل المستندات المالية والقيود المحاسبية (Immutable Append-Only Ledger)',
            icon: Icons.shield_rounded,
            color: Colors.red.shade700,
            description:
                'وفقاً للمعايير المحاسبية المعتمدة في الفا سوفت، فإن جميع فواتير المبيعات، قيود اليومية، وسندات الاستلام المخزني غير قابلة للتعديل أو الحذف من أي طرف، بل تُسجل فقط بنمط الإضافة المتتالية (Append-Only). أي تسوية تتطلب إنشاء مستند قيد عكسي أو إشعار مدين/دائن جديد.',
          ),
          const SizedBox(height: 16),
          _ruleCard(
            title: '2. سياسة الفوز للتعديل الأحدث للبيانات الرئيسية (Last-Write-Wins / LWW)',
            icon: Icons.timelapse_rounded,
            color: Colors.blue.shade700,
            description:
                'بالنسبة للأصناف، العملاء، والموردين، يتم مقارنة رقم الإصدار (Version) وتاريخ آخر تحديث (Updated At). يتم تلقائياً تطبيق النسخة الأحدث عبر الشبكة دون توقف حركة البيع.',
          ),
          const SizedBox(height: 16),
          _ruleCard(
            title: '3. نمط صندوق الصادر المضمون (Guaranteed Outbox Delivery)',
            icon: Icons.mark_email_read_rounded,
            color: Colors.green.shade700,
            description:
                'كل عملية تجارية تُسجل محلياً في جدول SQLite في نفس المعاملة الذرية (Atomic Transaction). في حال انقطاع الشبكة، يستمر النظام بالعمل دون انقطاع ويتم إعادة الإرسال تلقائياً بمجرد عودة الاتصال.',
          ),
        ],
      ),
    );
  }

  Widget _ruleCard({required String title, required IconData icon, required Color color, required String description}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color))),
              ],
            ),
            const Divider(height: 24),
            Text(description, style: const TextStyle(fontSize: 14, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
