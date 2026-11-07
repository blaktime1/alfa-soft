import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/sync/outbox_manager.dart';
import 'package:alfa_soft/core/sync/conflict_resolution_engine.dart';
import 'package:alfa_soft/core/sync/lan_sync_protocol.dart';

void main() {
  late DatabaseService db;
  late OutboxManager outbox;
  late LanSyncService syncService;
  const conflictEngine = ConflictResolutionEngine();

  setUp(() {
    db = DatabaseService.inMemory();
    outbox = OutboxManager(db);
    syncService = LanSyncService(db: db, outboxManager: outbox, conflictEngine: conflictEngine);
  });

  tearDown(() {
    db.dispose();
  });

  group('Phase 6 — Offline & Multi-Device Sync Test Suite', () {
    test('1. Outbox Pattern: enqueues items with monotonic sequence numbers, batches and tracks status', () {
      final item1 = outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: 'prod_101',
        operation: SyncOperation.create,
        payload: {'sku': '1001', 'name_ar': 'ماء 500 مل', 'price': 150},
      );

      final item2 = outbox.enqueue(
        entityType: 'CUSTOMER',
        entityId: 'cust_201',
        operation: SyncOperation.create,
        payload: {'code': 'C01', 'name': 'مؤسسة الروابي'},
      );

      expect(item1.sequenceNumber, equals(1));
      expect(item2.sequenceNumber, equals(2));

      // Retrieve batch
      final batch = outbox.getPendingBatch();
      expect(batch.length, equals(2));
      expect(batch.first.entityId, equals('prod_101'));

      // Check stats
      var stats = outbox.getStats();
      expect(stats.pendingCount, equals(2));
      expect(stats.syncedCount, equals(0));

      // Mark first item as synced
      outbox.markSynced([item1.id]);

      stats = outbox.getStats();
      expect(stats.pendingCount, equals(1));
      expect(stats.syncedCount, equals(1));

      // Verify pending batch now only returns remaining item
      final remaining = outbox.getPendingBatch();
      expect(remaining.length, equals(1));
      expect(remaining.first.entityId, equals('cust_201'));
    });

    test('2. Conflict Resolution: strictly protects financial ledger immutability', () {
      // 1. Attempt to update a posted sales invoice -> Must be strictly REJECTED
      final resUpdate = conflictEngine.resolve(
        entityType: 'SALES_INVOICE',
        operation: 'UPDATE',
        localState: {'id': 'inv_101', 'grand_total': 11500},
        remoteState: {'id': 'inv_101', 'grand_total': 8000},
      );
      expect(resUpdate.outcome, equals(ResolutionOutcome.rejected));
      expect(resUpdate.reason.contains('غير قابلة للتعديل'), isTrue);

      // 2. Attempt to delete a journal entry -> Must be strictly REJECTED
      final resDelete = conflictEngine.resolve(
        entityType: 'JOURNAL_ENTRY',
        operation: 'DELETE',
        localState: {'id': 'je_501'},
        remoteState: {'id': 'je_501'},
      );
      expect(resDelete.outcome, equals(ResolutionOutcome.rejected));

      // 3. New sales invoice insert -> APPLIED
      final resCreate = conflictEngine.resolve(
        entityType: 'SALES_INVOICE',
        operation: 'CREATE',
        localState: null,
        remoteState: {'id': 'inv_new_01', 'grand_total': 5000},
      );
      expect(resCreate.outcome, equals(ResolutionOutcome.applied));
    });

    test('3. Conflict Resolution: applies Last-Write-Wins (LWW) on master catalog data', () {
      // Case A: Remote has higher version -> Remote wins (applied)
      final resHigherVer = conflictEngine.resolve(
        entityType: 'PRODUCT',
        operation: 'UPDATE',
        localState: {'id': 'p1', 'name': 'صنف قديم', 'version': 1},
        remoteState: {'id': 'p1', 'name': 'صنف محدث من الخادم', 'version': 2},
      );
      expect(resHigherVer.outcome, equals(ResolutionOutcome.applied));

      // Case B: Local has higher version -> Local wins
      final resLowerVer = conflictEngine.resolve(
        entityType: 'PRODUCT',
        operation: 'UPDATE',
        localState: {'id': 'p1', 'name': 'صنف محدث محلياً', 'version': 3},
        remoteState: {'id': 'p1', 'name': 'صنف قديم', 'version': 2},
      );
      expect(resLowerVer.outcome, equals(ResolutionOutcome.localWins));

      // Case C: Same version, remote timestamp is newer -> Remote applied
      final resNewerTime = conflictEngine.resolve(
        entityType: 'PRODUCT',
        operation: 'UPDATE',
        localState: {'id': 'p1', 'version': 1, 'updated_at': '2026-11-07T10:00:00Z'},
        remoteState: {'id': 'p1', 'version': 1, 'updated_at': '2026-11-07T12:00:00Z'},
      );
      expect(resNewerTime.outcome, equals(ResolutionOutcome.applied));
    });

    test('4. LAN Sync Protocol: packet creation, cryptographic verification, and batch ingestion', () {
      // Enqueue changes
      outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: 'p_sync_1',
        operation: SyncOperation.create,
        payload: {
          'id': 'p_sync_1',
          'company_id': 'comp_1',
          'base_unit_id': 'unit_pcs',
          'sku': 'SKU-SYNC-01',
          'name_ar': 'منتج المزامنة التجريبي',
          'sale_price': 2500,
          'cost_price': 1800,
          'version': 1,
        },
      );

      final packet = syncService.createOutboxPacket(localNodeId: 'NODE-POS-01');
      expect(packet.items.length, equals(1));
      expect(packet.checksum, isNotEmpty);

      // Verify tampered packet is rejected
      final tamperedPacket = SyncPacket(
        packetId: packet.packetId,
        senderNodeId: packet.senderNodeId,
        timestamp: packet.timestamp,
        items: packet.items,
        checksum: 'INVALID_CORRUPTED_CHECKSUM',
      );
      expect(() => syncService.ingestPacket(tamperedPacket), throwsFormatException);

      // Seed required master unit for foreign key validity in DB
      db.execute('''
        INSERT INTO companies (id, legal_name, trade_name) VALUES ('comp_1', 'C1', 'C1');
        INSERT INTO units (id, company_id, code, name) VALUES ('unit_pcs', 'comp_1', 'PCS', 'حبة');
      ''');

      // Ingest valid packet
      final summary = syncService.ingestPacket(packet);
      expect(summary.totalReceived, equals(1));
      expect(summary.appliedCount, equals(1));
      expect(summary.rejectedCount, equals(0));
      expect(summary.acknowledgedOutboxIds.length, equals(1));

      // Assert data applied to products table in database
      final prodResult = db.select('SELECT * FROM products WHERE id = "p_sync_1"');
      expect(prodResult.isNotEmpty, isTrue);
      expect(prodResult.first['name_ar'], equals('منتج المزامنة التجريبي'));
      expect(prodResult.first['sale_price'], equals(2500));
    });
  });
}
