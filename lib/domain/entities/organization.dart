import '../../core/types/enums.dart';

class CompanyEntity {
  final String id;
  final String legalName;
  final String tradeName;
  final String? taxNumber;
  final String? commercialRegistration;
  final CurrencyCode currency;
  final String? logoPath;
  final bool isActive;
  final DateTime createdAt;

  const CompanyEntity({
    required this.id,
    required this.legalName,
    required this.tradeName,
    this.taxNumber,
    this.commercialRegistration,
    required this.currency,
    this.logoPath,
    this.isActive = true,
    required this.createdAt,
  });

  factory CompanyEntity.fromMap(Map<String, dynamic> map) {
    return CompanyEntity(
      id: map['id'] as String,
      legalName: map['legal_name'] as String,
      tradeName: map['trade_name'] as String,
      taxNumber: map['tax_number'] as String?,
      commercialRegistration: map['commercial_registration'] as String?,
      currency: CurrencyCode.values.firstWhere(
        (c) => c.code == map['currency_code'],
        orElse: () => CurrencyCode.sar,
      ),
      logoPath: map['logo_path'] as String?,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class BranchEntity {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? phone;
  final String? address;
  final bool isMain;
  final bool isActive;

  const BranchEntity({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.phone,
    this.address,
    this.isMain = false,
    this.isActive = true,
  });

  factory BranchEntity.fromMap(Map<String, dynamic> map) {
    return BranchEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      isMain: (map['is_main'] as int) == 1,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class WarehouseEntity {
  final String id;
  final String branchId;
  final String code;
  final String name;
  final bool isActive;

  const WarehouseEntity({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  factory WarehouseEntity.fromMap(Map<String, dynamic> map) {
    return WarehouseEntity(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}
