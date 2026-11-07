class CustomerEntity {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? phone;
  final String? taxNumber;
  final int creditLimitCents;
  final int currentBalanceCents;
  final bool isActive;

  const CustomerEntity({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.phone,
    this.taxNumber,
    this.creditLimitCents = 0,
    this.currentBalanceCents = 0,
    this.isActive = true,
  });

  double get creditLimit => creditLimitCents / 100.0;
  double get currentBalance => currentBalanceCents / 100.0;

  factory CustomerEntity.fromMap(Map<String, dynamic> map) {
    return CustomerEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      taxNumber: map['tax_number'] as String?,
      creditLimitCents: map['credit_limit'] as int,
      currentBalanceCents: map['current_balance'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class SupplierEntity {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? phone;
  final String? taxNumber;
  final int currentBalanceCents;
  final bool isActive;

  const SupplierEntity({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.phone,
    this.taxNumber,
    this.currentBalanceCents = 0,
    this.isActive = true,
  });

  double get currentBalance => currentBalanceCents / 100.0;

  factory SupplierEntity.fromMap(Map<String, dynamic> map) {
    return SupplierEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      taxNumber: map['tax_number'] as String?,
      currentBalanceCents: map['current_balance'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}
