class StockTransferEntity {
  final String id;
  final String companyId;
  final String transferNumber;
  final String fromWarehouseId;
  final String toWarehouseId;
  final String status;
  final DateTime transferDate;
  final String? notes;

  const StockTransferEntity({
    required this.id,
    required this.companyId,
    required this.transferNumber,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    required this.status,
    required this.transferDate,
    this.notes,
  });

  factory StockTransferEntity.fromMap(Map<String, dynamic> map) {
    return StockTransferEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      transferNumber: map['transfer_number'] as String,
      fromWarehouseId: map['from_warehouse_id'] as String,
      toWarehouseId: map['to_warehouse_id'] as String,
      status: map['status'] as String,
      transferDate: DateTime.parse(map['transfer_date'] as String),
      notes: map['notes'] as String?,
    );
  }
}

class StockAdjustmentEntity {
  final String id;
  final String companyId;
  final String warehouseId;
  final String productId;
  final String adjustmentType;
  final int quantity;
  final int unitCostCents;
  final String reason;
  final DateTime adjustmentDate;

  const StockAdjustmentEntity({
    required this.id,
    required this.companyId,
    required this.warehouseId,
    required this.productId,
    required this.adjustmentType,
    required this.quantity,
    required this.unitCostCents,
    required this.reason,
    required this.adjustmentDate,
  });

  double get unitCost => unitCostCents / 100.0;
  double get totalCost => (unitCostCents * quantity) / 100.0;

  factory StockAdjustmentEntity.fromMap(Map<String, dynamic> map) {
    return StockAdjustmentEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      warehouseId: map['warehouse_id'] as String,
      productId: map['product_id'] as String,
      adjustmentType: map['adjustment_type'] as String,
      quantity: map['quantity'] as int,
      unitCostCents: map['unit_cost'] as int,
      reason: map['reason'] as String,
      adjustmentDate: DateTime.parse(map['adjustment_date'] as String),
    );
  }
}
