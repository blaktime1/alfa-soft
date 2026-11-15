import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/purchase.dart';
import 'accounting_repository.dart';

class PurchaseRepository {
  final DatabaseService _db;
  const PurchaseRepository(this._db);

  List<PurchaseOrderEntity> getPurchaseOrders(String companyId) {
    final result = _db.select('''
      SELECT * FROM purchase_orders 
      WHERE company_id = ? 
      ORDER BY order_date DESC
    ''', [companyId]);

    final orders = <PurchaseOrderEntity>[];
    for (final row in result) {
      final poId = row['id'] as String;
      final itemsResult = _db.select('''
        SELECT * FROM purchase_order_items WHERE purchase_order_id = ?
      ''', [poId]);
      final items = itemsResult.map((r) => PurchaseOrderItemEntity.fromMap(Map<String, dynamic>.from(r))).toList();
      orders.add(PurchaseOrderEntity.fromMap(Map<String, dynamic>.from(row), items));
    }
    return orders;
  }

  PurchaseOrderEntity createPurchaseOrder({
    required String companyId,
    required String branchId,
    required String supplierId,
    required String userId,
    required String orderNumber,
    DateTime? expectedDate,
    String? notes,
    required List<Map<String, dynamic>> items, // [{productId, unitId, quantity, unitCostCents}]
  }) {
    const uuid = Uuid();
    final poId = 'po_${uuid.v4()}';

    int subtotalCents = 0;
    for (final item in items) {
      final qty = item['quantity'] as int;
      final cost = item['unitCostCents'] as int;
      subtotalCents += qty * cost;
    }
    final taxRows = _db.select("SELECT value FROM system_settings WHERE key = 'tax_is_enabled' LIMIT 1");
    final isTaxOn = taxRows.isEmpty || taxRows.first['value'] != '0';
    final rateRows = _db.select("SELECT value FROM system_settings WHERE key = 'tax_rate_percent' LIMIT 1");
    final rate = rateRows.isNotEmpty ? (double.tryParse(rateRows.first['value']?.toString() ?? '15') ?? 15.0) : 15.0;
    final taxTotalCents = (isTaxOn && rate > 0) ? ((subtotalCents * (rate / 100.0)).round()) : 0;
    final grandTotalCents = subtotalCents + taxTotalCents;

    _db.transaction((tx) {
      // 1. Insert PO Header (Note: Stock is NOT incremented upon PO creation!)
      tx.execute('''
        INSERT INTO purchase_orders (
          id, company_id, branch_id, supplier_id, order_number,
          order_date, expected_date, subtotal, tax_total, grand_total,
          status, notes, created_by_user_id
        ) VALUES (?, ?, ?, ?, ?, datetime('now'), ?, ?, ?, ?, 'PENDING', ?, ?)
      ''', [
        poId,
        companyId,
        branchId,
        supplierId,
        orderNumber.trim(),
        expectedDate?.toIso8601String(),
        subtotalCents,
        taxTotalCents,
        grandTotalCents,
        notes?.trim(),
        userId,
      ]);

      // 2. Insert PO Lines
      for (final item in items) {
        final qty = item['quantity'] as int;
        final cost = item['unitCostCents'] as int;
        tx.execute('''
          INSERT INTO purchase_order_items (
            id, purchase_order_id, product_id, unit_id, quantity,
            received_quantity, unit_cost, line_total
          ) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ''', [
          'poi_${uuid.v4()}',
          poId,
          item['productId'],
          item['unitId'],
          qty,
          cost,
          qty * cost,
        ]);
      }

      // 3. Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'LOCAL_DESKTOP', 'CREATE_PURCHASE_ORDER', 'PURCHASE_ORDER', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        poId,
        'PO: $orderNumber, Total: ${grandTotalCents / 100.0} SAR',
      ]);
    });

    return PurchaseOrderEntity(
      id: poId,
      companyId: companyId,
      branchId: branchId,
      supplierId: supplierId,
      orderNumber: orderNumber,
      orderDate: DateTime.now(),
      expectedDate: expectedDate,
      subtotalCents: subtotalCents,
      taxTotalCents: taxTotalCents,
      grandTotalCents: grandTotalCents,
      status: 'PENDING',
      notes: notes,
    );
  }

  /// Physical receipt of goods into warehouse (GRN).
  /// Enforces stock increment, Moving Average Cost recalculation, and PO status update.
  GoodsReceiptEntity receiveGoods({
    required String companyId,
    required String branchId,
    required String warehouseId,
    required String supplierId,
    required String userId,
    String? purchaseOrderId,
    required String receiptNumber,
    required List<Map<String, dynamic>> receivedItems, // [{productId, quantity, unitCostCents}]
  }) {
    const uuid = Uuid();
    final grnId = 'grn_${uuid.v4()}';
    int totalCostCents = 0;

    _db.transaction((tx) {
      // 1. Insert GRN Header
      for (final item in receivedItems) {
        final qty = item['quantity'] as int;
        final cost = item['unitCostCents'] as int;
        totalCostCents += qty * cost;
      }

      tx.execute('''
        INSERT INTO goods_receipt_notes (
          id, company_id, branch_id, warehouse_id, purchase_order_id,
          supplier_id, receipt_number, receipt_date, total_cost, status,
          created_by_user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?, 'POSTED', ?)
      ''', [
        grnId,
        companyId,
        branchId,
        warehouseId,
        purchaseOrderId,
        supplierId,
        receiptNumber.trim(),
        totalCostCents,
        userId,
      ]);

      // 2. Process each item: Ledger Movement + Moving Average Cost Update
      for (final item in receivedItems) {
        final productId = item['productId'] as String;
        final qty = item['quantity'] as int;
        final unitCost = item['unitCostCents'] as int;

        tx.execute('''
          INSERT INTO goods_receipt_items (id, receipt_id, product_id, quantity, unit_cost, total_cost)
          VALUES (?, ?, ?, ?, ?, ?)
        ''', ['gri_${uuid.v4()}', grnId, productId, qty, unitCost, qty * unitCost]);

        // Insert Immutable Inventory Movement
        tx.execute('''
          INSERT INTO inventory_movements (
            id, company_id, warehouse_id, product_id, movement_type,
            quantity, unit_cost, total_cost, reference_document_type,
            reference_document_id, created_by_user_id
          ) VALUES (?, ?, ?, ?, 'PURCHASE_RECEIPT', ?, ?, ?, 'GRN', ?, ?)
        ''', [
          'mov_${uuid.v4()}',
          companyId,
          warehouseId,
          productId,
          qty, // Positive for incoming receipt
          unitCost,
          qty * unitCost,
          grnId,
          userId,
        ]);

        // Recalculate Moving Average Cost on Inventory Balance
        final balResult = tx.select('''
          SELECT quantity, average_cost FROM inventory_balances
          WHERE warehouse_id = ? AND product_id = ?
        ''', [warehouseId, productId]);

        if (balResult.isEmpty) {
          // Initial balance record
          tx.execute('''
            INSERT INTO inventory_balances (warehouse_id, product_id, quantity, average_cost, updated_at)
            VALUES (?, ?, ?, ?, datetime('now'))
          ''', [warehouseId, productId, qty, unitCost]);
        } else {
          final currentQty = balResult.first['quantity'] as int;
          final currentAvgCost = balResult.first['average_cost'] as int;
          final newQty = currentQty + qty;

          // MAC formula: ((Q_curr * C_curr) + (Q_in * C_in)) / (Q_curr + Q_in)
          final newAvgCost = newQty > 0
              ? (((currentQty * currentAvgCost) + (qty * unitCost)) / newQty).round()
              : unitCost;

          tx.execute('''
            UPDATE inventory_balances 
            SET quantity = ?, average_cost = ?, updated_at = datetime('now')
            WHERE warehouse_id = ? AND product_id = ?
          ''', [newQty, newAvgCost, warehouseId, productId]);
        }

        // Also update product catalog's master cost price
        tx.execute('''
          UPDATE products SET cost_price = ? WHERE id = ?
        ''', [unitCost, productId]);

        // If linked to PO, update received_quantity
        if (purchaseOrderId != null) {
          tx.execute('''
            UPDATE purchase_order_items 
            SET received_quantity = received_quantity + ?
            WHERE purchase_order_id = ? AND product_id = ?
          ''', [qty, purchaseOrderId, productId]);
        }
      }

      // If linked to PO, check if fully received
      if (purchaseOrderId != null) {
        final pendingItems = tx.select('''
          SELECT COUNT(*) as pending 
          FROM purchase_order_items 
          WHERE purchase_order_id = ? AND received_quantity < quantity
        ''', [purchaseOrderId]);

        final isFullyReceived = (pendingItems.first['pending'] as int) == 0;
        tx.execute('''
          UPDATE purchase_orders 
          SET status = ? 
          WHERE id = ?
        ''', [isFullyReceived ? 'RECEIVED' : 'PARTIALLY_RECEIVED', purchaseOrderId]);
      }

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'LOCAL_DESKTOP', 'RECEIVE_GOODS', 'GRN', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        grnId,
        'GRN: $receiptNumber, Cost: ${totalCostCents / 100.0} SAR',
      ]);
    });

    // Post double-entry journal entry for GRN
    try {
      AccountingRepository(_db).postPurchaseGrnJournal(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        grnId: grnId,
        grnNumber: receiptNumber,
        grnDate: DateTime.now(),
        totalCostCents: totalCostCents,
      );
    } catch (_) {}

    return GoodsReceiptEntity(
      id: grnId,
      companyId: companyId,
      branchId: branchId,
      warehouseId: warehouseId,
      purchaseOrderId: purchaseOrderId,
      supplierId: supplierId,
      receiptNumber: receiptNumber,
      receiptDate: DateTime.now(),
      totalCostCents: totalCostCents,
      status: 'POSTED',
    );
  }

  /// Updates an existing purchase order / invoice
  void updatePurchaseOrder({
    required String poId,
    required String supplierId,
    String? notes,
    required List<Map<String, dynamic>> items,
    required String userId,
  }) {
    int subtotalCents = 0;
    for (final item in items) {
      final qty = item['quantity'] as int;
      final cost = item['unitCostCents'] as int;
      subtotalCents += qty * cost;
    }
    final taxRows = _db.select("SELECT value FROM system_settings WHERE key = 'tax_is_enabled' LIMIT 1");
    final isTaxOn = taxRows.isEmpty || taxRows.first['value'] != '0';
    final rateRows = _db.select("SELECT value FROM system_settings WHERE key = 'tax_rate_percent' LIMIT 1");
    final rate = rateRows.isNotEmpty ? (double.tryParse(rateRows.first['value']?.toString() ?? '15') ?? 15.0) : 15.0;
    final taxTotalCents = (isTaxOn && rate > 0) ? ((subtotalCents * (rate / 100.0)).round()) : 0;
    final grandTotalCents = subtotalCents + taxTotalCents;

    _db.transaction((tx) {
      final oldPo = tx.select('SELECT company_id, branch_id, order_number FROM purchase_orders WHERE id = ?', [poId]).first;
      final companyId = oldPo['company_id'] as String;
      final branchId = oldPo['branch_id'] as String;
      final orderNumber = oldPo['order_number'] as String;

      tx.execute('''
        UPDATE purchase_orders
        SET supplier_id = ?, subtotal = ?, tax_total = ?, grand_total = ?, notes = ?
        WHERE id = ?
      ''', [supplierId, subtotalCents, taxTotalCents, grandTotalCents, notes?.trim(), poId]);

      // Delete old items and insert updated lines
      tx.execute('DELETE FROM purchase_order_items WHERE purchase_order_id = ?', [poId]);

      const uuid = Uuid();
      for (final item in items) {
        final qty = item['quantity'] as int;
        final cost = item['unitCostCents'] as int;
        tx.execute('''
          INSERT INTO purchase_order_items (
            id, purchase_order_id, product_id, unit_id, quantity,
            received_quantity, unit_cost, line_total
          ) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ''', [
          'poi_${uuid.v4()}',
          poId,
          item['productId'],
          item['unitId'],
          qty,
          cost,
          qty * cost,
        ]);
      }

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'LOCAL_DESKTOP', 'EDIT_PURCHASE_ORDER', 'PURCHASE_ORDER', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        poId,
        'تعديل أمر شراء: $orderNumber، الإجمالي: ${grandTotalCents / 100.0}، عدد الأصناف: ${items.length}',
      ]);
    });
  }

  /// Retrieves list of goods receipt notes with supplier and warehouse names
  List<Map<String, dynamic>> getGoodsReceiptNotes(String companyId) {
    return _db.select('''
      SELECT grn.*, s.name as supplier_name, s.phone as supplier_phone, w.name as warehouse_name, u.full_name as receiver_name
      FROM goods_receipt_notes grn
      LEFT JOIN suppliers s ON grn.supplier_id = s.id
      LEFT JOIN warehouses w ON grn.warehouse_id = w.id
      LEFT JOIN users u ON grn.created_by_user_id = u.id
      WHERE grn.company_id = ?
      ORDER BY grn.receipt_date DESC, grn.created_at DESC
    ''', [companyId]).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Retrieves items of a specific goods receipt note
  List<Map<String, dynamic>> getGoodsReceiptItems(String receiptId) {
    return _db.select('''
      SELECT gri.*, p.name_ar, p.sku
      FROM goods_receipt_items gri
      LEFT JOIN products p ON gri.product_id = p.id
      WHERE gri.receipt_id = ?
    ''', [receiptId]).map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
