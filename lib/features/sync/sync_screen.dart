import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/sync/outbox_manager.dart';
import '../../core/sync/lan_sync_protocol.dart';
import '../../core/sync/lan_sync_server.dart';
import '../../core/sync/lan_sync_client.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Device Role: 'SERVER' or 'CLIENT'
  String _deviceRole = 'SERVER';

  // Server state
  bool _isServerRunning = false;
  List<String> _serverIps = [];
  final TextEditingController _serverPortCtrl = TextEditingController(text: '7070');

  // Client state
  final TextEditingController _clientServerIpCtrl = TextEditingController();
  final TextEditingController _clientPortCtrl = TextEditingController(text: '7070');
  final TextEditingController _clientNodeIdCtrl = TextEditingController();
  bool _clientAutoSync = true;
  bool _isTestingPing = false;
  LanPingResult? _pingResult;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverPortCtrl.dispose();
    _clientServerIpCtrl.dispose();
    _clientPortCtrl.dispose();
    _clientNodeIdCtrl.dispose();
    super.dispose();
  }

  void _loadInitialConfig() async {
    final db = ref.read(databaseServiceProvider);
    try {
      final roleRow = db.select("SELECT value FROM system_settings WHERE key = 'sync_device_role' LIMIT 1");
      if (roleRow.isNotEmpty) {
        _deviceRole = roleRow.first['value'] as String;
      }

      final server = ref.read(lanSyncServerProvider);
      _isServerRunning = server.isRunning;
      _serverPortCtrl.text = server.port.toString();

      final client = ref.read(lanSyncClientProvider);
      _clientServerIpCtrl.text = client.serverHost;
      _clientPortCtrl.text = client.serverPort.toString();
      _clientNodeIdCtrl.text = client.localNodeId;
      _clientAutoSync = client.isAutoSyncEnabled;

      // Discover real local IPs
      final ips = await LanSyncServer.getLocalIpAddresses();
      if (mounted) {
        setState(() {
          _serverIps = ips;
        });
      }
    } catch (_) {}
  }

  void _saveRole(String newRole) {
    setState(() => _deviceRole = newRole);
    final db = ref.read(databaseServiceProvider);
    try {
      db.execute('''
        INSERT OR REPLACE INTO system_settings (key, value, updated_at)
        VALUES ('sync_device_role', ?, datetime('now'))
      ''', [newRole]);
    } catch (_) {}
  }

  // --- SERVER ACTIONS ---
  Future<void> _toggleServer(bool start) async {
    final server = ref.read(lanSyncServerProvider);
    final port = int.tryParse(_serverPortCtrl.text.trim()) ?? 7070;

    if (start) {
      final success = await server.start(port: port);
      if (mounted) {
        setState(() => _isServerRunning = server.isRunning);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تشغيل سيرفر المزامنة المركزي بنجاح على المنفذ $port! جاهز لاستقبال بيانات الكاشيرات.'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل بدء السيرفر: المنفذ $port قد يكون قيد الاستخدام بواسطة برنامج آخر.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } else {
      await server.stop();
      if (mounted) {
        setState(() => _isServerRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إيقاف سيرفر المزامنة المركزي.')),
        );
      }
    }
  }

  // --- CLIENT ACTIONS ---
  Future<void> _testPing() async {
    final client = ref.read(lanSyncClientProvider);
    final host = _clientServerIpCtrl.text.trim();
    final port = int.tryParse(_clientPortCtrl.text.trim()) ?? 7070;

    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان IP الخاص بالخادم المركزي أولاً'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _isTestingPing = true;
      _pingResult = null;
    });

    final res = await client.pingServer(host: host, port: port);

    if (mounted) {
      setState(() {
        _isTestingPing = false;
        _pingResult = res;
      });
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الاتصال بالخادم المركزي بنجاح! سرعة الاستجابة: ${res.latencyMs}ms'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الاتصال: ${res.error ?? "تأكد من تشغيل السيرفر على الجهاز الأساسي"}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _saveClientConfig() {
    final client = ref.read(lanSyncClientProvider);
    final host = _clientServerIpCtrl.text.trim();
    final port = int.tryParse(_clientPortCtrl.text.trim()) ?? 7070;
    final nodeId = _clientNodeIdCtrl.text.trim();

    client.configure(
      serverHost: host,
      serverPort: port,
      autoSync: _clientAutoSync,
      nodeId: nodeId.isNotEmpty ? nodeId : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ إعدادات المحطة الفرعية بنجاح وتفعيل الربط التلقائي!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _triggerManualSync() async {
    final client = ref.read(lanSyncClientProvider);
    final outbox = ref.read(outboxManagerProvider);

    setState(() => _isSyncing = true);

    outbox.getPendingBatch();
    final res = await client.syncNow();

    if (mounted) {
      setState(() => _isSyncing = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.syncedCount > 0
                  ? 'تمت مزامنة وترحيل ${res.syncedCount} حركة بنجاح إلى الخادم المركزي!'
                  : 'جميع الحركات متزامنة مسبقاً! تم فحص وتحديث البيانات من الخادم بنجاح.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في المزامنة: ${res.error ?? "تعذر الوصول للخادم"} — العمليات محفوظة محلياً'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final outbox = ref.watch(outboxManagerProvider);
    final syncService = ref.watch(lanSyncServiceProvider);
    final stats = outbox.getStats();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المزامنة والربط الشبكي المحلي — Offline-First & LAN Multi-Terminal Sync'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings_ethernet_rounded), text: 'التحكم بالربط والشبكة (LAN Hub)'),
            Tab(icon: Icon(Icons.outbox_rounded), text: 'صندوق العمليات الصادرة (Outbox)'),
            Tab(icon: Icon(Icons.history_edu_rounded), text: 'سجل حركات الاستقبال (Server Log)'),
            Tab(icon: Icon(Icons.shield_rounded), text: 'قواعد حماية البيانات (Conflict Rules)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildControlTab(context),
          _buildOutboxTab(context, outbox, syncService, stats),
          _buildServerLogsTab(context),
          _buildConflictRulesTab(context),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: LAN CONTROL & ROLE SETUP
  // -------------------------------------------------------------
  Widget _buildControlTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Role Selector
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices_other_rounded, color: AppColors.brandPrimary, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'تحديد دور هذا الجهاز في المنشأة (Device Role)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اختر ما إذا كان هذا الجهاز هو الخادم المالي المركزي الرئيسي الذي يخزن قاعدة البيانات المركزية، أو أنه كاشير فرعي إضافي ينقل فواتيره عبر الشبكة.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.dns_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('الجهاز الأساسي / الخادم المركزي (Primary Server)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          selected: _deviceRole == 'SERVER',
                          selectedColor: AppColors.brandPrimary.withValues(alpha: 0.15),
                          onSelected: (val) {
                            if (val) _saveRole('SERVER');
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ChoiceChip(
                          label: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.point_of_sale_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('كاشير فرعي / محطة إضافية (Secondary POS Terminal)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          selected: _deviceRole == 'CLIENT',
                          selectedColor: AppColors.brandAccent.withValues(alpha: 0.15),
                          onSelected: (val) {
                            if (val) _saveRole('CLIENT');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Role-specific Panel
          if (_deviceRole == 'SERVER') _buildServerModeCard(context) else _buildClientModeCard(context),
        ],
      ),
    );
  }

  // --- SERVER MODE CARD ---
  Widget _buildServerModeCard(BuildContext context) {
    final server = ref.watch(lanSyncServerProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isServerRunning ? AppColors.success : Colors.grey).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.dns_rounded,
                    color: _isServerRunning ? AppColors.success : Colors.grey,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سيرفر المزامنة والربط الشبكي المركزي',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isServerRunning
                          ? 'السيرفر نشط الآن وجاهز لاستقبال فواتير وحركات الكاشيرات الفرعية'
                          : 'السيرفر متوقف حالياً. قم بتشغيله ليتمكن الكاشير الفرعي من الاتصال والمزامنة',
                      style: TextStyle(
                        color: _isServerRunning ? AppColors.success : Colors.grey.shade700,
                        fontWeight: _isServerRunning ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Switch(
                  value: _isServerRunning,
                  activeThumbColor: AppColors.success,
                  onChanged: (val) => _toggleServer(val),
                ),
              ],
            ),
            const Divider(height: 32),

            // Server Local LAN IP Addresses for Easy Setup on Secondary Computers
            const Text(
              'عناوين هذا الجهاز على الشبكة المحلية (LAN IPv4 Addresses):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'اكتب أحد هذه العناوين في شاشة المزامنة على جهاز الكاشير الثاني لربطه بهذا الجهاز الأساسي مباشرة:',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),

            if (_serverIps.isEmpty)
              const Text('جاري فحص كروت الشبكة...')
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: _serverIps.map((ip) {
                  final fullUrl = 'http://$ip:${_serverPortCtrl.text.trim()}';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_rounded, size: 18, color: Colors.blue),
                        const SizedBox(width: 8),
                        SelectableText(
                          fullUrl,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'نسخ عنوان IP',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: ip));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم نسخ عنوان IP: $ip')),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 24),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _serverPortCtrl,
                    decoration: const InputDecoration(
                      labelText: 'منفذ السيرفر (Port)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_isServerRunning,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _toggleServer(!_isServerRunning),
                  icon: Icon(_isServerRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_isServerRunning ? 'إيقاف السيرفر' : 'تشغيل السيرفر الآن'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isServerRunning ? AppColors.error : AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            // Metrics Summary Row
            Row(
              children: [
                Expanded(
                  child: _statMiniCard(
                    'الكاشيرات المتصلة',
                    '${server.connectedClientsCount}',
                    Icons.devices_rounded,
                    Colors.indigo,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _statMiniCard(
                    'عمليات الاستقبال المنفذة',
                    '${server.syncLogs.length}',
                    Icons.move_to_inbox_rounded,
                    AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- CLIENT MODE CARD ---
  Widget _buildClientModeCard(BuildContext context) {
    final client = ref.watch(lanSyncClientProvider);

    return Column(
      children: [
        // Live Network State Banner
        StreamBuilder<ClientSyncState>(
          stream: client.stateStream,
          initialData: client.state,
          builder: (context, snapshot) {
            final st = snapshot.data ?? ClientSyncState.offline;
            Color bannerColor = Colors.orange;
            IconData bannerIcon = Icons.wifi_off_rounded;
            String bannerTitle = 'وضع العمل المستقل دون اتصال (Offline-First)';
            String bannerSub =
                'الكاشير يعمل بكامل وظائفه الطبيعية دون أي تعطيل. سيتم ترحيل كافة الفواتير تلقائياً فور توفر الخادم المركزي.';

            if (st == ClientSyncState.online) {
              bannerColor = AppColors.success;
              bannerIcon = Icons.cloud_done_rounded;
              bannerTitle = 'متصل بالخادم المركزي بنجاح (Online)';
              bannerSub =
                  'النظام ينقل أي فواتير جديدة للخادم فوراً بالخلفية. سرعة الاستجابة: ${client.lastLatencyMs}ms';
            } else if (st == ClientSyncState.syncing) {
              bannerColor = Colors.blue;
              bannerIcon = Icons.sync_rounded;
              bannerTitle = 'جاري ترحيل وتحديث البيانات مع الخادم المركزي...';
              bannerSub = 'يتم الآن نقل الفواتير المعلقة وتحديث بيانات الأصناف والأسعار.';
            } else if (st == ClientSyncState.unconfigured) {
              bannerColor = Colors.grey;
              bannerIcon = Icons.settings_ethernet_rounded;
              bannerTitle = 'إعدادات الخادم المركزي غير مكتملة';
              bannerSub = 'يرجى إدخال عنوان IP الخاص بالجهاز الأساسي والضغط على "فحص الربط" ثم "حفظ الإعدادات".';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: bannerColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(bannerIcon, color: bannerColor, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bannerTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: bannerColor)),
                        const SizedBox(height: 4),
                        Text(bannerSub, style: const TextStyle(fontSize: 12, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Settings & Actions Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cast_connected_rounded, color: AppColors.brandAccent, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'إعدادات الربط بالجهاز الأساسي (Primary Server Connection)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Server IP & Port Fields
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _clientServerIpCtrl,
                        decoration: const InputDecoration(
                          labelText: 'عنوان IP الخاص بالجهاز الأساسي (مثال: 192.168.1.15)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lan_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _clientPortCtrl,
                        decoration: const InputDecoration(
                          labelText: 'المنفذ (Port)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _clientNodeIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'معرف هذه المحطة (POS Node ID)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Auto Sync Switch
                SwitchListTile(
                  title: const Text('المزامنة التلقائية بالخلفية وإعادة الاتصال الذاتي (Auto-Sync & Catch-up)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                    'عند تفعيلها، يفحص النظام حالة الخادم كل 10 ثوانٍ تلقائياً؛ بمجرد عودة الخادم للعمل ينقل كل الفواتير التي تمت أثناء التوقف.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _clientAutoSync,
                  activeThumbColor: AppColors.brandAccent,
                  onChanged: (val) {
                    setState(() => _clientAutoSync = val);
                  },
                ),
                const SizedBox(height: 20),

                // Ping Result Banner
                if (_pingResult != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_pingResult!.isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_pingResult!.isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _pingResult!.isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: _pingResult!.isSuccess ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _pingResult!.isSuccess
                                ? 'تم فحص الربط بنجاح! اسم الخادم: ${_pingResult!.serverName ?? "الخادم المركزي"} | زمن الاستجابة: ${_pingResult!.latencyMs}ms'
                                : 'فشل فحص الربط: ${_pingResult!.error}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _pingResult!.isSuccess ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Action Buttons
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isTestingPing ? null : _testPing,
                      icon: _isTestingPing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.network_check_rounded),
                      label: const Text('فحص الربط بالجهاز الأساسي (Ping Test)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _triggerManualSync,
                      icon: _isSyncing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded),
                      label: const Text('مزامنة فورية الآن (Sync Now)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _saveClientConfig,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('حفظ إعدادات الربط'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: OUTBOX QUEUE
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
                child: _statMiniCard('معلق بانتظار الإرسال', '${stats.pendingCount}', Icons.hourglass_top_rounded, Colors.orange),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statMiniCard('متزامن ومؤكد بالخادم', '${stats.syncedCount}', Icons.cloud_done_rounded, AppColors.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statMiniCard('تعارضات بحاجة لمراجعة', '${stats.conflictCount}', Icons.warning_amber_rounded, Colors.purple),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statMiniCard('فشل / قيد الإعادة', '${stats.failedCount}', Icons.error_outline_rounded, AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action Toolbar
          Row(
            children: [
              Text('سجل قائمة الانتظار الحالية (${pendingItems.length} حركة معلقة)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : _triggerManualSync,
                icon: _isSyncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync_rounded),
                label: const Text('ترحيل المعلق الآن إلى الخادم (Push Now)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandAccent,
                  foregroundColor: Colors.white,
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
                          const Text('الصندوق الصادر فارغ كلياً. جميع الفواتير والحركات مرحلة ومتزامنة بالكامل.',
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(item.status.code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                backgroundColor: _getStatusColor(item.status).withValues(alpha: 0.15),
                                side: BorderSide.none,
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.info_outline_rounded, size: 18),
                                tooltip: 'عرض محتوى الحركة',
                                onPressed: () => _showPayloadDialog(context, item),
                              ),
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

  void _showPayloadDialog(BuildContext context, OutboxItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('بيانات الحركة: ${item.entityType} (${item.entityId})'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              item.payload.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: SERVER INCOMING LOGS
  // -------------------------------------------------------------
  Widget _buildServerLogsTab(BuildContext context) {
    final server = ref.watch(lanSyncServerProvider);
    final logs = server.syncLogs;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('سجل حركات الاستقبال على الخادم المركزي (${logs.length} عمليات)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث السجل',
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.inbox_rounded, size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('لا توجد عمليات استقبال مسجلة بعد. عند مزامنة أي كاشير ستظهر تفاصيلها هنا فوراً.'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (log.isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                            child: Icon(
                              log.isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                              color: log.isSuccess ? AppColors.success : AppColors.error,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(log.clientNodeId, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Text('(${log.clientIp})', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          subtitle: Text(log.details),
                          trailing: Text(
                            DateFormat('HH:mm:ss').format(log.timestamp),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
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

  // -------------------------------------------------------------
  // TAB 4: CONFLICT & ACCOUNTING RULES
  // -------------------------------------------------------------
  Widget _buildConflictRulesTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('استراتيجية حماية البيانات وحل التعارضات والمحاسبة',
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
            title: '3. نمط صندوق الصادر المضمون (Guaranteed Outbox Store & Forward)',
            icon: Icons.mark_email_read_rounded,
            color: Colors.green.shade700,
            description:
                'كل عملية تجارية تُسجل محلياً في قاعدة SQLite في نفس المعاملة الذرية (Atomic Transaction). في حال انقطاع الشبكة أو إغلاق الخادم الرئيسي، يستمر الكاشير بالعمل دون توقف. وبمجرد تشغيل الخادم مجدداً، يتم الربط التلقائي وترحيل كل العمليات المتراكمة دون أي فقد في البيانات.',
          ),
        ],
      ),
    );
  }

  Widget _statMiniCard(String label, String value, IconData icon, Color color) {
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
}
