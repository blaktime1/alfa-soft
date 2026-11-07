class PurchaseOrderItemEntity {
  final String id;
  final String productId;
  final String unitId;
  final int quantity;
  final int receivedQuantity;
  final int unitCostCents;
  final int lineTotalCents;

  const PurchaseOrderItemEntity({
    required this.id,
    required this.productId,
    required this.unitId,
    required this.quantity,
    this.receivedQuantity = 0,
    required this.unitCostCents,
    required this.lineTotalCents,
  });

  double get unitCost => unitCostCents / 100.0;
  double get lineTotal => lineTotalCents / 100.0;

  factory PurchaseOrderItemEntity.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItemEntity(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      unitId: map['unit_id'] as String,
      quantity: map['quantity'] as int,
      receivedQuantity: map['received_quantity'] as int? ?? 0,
      unitCostCents: map['unit_cost'] as int,
      lineTotalCents: map['line_total'] as int,
    );
  }
}

class PurchaseOrderEntity {
  final String id;
  final String companyId;
  final String branchId;
  final String supplierId;
  final String orderNumber;
  final DateTime orderDate;
  final DateTime? expectedDate;
  final int subtotalCents;
  final int taxTotalCents;
  final int grandTotalCents;
  final String status;
  final String? notes;
  final List<PurchaseOrderItemEntity> items;

  const PurchaseOrderEntity({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.supplierId,
    required this.orderNumber,
    required this.orderDate,
    this.expectedDate,
    required this.subtotalCents,
    required this.taxTotalCents,
    required this.grandTotalCents,
    required this.status,
    this.notes,
    this.items = const [],
  });

  double get subtotal => subtotalCents / 100.0;
  double get taxTotal => taxTotalCents / 100.0;
  double get grandTotal => grandTotalCents / 100.0;

  factory PurchaseOrderEntity.fromMap(
    Map<String, dynamic> map, [
    List<PurchaseOrderItemEntity> items = const [],
  ]) {
    return PurchaseOrderEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      branchId: map['branch_id'] as String,
      supplierId: map['supplier_id'] as String,
      orderNumber: map['order_number'] as String,
      orderDate: DateTime.parse(map['order_date'] as String),
      expectedDate: map['expected_date'] != null
          ? DateTime.parse(map['expected_date'] as String)
          : null,
      subtotalCents: map['subtotal'] as int,
      taxTotalCents: map['tax_total'] as int,
      grandTotalCents: map['grand_total'] as int,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      items: items,
    );
  }
}

class GoodsReceiptEntity {
  final String id;
  final String companyId;
  final String branchId;
  final String warehouseId;
  final String? purchaseOrderId;
  final String supplierId;
  final String receiptNumber;
  final DateTime receiptDate;
  final int totalCostCents;
  final String status;

  const GoodsReceiptEntity({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.warehouseId,
    this.purchaseOrderId,
    required this.supplierId,
    required this.receiptNumber,
    required this.receiptDate,
    required this.totalCostCents,
    required this.status,
  });

  double get totalCost => totalCostCents / 100.0;

  factory GoodsReceiptEntity.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      branchId: map['branch_id'] as String,
      warehouseId: map['warehouse_id'] as String,
      purchaseOrderId: map['purchase_order_id'] as String?,
      supplierId: map['supplier_id'] as String,
      receiptNumber: map['receipt_number'] as String,
      receiptDate: DateTime.parse(map['receipt_date'] as String),
      totalCostCents: map['total_cost'] as int,
      status: map['status'] as String,
    );
  }
}
