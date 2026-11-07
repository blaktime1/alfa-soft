class PosShiftEntity {
  final String id;
  final String branchId;
  final String userId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int startingCashCents;
  final int expectedCashCents;
  final int? actualCashCents;
  final int? differenceCents;
  final String status;
  final String? notes;

  const PosShiftEntity({
    required this.id,
    required this.branchId,
    required this.userId,
    required this.openedAt,
    this.closedAt,
    required this.startingCashCents,
    this.expectedCashCents = 0,
    this.actualCashCents,
    this.differenceCents,
    this.status = 'OPEN',
    this.notes,
  });

  double get startingCash => startingCashCents / 100.0;
  double get expectedCash => expectedCashCents / 100.0;
  double? get actualCash => actualCashCents != null ? actualCashCents! / 100.0 : null;
  double? get difference => differenceCents != null ? differenceCents! / 100.0 : null;

  factory PosShiftEntity.fromMap(Map<String, dynamic> map) {
    return PosShiftEntity(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      openedAt: DateTime.parse(map['opened_at'] as String),
      closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
      startingCashCents: map['starting_cash'] as int,
      expectedCashCents: map['expected_cash'] as int? ?? 0,
      actualCashCents: map['actual_cash'] as int?,
      differenceCents: map['difference'] as int?,
      status: map['status'] as String,
      notes: map['notes'] as String?,
    );
  }
}

class SuspendedCartEntity {
  final String id;
  final String branchId;
  final String userId;
  final String holdReference;
  final String cartPayload;
  final DateTime createdAt;

  const SuspendedCartEntity({
    required this.id,
    required this.branchId,
    required this.userId,
    required this.holdReference,
    required this.cartPayload,
    required this.createdAt,
  });

  factory SuspendedCartEntity.fromMap(Map<String, dynamic> map) {
    return SuspendedCartEntity(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      userId: map['user_id'] as String,
      holdReference: map['hold_reference'] as String,
      cartPayload: map['cart_payload'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
