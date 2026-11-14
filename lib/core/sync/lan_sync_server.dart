import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../data/local/database_service.dart';
import 'lan_sync_protocol.dart';
import 'outbox_manager.dart';

class ServerSyncLogItem {
  final String id;
  final String clientNodeId;
  final String clientIp;
  final int itemsCount;
  final DateTime timestamp;
  final bool isSuccess;
  final String details;

  const ServerSyncLogItem({
    required this.id,
    required this.clientNodeId,
    required this.clientIp,
    required this.itemsCount,
    required this.timestamp,
    required this.isSuccess,
    required this.details,
  });
}

/// Embedded HTTP Server for real LAN Synchronization on the Primary Machine
class LanSyncServer {
  final DatabaseService _db;
  final LanSyncService _syncService;

  HttpServer? _server;
  int _port = 7070;
  String _nodeId = 'NODE-SERVER-MAIN';
  String _serverName = 'الخادم المالي المركزي - الفا سوفت';
  final List<ServerSyncLogItem> _syncLogs = [];
  final Set<String> _connectedClients = {};

  LanSyncServer({
    required DatabaseService db,
    LanSyncService? syncService,
  })  : _db = db,
        _syncService = syncService ?? LanSyncService(db: db, outboxManager: OutboxManager(db));

  bool get isRunning => _server != null;
  int get port => _port;
  String get nodeId => _nodeId;
  String get serverName => _serverName;
  List<ServerSyncLogItem> get syncLogs => List.unmodifiable(_syncLogs);
  int get connectedClientsCount => _connectedClients.length;

  /// Detects real LAN IPv4 addresses of this machine (excluding loopback)
  static Future<List<String>> getLocalIpAddresses() async {
    final List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    if (ips.isEmpty) {
      ips.add('127.0.0.1');
    }
    return ips;
  }

  /// Starts the embedded HTTP Server
  Future<bool> start({int port = 7070, String? serverName, String? nodeId}) async {
    if (_server != null) return true;

    _port = port;
    if (serverName != null) _serverName = serverName;
    if (nodeId != null) _nodeId = nodeId;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server!.listen(
        _handleRequest,
        onError: (e) {
          _addLog('ERROR', '0.0.0.0', 0, false, 'خطأ في استقبال الطلبات: $e');
        },
      );
      return true;
    } catch (e) {
      _server = null;
      return false;
    }
  }

  /// Stops the server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }

  void _handleRequest(HttpRequest request) async {
    // Add CORS headers for web/desktop integration
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, X-Node-Id');
    request.response.headers.contentType = ContentType.json;

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'مجهول';

    try {
      if (request.method == 'GET' && path == '/api/ping') {
        _handlePing(request);
      } else if (request.method == 'POST' && path == '/api/sync/push') {
        await _handlePush(request, clientIp);
      } else if (request.method == 'GET' && path == '/api/sync/pull') {
        _handlePull(request);
      } else if (request.method == 'GET' && path == '/api/server/status') {
        _handleStatus(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'المسار المطلوب غير موجود: $path'}));
        await request.response.close();
      }
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': 'خطأ داخلي في الخادم: $e'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  void _handlePing(HttpRequest request) {
    final responsePayload = {
      'status': 'ONLINE',
      'role': 'PRIMARY_SERVER',
      'server_name': _serverName,
      'node_id': _nodeId,
      'server_time': DateTime.now().toIso8601String(),
      'version': '1.0.0',
    };
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(responsePayload));
    request.response.close();
  }

  Future<void> _handlePush(HttpRequest request, String clientIp) async {
    final bodyString = await utf8.decodeStream(request);
    final data = jsonDecode(bodyString) as Map<String, dynamic>;

    final packet = SyncPacket(
      packetId: data['packet_id'] as String? ?? 'pkt_${DateTime.now().millisecondsSinceEpoch}',
      senderNodeId: data['sender_node_id'] as String? ?? 'UNKNOWN',
      timestamp: data['timestamp'] != null ? DateTime.parse(data['timestamp'] as String) : DateTime.now(),
      items: List<Map<String, dynamic>>.from(data['items'] as List? ?? []),
      checksum: data['checksum'] as String? ?? '',
    );

    _connectedClients.add('${packet.senderNodeId} ($clientIp)');

    final summary = _syncService.ingestPacket(packet);

    _addLog(
      packet.senderNodeId,
      clientIp,
      summary.totalReceived,
      true,
      'تم استقبال وتطبيق ${summary.appliedCount} حركة بنجاح (تعارضات: ${summary.conflictCount})',
    );

    final responsePayload = {
      'success': true,
      'total_received': summary.totalReceived,
      'applied_count': summary.appliedCount,
      'rejected_count': summary.rejectedCount,
      'conflict_count': summary.conflictCount,
      'acknowledged_ids': summary.acknowledgedOutboxIds,
    };

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(responsePayload));
    await request.response.close();
  }

  void _handlePull(HttpRequest request) {
    final sinceStr = request.uri.queryParameters['since'];
    DateTime since = DateTime.fromMillisecondsSinceEpoch(0);
    if (sinceStr != null) {
      final parsed = DateTime.tryParse(sinceStr);
      if (parsed != null) {
        since = parsed.toUtc();
      }
    }

    // Format since in UTC matching SQLite datetime('now') 'YYYY-MM-DD HH:MM:SS'
    final y = since.year.toString().padLeft(4, '0');
    final m = since.month.toString().padLeft(2, '0');
    final d = since.day.toString().padLeft(2, '0');
    final hh = since.hour.toString().padLeft(2, '0');
    final mm = since.minute.toString().padLeft(2, '0');
    final ss = since.second.toString().padLeft(2, '0');
    final sqliteSince = '$y-$m-$d $hh:$mm:$ss';

    // Pull updated products, customers, and suppliers created or updated after 'since'
    List<Map<String, dynamic>> products = [];
    List<Map<String, dynamic>> customers = [];
    List<Map<String, dynamic>> suppliers = [];

    try {
      products = _db.select('''
        SELECT * FROM products 
        WHERE (updated_at >= ? OR datetime(updated_at) >= datetime(?)) 
        ORDER BY updated_at ASC LIMIT 200
      ''', [sqliteSince, sqliteSince]).map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {}

    try {
      customers = _db.select('''
        SELECT * FROM customers 
        WHERE (updated_at >= ? OR datetime(updated_at) >= datetime(?)) 
        ORDER BY updated_at ASC LIMIT 100
      ''', [sqliteSince, sqliteSince]).map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {}

    try {
      suppliers = _db.select('''
        SELECT * FROM suppliers 
        WHERE (updated_at >= ? OR datetime(updated_at) >= datetime(?)) 
        ORDER BY updated_at ASC LIMIT 100
      ''', [sqliteSince, sqliteSince]).map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {}

    final responsePayload = {
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'products': products,
      'customers': customers,
      'suppliers': suppliers,
    };

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(responsePayload));
    request.response.close();
  }

  void _handleStatus(HttpRequest request) {
    final responsePayload = {
      'is_running': isRunning,
      'server_name': _serverName,
      'node_id': _nodeId,
      'port': _port,
      'connected_clients_count': _connectedClients.length,
      'sync_logs_count': _syncLogs.length,
      'server_time': DateTime.now().toIso8601String(),
    };
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(responsePayload));
    request.response.close();
  }

  void _addLog(String senderNodeId, String clientIp, int count, bool success, String details) {
    _syncLogs.insert(
      0,
      ServerSyncLogItem(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        clientNodeId: senderNodeId,
        clientIp: clientIp,
        itemsCount: count,
        timestamp: DateTime.now(),
        isSuccess: success,
        details: details,
      ),
    );
    if (_syncLogs.length > 100) {
      _syncLogs.removeLast();
    }
  }
}
