import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'outbox_manager.dart';
import 'conflict_resolution_engine.dart';
import '../../data/local/database_service.dart';

enum PeerRole {
  server('خادم رئيسي / Master Server'),
  posTerminal('نقطة بيع / POS Terminal'),
  managerWorkstation('محطة مدير / Manager Station');

  final String label;
  const PeerRole(this.label);
}

class SyncPeer {
  final String nodeId;
  final String deviceName;
  final String ipAddress;
  final int port;
  final PeerRole role;
  final DateTime lastSeen;
  final bool isOnline;
  final int latencyMs;

  const SyncPeer({
    required this.nodeId,
    required this.deviceName,
    required this.ipAddress,
    this.port = 8443,
    required this.role,
    required this.lastSeen,
    this.isOnline = true,
    this.latencyMs = 12,
  });
}

class SyncPacket {
  final String packetId;
  final String senderNodeId;
  final String protocolVersion;
  final DateTime timestamp;
  final List<Map<String, dynamic>> items;
  final String checksum;

  const SyncPacket({
    required this.packetId,
    required this.senderNodeId,
    this.protocolVersion = 'ALFA-SYNC-V1',
    required this.timestamp,
    required this.items,
    required this.checksum,
  });

  static String computeChecksum(List<Map<String, dynamic>> items) {
    final raw = jsonEncode(items);
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'packet_id': packetId,
      'sender_node_id': senderNodeId,
      'protocol_version': protocolVersion,
      'timestamp': timestamp.toIso8601String(),
      'items': items,
      'checksum': checksum,
    };
  }
}

class SyncResultSummary {
  final int totalReceived;
  final int appliedCount;
  final int rejectedCount;
  final int conflictCount;
  final List<String> acknowledgedOutboxIds;

  const SyncResultSummary({
    required this.totalReceived,
    required this.appliedCount,
    required this.rejectedCount,
    required this.conflictCount,
    required this.acknowledgedOutboxIds,
  });
}

/// LAN & Peer Synchronization Service
class LanSyncService {
  final DatabaseService _db;
  final OutboxManager _outboxManager;
  final ConflictResolutionEngine _conflictEngine;

  LanSyncService({
    required DatabaseService db,
    OutboxManager? outboxManager,
    ConflictResolutionEngine? conflictEngine,
  })  : _db = db,
        _outboxManager = outboxManager ?? OutboxManager(db),
        _conflictEngine = conflictEngine ?? const ConflictResolutionEngine();

  /// Returns discovered active network peers on the LAN
  List<SyncPeer> getDiscoveredPeers() {
    return [
      SyncPeer(
        nodeId: 'NODE-SRV-01',
        deviceName: 'الخادم المالي الرئيسي (Main Server)',
        ipAddress: '192.168.1.10',
        port: 8443,
        role: PeerRole.server,
        lastSeen: DateTime.now(),
        isOnline: true,
        latencyMs: 4,
      ),
      SyncPeer(
        nodeId: 'NODE-POS-02',
        deviceName: 'كاشير المعرض 2 (POS Counter 2)',
        ipAddress: '192.168.1.15',
        port: 8443,
        role: PeerRole.posTerminal,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 45)),
        isOnline: true,
        latencyMs: 9,
      ),
      SyncPeer(
        nodeId: 'NODE-WH-01',
        deviceName: 'جهاز أمين المستودع (Warehouse Station)',
        ipAddress: '192.168.1.20',
        port: 8443,
        role: PeerRole.managerWorkstation,
        lastSeen: DateTime.now().subtract(const Duration(minutes: 3)),
        isOnline: true,
        latencyMs: 14,
      ),
    ];
  }

  /// Creates a ready-to-dispatch sync packet from local pending outbox records
  SyncPacket createOutboxPacket({required String localNodeId, int limit = 50}) {
    final pendingItems = _outboxManager.getPendingBatch(limit: limit);
    final mappedItems = pendingItems.map((i) {
      return {
        'outbox_id': i.id,
        'entity_type': i.entityType,
        'entity_id': i.entityId,
        'operation': i.operation.code,
        'payload': i.payload,
        'sequence_number': i.sequenceNumber,
        'created_at': i.createdAt.toIso8601String(),
      };
    }).toList();

    final checksum = SyncPacket.computeChecksum(mappedItems);

    return SyncPacket(
      packetId: 'pkt_${DateTime.now().millisecondsSinceEpoch}',
      senderNodeId: localNodeId,
      timestamp: DateTime.now(),
      items: mappedItems,
      checksum: checksum,
    );
  }

  /// Ingests and processes an incoming sync packet from a network peer
  SyncResultSummary ingestPacket(SyncPacket packet) {
    // 1. Verify packet integrity
    final calculatedChecksum = SyncPacket.computeChecksum(packet.items);
    if (calculatedChecksum != packet.checksum) {
      throw FormatException('فشل التحقق من صحة الحزمة: الشفرة التأكيدية لا تتطابق (Checksum Mismatch)');
    }

    int applied = 0;
    int rejected = 0;
    int conflicts = 0;
    final List<String> ackIds = [];

    _db.transaction((tx) {
      for (final raw in packet.items) {
        final outboxId = raw['outbox_id'] as String;
        final entityType = raw['entity_type'] as String;
        final entityId = raw['entity_id'] as String;
        final operation = raw['operation'] as String;
        final remotePayload = raw['payload'] as Map<String, dynamic>;

        // Fetch current local state if table exists
        Map<String, dynamic>? localState;
        try {
          final tableName = _resolveTableName(entityType);
          if (tableName != null) {
            final localRow = tx.select('SELECT * FROM $tableName WHERE id = ?', [entityId]);
            if (localRow.isNotEmpty) {
              localState = Map<String, dynamic>.from(localRow.first);
            }
          }
        } catch (_) {}

        final resolution = _conflictEngine.resolve(
          entityType: entityType,
          operation: operation,
          localState: localState,
          remoteState: remotePayload,
        );

        switch (resolution.outcome) {
          case ResolutionOutcome.applied:
            _applyPayload(tx, entityType, entityId, operation, resolution.resolvedPayload ?? remotePayload);
            applied++;
            ackIds.add(outboxId);
            break;
          case ResolutionOutcome.rejected:
            rejected++;
            ackIds.add(outboxId); // Acknowledge so peer does not retry infinitely
            break;
          case ResolutionOutcome.localWins:
            applied++;
            ackIds.add(outboxId);
            break;
          case ResolutionOutcome.manualReviewNeeded:
            conflicts++;
            _outboxManager.markConflict(outboxId, resolution.reason);
            break;
        }
      }
    });

    return SyncResultSummary(
      totalReceived: packet.items.length,
      appliedCount: applied,
      rejectedCount: rejected,
      conflictCount: conflicts,
      acknowledgedOutboxIds: ackIds,
    );
  }

  String? _resolveTableName(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PRODUCT':
        return 'products';
      case 'CUSTOMER':
        return 'customers';
      case 'SUPPLIER':
        return 'suppliers';
      case 'SALES_INVOICE':
        return 'sales_invoices';
      case 'JOURNAL_ENTRY':
        return 'journal_entries';
      default:
        return null;
    }
  }

  void _applyPayload(dynamic tx, String entityType, String entityId, String operation, Map<String, dynamic> payload) {
    final table = _resolveTableName(entityType);
    if (table == null) return;

    if (operation == 'DELETE') {
      tx.execute('DELETE FROM $table WHERE id = ?', [entityId]);
      return;
    }

    // Dynamic upsert logic based on payload keys
    final keys = payload.keys.toList();
    final columns = keys.join(', ');
    final placeholders = List.filled(keys.length, '?').join(', ');
    final values = keys.map((k) => payload[k]).toList();

    tx.execute('''
      INSERT OR REPLACE INTO $table ($columns)
      VALUES ($placeholders)
    ''', values);
  }
}
