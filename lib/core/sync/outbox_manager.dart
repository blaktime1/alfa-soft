import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../data/local/database_service.dart';

enum SyncOperation {
  create('CREATE'),
  update('UPDATE'),
  delete('DELETE');

  final String code;
  const SyncOperation(this.code);

  static SyncOperation fromString(String val) {
    return SyncOperation.values.firstWhere(
      (e) => e.code == val.toUpperCase(),
      orElse: () => SyncOperation.create,
    );
  }
}

enum SyncStatus {
  pending('PENDING'),
  synced('SYNCED'),
  conflict('CONFLICT'),
  failed('FAILED');

  final String code;
  const SyncStatus(this.code);

  static SyncStatus fromString(String val) {
    return SyncStatus.values.firstWhere(
      (e) => e.code == val.toUpperCase(),
      orElse: () => SyncStatus.pending,
    );
  }
}

class OutboxItem {
  final String id;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final int sequenceNumber;
  final DateTime createdAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;

  const OutboxItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.sequenceNumber,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastError,
  });

  factory OutboxItem.fromMap(Map<String, dynamic> map) {
    return OutboxItem(
      id: map['id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operation: SyncOperation.fromString(map['operation'] as String),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      sequenceNumber: map['sequence_number'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: SyncStatus.fromString(map['sync_status'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}

class SyncStats {
  final int pendingCount;
  final int syncedCount;
  final int conflictCount;
  final int failedCount;

  const SyncStats({
    required this.pendingCount,
    required this.syncedCount,
    required this.conflictCount,
    required this.failedCount,
  });
}

/// Outbox Manager: captures and dispatches local offline changes
class OutboxManager {
  final DatabaseService _db;
  const OutboxManager(this._db);

  /// Enqueues a local modification to the sync outbox
  OutboxItem enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) {
    const uuid = Uuid();
    final outboxId = 'out_${uuid.v4()}';
    final payloadJson = jsonEncode(payload);

    // Get current maximum sequence number
    final maxSeqResult = _db.select('SELECT COALESCE(MAX(sequence_number), 0) as max_seq FROM sync_outbox');
    final nextSeq = (maxSeqResult.first['max_seq'] as int) + 1;

    _db.execute('''
      INSERT INTO sync_outbox (
        id, entity_type, entity_id, operation, payload, sequence_number,
        created_at, sync_status, retry_count
      ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), 'PENDING', 0)
    ''', [
      outboxId,
      entityType.toUpperCase(),
      entityId,
      operation.code,
      payloadJson,
      nextSeq,
    ]);

    return OutboxItem(
      id: outboxId,
      entityType: entityType.toUpperCase(),
      entityId: entityId,
      operation: operation,
      payload: payload,
      sequenceNumber: nextSeq,
      createdAt: DateTime.now(),
    );
  }

  /// Retrieves pending outbox records up to batch limit
  List<OutboxItem> getPendingBatch({int limit = 50}) {
    final result = _db.select('''
      SELECT * FROM sync_outbox 
      WHERE sync_status = 'PENDING' 
      ORDER BY sequence_number ASC 
      LIMIT ?
    ''', [limit]);

    return result.map((r) => OutboxItem.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  /// Marks items as successfully acknowledged and synced
  void markSynced(List<String> outboxIds) {
    if (outboxIds.isEmpty) return;

    _db.transaction((tx) {
      for (final id in outboxIds) {
        tx.execute('''
          UPDATE sync_outbox 
          SET sync_status = 'SYNCED', last_error = NULL 
          WHERE id = ?
        ''', [id]);
      }
    });
  }

  /// Marks an outbox item as failed with error details and increments retry count
  void markFailed(String outboxId, String error) {
    _db.execute('''
      UPDATE sync_outbox 
      SET sync_status = 'FAILED', retry_count = retry_count + 1, last_error = ? 
      WHERE id = ?
    ''', [error, outboxId]);
  }

  /// Marks an outbox item as conflict
  void markConflict(String outboxId, String reason) {
    _db.execute('''
      UPDATE sync_outbox 
      SET sync_status = 'CONFLICT', last_error = ? 
      WHERE id = ?
    ''', [reason, outboxId]);
  }

  /// Retrieves queue metrics and summary counters
  SyncStats getStats() {
    final result = _db.select('''
      SELECT 
        SUM(CASE WHEN sync_status = 'PENDING' THEN 1 ELSE 0 END) as pending_cnt,
        SUM(CASE WHEN sync_status = 'SYNCED' THEN 1 ELSE 0 END) as synced_cnt,
        SUM(CASE WHEN sync_status = 'CONFLICT' THEN 1 ELSE 0 END) as conflict_cnt,
        SUM(CASE WHEN sync_status = 'FAILED' THEN 1 ELSE 0 END) as failed_cnt
      FROM sync_outbox
    ''');

    final row = result.first;
    return SyncStats(
      pendingCount: row['pending_cnt'] as int? ?? 0,
      syncedCount: row['synced_cnt'] as int? ?? 0,
      conflictCount: row['conflict_cnt'] as int? ?? 0,
      failedCount: row['failed_cnt'] as int? ?? 0,
    );
  }
}
