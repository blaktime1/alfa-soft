import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../data/local/database_service.dart';
import 'lan_sync_protocol.dart';
import 'outbox_manager.dart';

enum ClientSyncState {
  unconfigured('غير مضبوط'),
  offline('غير متصل بالخادم (يعمل محلياً)'),
  connecting('جاري الاتصال...'),
  online('متصل بالخادم الرئيسي'),
  syncing('جاري مزامنة ونقل البيانات...'),
  error('خطأ في الاتصال');

  final String label;
  const ClientSyncState(this.label);
}

class LanPingResult {
  final bool isSuccess;
  final int latencyMs;
  final String? serverName;
  final String? serverNodeId;
  final String? error;

  const LanPingResult({
    required this.isSuccess,
    this.latencyMs = 0,
    this.serverName,
    this.serverNodeId,
    this.error,
  });
}

class LanPushResult {
  final bool isSuccess;
  final int syncedCount;
  final int conflictCount;
  final String? error;

  const LanPushResult({
    required this.isSuccess,
    this.syncedCount = 0,
    this.conflictCount = 0,
    this.error,
  });
}

/// Real LAN Sync Client for Secondary POS Terminals
class LanSyncClient {
  final DatabaseService _db;
  final OutboxManager _outboxManager;
  final LanSyncService _syncService;

  String _serverHost = '';
  int _serverPort = 7070;
  String _localNodeId = 'NODE-POS-01';
  bool _isAutoSyncEnabled = true;

  ClientSyncState _state = ClientSyncState.unconfigured;
  int _lastLatencyMs = 0;
  DateTime? _lastSyncTime;
  String? _lastError;
  Timer? _bgTimer;
  bool _isSyncRunning = false;

  final StreamController<ClientSyncState> _stateController = StreamController<ClientSyncState>.broadcast();

  LanSyncClient({
    required DatabaseService db,
    OutboxManager? outboxManager,
    LanSyncService? syncService,
  })  : _db = db,
        _outboxManager = outboxManager ?? OutboxManager(db),
        _syncService = syncService ?? LanSyncService(db: db, outboxManager: outboxManager ?? OutboxManager(db)) {
    _loadSettings();
  }

  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get localNodeId => _localNodeId;
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;
  ClientSyncState get state => _state;
  int get lastLatencyMs => _lastLatencyMs;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;
  Stream<ClientSyncState> get stateStream => _stateController.stream;

  void _loadSettings() {
    try {
      final ipRow = _db.select("SELECT value FROM system_settings WHERE key = 'sync_server_ip' LIMIT 1");
      if (ipRow.isNotEmpty) _serverHost = ipRow.first['value'] as String;

      final portRow = _db.select("SELECT value FROM system_settings WHERE key = 'sync_server_port' LIMIT 1");
      if (portRow.isNotEmpty) _serverPort = int.tryParse(portRow.first['value'] as String) ?? 7070;

      final nodeRow = _db.select("SELECT value FROM system_settings WHERE key = 'sync_node_id' LIMIT 1");
      if (nodeRow.isNotEmpty) {
        _localNodeId = nodeRow.first['value'] as String;
      } else {
        _localNodeId = 'POS-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        _saveSetting('sync_node_id', _localNodeId);
      }

      final autoRow = _db.select("SELECT value FROM system_settings WHERE key = 'sync_auto_enabled' LIMIT 1");
      if (autoRow.isNotEmpty) _isAutoSyncEnabled = autoRow.first['value'] == '1' || autoRow.first['value'] == 'true';

      final lastTimeRow = _db.select("SELECT value FROM system_settings WHERE key = 'sync_last_timestamp' LIMIT 1");
      if (lastTimeRow.isNotEmpty) _lastSyncTime = DateTime.tryParse(lastTimeRow.first['value'] as String);

      if (_serverHost.isNotEmpty) {
        _setState(ClientSyncState.offline);
      } else {
        _setState(ClientSyncState.unconfigured);
      }
    } catch (_) {}
  }

  void _saveSetting(String key, String value) {
    try {
      _db.execute('''
        INSERT OR REPLACE INTO system_settings (key, value, updated_at)
        VALUES (?, ?, datetime('now'))
      ''', [key, value]);
    } catch (_) {}
  }

  void configure({
    required String serverHost,
    required int serverPort,
    bool? autoSync,
    String? nodeId,
  }) {
    _serverHost = serverHost.trim();
    _serverPort = serverPort;
    if (autoSync != null) _isAutoSyncEnabled = autoSync;
    if (nodeId != null && nodeId.trim().isNotEmpty) _localNodeId = nodeId.trim();

    _saveSetting('sync_server_ip', _serverHost);
    _saveSetting('sync_server_port', '$_serverPort');
    _saveSetting('sync_auto_enabled', _isAutoSyncEnabled ? '1' : '0');
    _saveSetting('sync_node_id', _localNodeId);

    if (_serverHost.isEmpty) {
      _setState(ClientSyncState.unconfigured);
      stopBackgroundSync();
    } else {
      _setState(ClientSyncState.offline);
      if (_isAutoSyncEnabled) {
        startBackgroundSync();
      }
    }
  }

  void _setState(ClientSyncState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  /// Real Ping check to the Primary Server measuring actual millisecond network latency
  Future<LanPingResult> pingServer({String? host, int? port}) async {
    final targetHost = host ?? _serverHost;
    final targetPort = port ?? _serverPort;

    if (targetHost.isEmpty) {
      return const LanPingResult(
        isSuccess: false,
        error: 'لم يتم تحديد عنوان IP الخاص بالخادم المركزي',
      );
    }

    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse('http://$targetHost:$targetPort/api/ping');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      stopwatch.stop();

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decodeStream(response);
        final data = jsonDecode(body) as Map<String, dynamic>;
        _lastLatencyMs = stopwatch.elapsedMilliseconds;
        _lastError = null;
        _setState(ClientSyncState.online);

        return LanPingResult(
          isSuccess: true,
          latencyMs: _lastLatencyMs,
          serverName: data['server_name'] as String?,
          serverNodeId: data['node_id'] as String?,
        );
      } else {
        stopwatch.stop();
        final err = 'استجاب الخادم برمز خطأ: ${response.statusCode}';
        _lastError = err;
        _setState(ClientSyncState.error);
        return LanPingResult(isSuccess: false, error: err);
      }
    } catch (e) {
      stopwatch.stop();
      final err = 'تعذر الاتصال بالخادم على $targetHost:$targetPort ($e)';
      _lastError = err;
      _setState(ClientSyncState.offline);
      return LanPingResult(isSuccess: false, error: err);
    } finally {
      client.close();
    }
  }

  /// Pushes all pending outbox records to the Primary Server
  Future<LanPushResult> pushPendingOutbox({int limit = 50}) async {
    if (_serverHost.isEmpty) {
      return const LanPushResult(isSuccess: false, error: 'عنوان الخادم غير محدد');
    }

    final pending = _outboxManager.getPendingBatch(limit: limit);
    if (pending.isEmpty) {
      return const LanPushResult(isSuccess: true, syncedCount: 0);
    }

    final packet = _syncService.createOutboxPacket(localNodeId: _localNodeId, limit: limit);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    try {
      final uri = Uri.parse('http://$_serverHost:$_serverPort/api/sync/push');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final payloadJson = jsonEncode(packet.toMap());
      request.write(payloadJson);

      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decodeStream(response);
        final resData = jsonDecode(body) as Map<String, dynamic>;
        final ackList = List<String>.from(resData['acknowledged_ids'] as List? ?? []);

        if (ackList.isNotEmpty) {
          _outboxManager.markSynced(ackList);
        }

        final count = resData['applied_count'] as int? ?? ackList.length;
        final conflicts = resData['conflict_count'] as int? ?? 0;

        _lastSyncTime = DateTime.now().toUtc();
        _saveSetting('sync_last_timestamp', _lastSyncTime!.toIso8601String());

        return LanPushResult(isSuccess: true, syncedCount: count, conflictCount: conflicts);
      } else {
        final err = 'فشل استلام الحزمة من الخادم، كود الحالة: ${response.statusCode}';
        _lastError = err;
        return LanPushResult(isSuccess: false, error: err);
      }
    } catch (e) {
      _lastError = 'خطأ أثناء إرسال البيانات للخادم: $e';
      return LanPushResult(isSuccess: false, error: _lastError);
    } finally {
      client.close();
    }
  }

  /// Pulls remote master data (products, customers, suppliers) from Primary Server
  Future<bool> pullServerUpdates() async {
    if (_serverHost.isEmpty) return false;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final sinceParam = _lastSyncTime != null
          ? _lastSyncTime!.subtract(const Duration(seconds: 2)).toIso8601String()
          : '1970-01-01T00:00:00.000Z';
      final uri = Uri.parse('http://$_serverHost:$_serverPort/api/sync/pull?since=$sinceParam');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decodeStream(response);
        final data = jsonDecode(body) as Map<String, dynamic>;

        final products = List<Map<String, dynamic>>.from(data['products'] as List? ?? []);
        final customers = List<Map<String, dynamic>>.from(data['customers'] as List? ?? []);
        final suppliers = List<Map<String, dynamic>>.from(data['suppliers'] as List? ?? []);

        _applyPulledData('products', products);
        _applyPulledData('customers', customers);
        _applyPulledData('suppliers', suppliers);

        _lastSyncTime = DateTime.now().toUtc();
        _saveSetting('sync_last_timestamp', _lastSyncTime!.toIso8601String());
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void _applyPulledData(String table, List<Map<String, dynamic>> records) {
    if (records.isEmpty) return;
    _db.transaction((tx) {
      for (final r in records) {
        final keys = r.keys.toList();
        final cols = keys.join(', ');
        final placeholders = List.filled(keys.length, '?').join(', ');
        final updateSets = keys.where((k) => k != 'id').map((k) => '$k = excluded.$k').join(', ');
        final vals = keys.map((k) => r[k]).toList();
        try {
          if (keys.contains('id') && updateSets.isNotEmpty) {
            tx.execute('''
              INSERT INTO $table ($cols) VALUES ($placeholders)
              ON CONFLICT(id) DO UPDATE SET $updateSets
            ''', vals);
          } else {
            tx.execute('INSERT OR REPLACE INTO $table ($cols) VALUES ($placeholders)', vals);
          }
        } catch (_) {}
      }
    });
  }

  /// Executes full sync: pushes pending outbox, then pulls server updates
  Future<LanPushResult> syncNow() async {
    if (_isSyncRunning) {
      return const LanPushResult(isSuccess: false, error: 'المزامنة قيد التشغيل بالفعل');
    }
    _isSyncRunning = true;
    _setState(ClientSyncState.syncing);

    try {
      final ping = await pingServer();
      if (!ping.isSuccess) {
        _setState(ClientSyncState.offline);
        return LanPushResult(isSuccess: false, error: ping.error);
      }

      final pushResult = await pushPendingOutbox();
      await pullServerUpdates();

      _setState(ClientSyncState.online);
      return pushResult;
    } finally {
      _isSyncRunning = false;
    }
  }

  /// Fast fire-and-forget push triggered right after invoice checkout
  Future<void> triggerImmediatePush() async {
    if (!_isAutoSyncEnabled || _serverHost.isEmpty || _isSyncRunning) return;
    try {
      await pushPendingOutbox(limit: 20);
    } catch (_) {}
  }

  /// Background Auto-Sync Worker with automatic reconnection and catch-up
  void startBackgroundSync({Duration interval = const Duration(seconds: 10)}) {
    _bgTimer?.cancel();
    if (!_isAutoSyncEnabled || _serverHost.isEmpty) return;

    _bgTimer = Timer.periodic(interval, (_) async {
      if (_isSyncRunning || _serverHost.isEmpty || !_isAutoSyncEnabled) return;

      final ping = await pingServer();
      if (ping.isSuccess) {
        // If server is back online and there are pending items from offline operations, push them!
        final pending = _outboxManager.getPendingBatch(limit: 1);
        if (pending.isNotEmpty) {
          await syncNow();
        }
      }
    });
  }

  void stopBackgroundSync() {
    _bgTimer?.cancel();
    _bgTimer = null;
  }

  void dispose() {
    stopBackgroundSync();
    _stateController.close();
  }
}
