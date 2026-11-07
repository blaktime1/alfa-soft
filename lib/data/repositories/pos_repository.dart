import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/pos_shift.dart';

class PosRepository {
  final DatabaseService _db;
  const PosRepository(this._db);

  PosShiftEntity? getActiveShift(String branchId, String userId) {
    final result = _db.select('''
      SELECT * FROM pos_shifts 
      WHERE branch_id = ? AND user_id = ? AND status = 'OPEN' 
      ORDER BY opened_at DESC 
      LIMIT 1
    ''', [branchId, userId]);

    if (result.isEmpty) return null;
    return PosShiftEntity.fromMap(Map<String, dynamic>.from(result.first));
  }

  PosShiftEntity openShift({
    required String branchId,
    required String userId,
    required int startingCashCents,
  }) {
    // Verify no shift is already open for this user on this branch
    final active = getActiveShift(branchId, userId);
    if (active != null) {
      return active;
    }

    const uuid = Uuid();
    final shiftId = 'shift_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO pos_shifts (
          id, branch_id, user_id, opened_at, starting_cash,
          expected_cash, status
        ) VALUES (?, ?, ?, datetime('now'), ?, ?, 'OPEN')
      ''', [shiftId, branchId, userId, startingCashCents, startingCashCents]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, 'SYSTEM', ?, ?, 'LOCAL_DESKTOP', 'OPEN_POS_SHIFT', 'SHIFT', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        branchId,
        userId,
        shiftId,
        'Starting Cash: ${startingCashCents / 100.0} SAR',
      ]);
    });

    return PosShiftEntity(
      id: shiftId,
      branchId: branchId,
      userId: userId,
      openedAt: DateTime.now(),
      startingCashCents: startingCashCents,
      expectedCashCents: startingCashCents,
    );
  }

  PosShiftEntity closeShift({
    required String shiftId,
    required int actualCashCents,
    String? notes,
  }) {
    final shiftResult = _db.select('SELECT * FROM pos_shifts WHERE id = ?', [shiftId]);
    if (shiftResult.isEmpty) {
      throw ArgumentError('الوردية غير موجودة');
    }

    final shiftRow = shiftResult.first;
    final startingCash = shiftRow['starting_cash'] as int;
    final openedAt = shiftRow['opened_at'] as String;
    final branchId = shiftRow['branch_id'] as String;
    final userId = shiftRow['user_id'] as String;

    // Calculate cash payments collected during this shift
    final paymentsResult = _db.select('''
      SELECT COALESCE(SUM(amount), 0) as cash_total
      FROM payments
      WHERE branch_id = ? 
        AND payment_method = 'CASH'
        AND created_at >= ?
    ''', [branchId, openedAt]);

    final cashSalesTotal = paymentsResult.first['cash_total'] as int;
    final expectedCashCents = startingCash + cashSalesTotal;
    final differenceCents = actualCashCents - expectedCashCents;

    _db.transaction((tx) {
      tx.execute('''
        UPDATE pos_shifts
        SET closed_at = datetime('now'),
            expected_cash = ?,
            actual_cash = ?,
            difference = ?,
            status = 'CLOSED',
            notes = ?
        WHERE id = ?
      ''', [
        expectedCashCents,
        actualCashCents,
        differenceCents,
        notes?.trim(),
        shiftId,
      ]);

      const uuid = Uuid();
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, 'SYSTEM', ?, ?, 'LOCAL_DESKTOP', 'CLOSE_POS_SHIFT', 'SHIFT', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        branchId,
        userId,
        shiftId,
        'Expected: ${expectedCashCents / 100.0}, Actual: ${actualCashCents / 100.0}, Diff: ${differenceCents / 100.0} SAR',
      ]);
    });

    return PosShiftEntity(
      id: shiftId,
      branchId: branchId,
      userId: userId,
      openedAt: DateTime.parse(openedAt),
      closedAt: DateTime.now(),
      startingCashCents: startingCash,
      expectedCashCents: expectedCashCents,
      actualCashCents: actualCashCents,
      differenceCents: differenceCents,
      status: 'CLOSED',
      notes: notes,
    );
  }

  SuspendedCartEntity suspendSale({
    required String branchId,
    required String userId,
    required String holdReference,
    required String cartPayload,
  }) {
    const uuid = Uuid();
    final holdId = 'hold_${uuid.v4()}';

    _db.execute('''
      INSERT INTO pos_suspended_sales (id, branch_id, user_id, hold_reference, cart_payload, created_at)
      VALUES (?, ?, ?, ?, ?, datetime('now'))
    ''', [holdId, branchId, userId, holdReference.trim(), cartPayload]);

    return SuspendedCartEntity(
      id: holdId,
      branchId: branchId,
      userId: userId,
      holdReference: holdReference,
      cartPayload: cartPayload,
      createdAt: DateTime.now(),
    );
  }

  List<SuspendedCartEntity> getSuspendedSales(String branchId) {
    final result = _db.select('''
      SELECT * FROM pos_suspended_sales 
      WHERE branch_id = ? 
      ORDER BY created_at DESC
    ''', [branchId]);
    return result.map((r) => SuspendedCartEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  String resumeSale(String holdId) {
    final result = _db.select('SELECT cart_payload FROM pos_suspended_sales WHERE id = ?', [holdId]);
    if (result.isEmpty) {
      throw ArgumentError('الفاتورة المعلقة غير موجودة');
    }
    final payload = result.first['cart_payload'] as String;
    _db.execute('DELETE FROM pos_suspended_sales WHERE id = ?', [holdId]);
    return payload;
  }
}
