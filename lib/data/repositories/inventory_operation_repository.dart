import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/inventory_operation.dart';

class InventoryOperationRepository {
  final DatabaseService _db;
  const InventoryOperationRepository(this._db);

  List<StockTransferEntity> getTransfers(String companyId) {
    final result = _db.select('''
      SELECT * FROM stock_transfers 
      WHERE company_id = ? 
      ORDER BY transfer_date DESC
    ''', [companyId]);
    return result.map((r) => StockTransferEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  StockTransferEntity transferStock({
    required String companyId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required String userId,
    required String transferNumber,
    String? notes,
    required List<Map<String, dynamic>> items, // [{productId, quantity, unitCostCents}]
  }) {
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('لا يمكن التحويل لنفس المستودع المصدر والمستهدف');
    }

    const uuid = Uuid();
    final transferId = 'tr_${uuid.v4()}';

    _db.transaction((tx) {
      // 1. Insert Transfer Header
      tx.execute('''
        INSERT INTO stock_transfers (
          id, company_id, transfer_number, from_warehouse_id,
          to_warehouse_id, status, transfer_date, notes, created_by_user_id
        ) VALUES (?, ?, ?, ?, ?, 'COMPLETED', datetime('now'), ?, ?)
      ''', [
        transferId,
        companyId,
        transferNumber.trim(),
        fromWarehouseId,
        toWarehouseId,
        notes?.trim(),
        userId,
      ]);

      // 2. Process Items
      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = item['quantity'] as int;
        final unitCost = item['unitCostCents'] as int;

        tx.execute('''
          INSERT INTO stock_transfer_items (id, transfer_id, product_id, quantity, unit_cost)
          VALUES (?, ?, ?, ?, ?)
        ''', ['tri_${uuid.v4()}', transferId, productId, qty, unitCost]);

        // Outbound Movement from Source Warehouse
        tx.execute('''
          INSERT INTO inventory_movements (
            id, company_id, warehouse_id, product_id, movement_type,
            quantity, unit_cost, total_cost, reference_document_type,
            reference_document_id, created_by_user_id
          ) VALUES (?, ?, ?, ?, 'TRANSFER_OUT', ?, ?, ?, 'STOCK_TRANSFER', ?, ?)
        ''', [
          'mov_${uuid.v4()}',
          companyId,
          fromWarehouseId,
          productId,
          -qty,
          unitCost,
          qty * unitCost,
          transferId,
          userId,
        ]);

        // Inbound Movement to Destination Warehouse
        tx.execute('''
          INSERT INTO inventory_movements (
            id, company_id, warehouse_id, product_id, movement_type,
            quantity, unit_cost, total_cost, reference_document_type,
            reference_document_id, created_by_user_id
          ) VALUES (?, ?, ?, ?, 'TRANSFER_IN', ?, ?, ?, 'STOCK_TRANSFER', ?, ?)
        ''', [
          'mov_${uuid.v4()}',
          companyId,
          toWarehouseId,
          productId,
          qty,
          unitCost,
          qty * unitCost,
          transferId,
          userId,
        ]);

        // Update Source Warehouse Balance
        tx.execute('''
          UPDATE inventory_balances 
          SET quantity = quantity - ?, updated_at = datetime('now')
          WHERE warehouse_id = ? AND product_id = ?
        ''', [qty, fromWarehouseId, productId]);

        // Update/Insert Destination Warehouse Balance
        final destBal = tx.select('''
          SELECT quantity FROM inventory_balances
          WHERE warehouse_id = ? AND product_id = ?
        ''', [toWarehouseId, productId]);

        if (destBal.isEmpty) {
          tx.execute('''
            INSERT INTO inventory_balances (warehouse_id, product_id, quantity, average_cost, updated_at)
            VALUES (?, ?, ?, ?, datetime('now'))
          ''', [toWarehouseId, productId, qty, unitCost]);
        } else {
          tx.execute('''
            UPDATE inventory_balances 
            SET quantity = quantity + ?, updated_at = datetime('now')
            WHERE warehouse_id = ? AND product_id = ?
          ''', [qty, toWarehouseId, productId]);
        }
      }

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, 'LOCAL_DESKTOP', 'STOCK_TRANSFER', 'TRANSFER', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        userId,
        transferId,
        'Transfer $transferNumber from $fromWarehouseId to $toWarehouseId',
      ]);
    });

    return StockTransferEntity(
      id: transferId,
      companyId: companyId,
      transferNumber: transferNumber,
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      status: 'COMPLETED',
      transferDate: DateTime.now(),
      notes: notes,
    );
  }

  StockAdjustmentEntity adjustStock({
    required String companyId,
    required String warehouseId,
    required String productId,
    required String userId,
    required String adjustmentType, // 'SURPLUS' (positive) or 'DEFICIT' (negative)
    required int quantity, // Absolute positive quantity
    required int unitCostCents,
    required String reason,
  }) {
    const uuid = Uuid();
    final adjustmentId = 'adj_${uuid.v4()}';
    final effectiveQty = adjustmentType == 'SURPLUS' ? quantity : -quantity;

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO stock_adjustments (
          id, company_id, warehouse_id, product_id, adjustment_type,
          quantity, unit_cost, reason, adjustment_date, created_by_user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
      ''', [
        adjustmentId,
        companyId,
        warehouseId,
        productId,
        adjustmentType,
        effectiveQty,
        unitCostCents,
        reason.trim(),
        userId,
      ]);

      // Record Inventory Movement
      tx.execute('''
        INSERT INTO inventory_movements (
          id, company_id, warehouse_id, product_id, movement_type,
          quantity, unit_cost, total_cost, reference_document_type,
          reference_document_id, created_by_user_id
        ) VALUES (?, ?, ?, ?, 'ADJUSTMENT', ?, ?, ?, 'ADJUSTMENT', ?, ?)
      ''', [
        'mov_${uuid.v4()}',
        companyId,
        warehouseId,
        productId,
        effectiveQty,
        unitCostCents,
        quantity * unitCostCents,
        adjustmentId,
        userId,
      ]);

      // Update Warehouse Balance
      final balResult = tx.select('''
        SELECT quantity FROM inventory_balances
        WHERE warehouse_id = ? AND product_id = ?
      ''', [warehouseId, productId]);

      if (balResult.isEmpty) {
        tx.execute('''
          INSERT INTO inventory_balances (warehouse_id, product_id, quantity, average_cost, updated_at)
          VALUES (?, ?, ?, ?, datetime('now'))
        ''', [warehouseId, productId, effectiveQty, unitCostCents]);
      } else {
        tx.execute('''
          UPDATE inventory_balances 
          SET quantity = quantity + ?, updated_at = datetime('now')
          WHERE warehouse_id = ? AND product_id = ?
        ''', [effectiveQty, warehouseId, productId]);
      }

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, 'LOCAL_DESKTOP', 'ADJUST_STOCK', 'ADJUSTMENT', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        userId,
        adjustmentId,
        'Type: $adjustmentType, Qty: $effectiveQty, Reason: $reason',
      ]);
    });

    return StockAdjustmentEntity(
      id: adjustmentId,
      companyId: companyId,
      warehouseId: warehouseId,
      productId: productId,
      adjustmentType: adjustmentType,
      quantity: effectiveQty,
      unitCostCents: unitCostCents,
      reason: reason,
      adjustmentDate: DateTime.now(),
    );
  }

  List<Map<String, dynamic>> getStockMovements({
    required String warehouseId,
    required String productId,
  }) {
    final result = _db.select('''
      SELECT * FROM inventory_movements 
      WHERE warehouse_id = ? AND product_id = ? 
      ORDER BY created_at DESC
    ''', [warehouseId, productId]);
    return result.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
