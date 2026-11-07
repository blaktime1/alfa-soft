class UnitEntity {
  final String id;
  final String companyId;
  final String code;
  final String name;

  const UnitEntity({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
  });

  factory UnitEntity.fromMap(Map<String, dynamic> map) {
    return UnitEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
    );
  }
}

class CategoryEntity {
  final String id;
  final String companyId;
  final String? parentId;
  final String name;
  final String? code;

  const CategoryEntity({
    required this.id,
    required this.companyId,
    this.parentId,
    required this.name,
    this.code,
  });

  factory CategoryEntity.fromMap(Map<String, dynamic> map) {
    return CategoryEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      parentId: map['parent_id'] as String?,
      name: map['name'] as String,
      code: map['code'] as String?,
    );
  }
}

class ProductEntity {
  final String id;
  final String companyId;
  final String? categoryId;
  final String baseUnitId;
  final String sku;
  final String? barcode;
  final String nameAr;
  final String? nameEn;
  final int costPriceCents;
  final int salePriceCents;
  final int minSalePriceCents;
  final int reorderLevel;
  final bool trackInventory;
  final bool isActive;

  const ProductEntity({
    required this.id,
    required this.companyId,
    this.categoryId,
    required this.baseUnitId,
    required this.sku,
    this.barcode,
    required this.nameAr,
    this.nameEn,
    this.costPriceCents = 0,
    this.salePriceCents = 0,
    this.minSalePriceCents = 0,
    this.reorderLevel = 0,
    this.trackInventory = true,
    this.isActive = true,
  });

  double get costPrice => costPriceCents / 100.0;
  double get salePrice => salePriceCents / 100.0;
  double get minSalePrice => minSalePriceCents / 100.0;

  factory ProductEntity.fromMap(Map<String, dynamic> map) {
    return ProductEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      categoryId: map['category_id'] as String?,
      baseUnitId: map['base_unit_id'] as String,
      sku: map['sku'] as String,
      barcode: map['barcode'] as String?,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String?,
      costPriceCents: map['cost_price'] as int,
      salePriceCents: map['sale_price'] as int,
      minSalePriceCents: map['min_sale_price'] as int,
      reorderLevel: map['reorder_level'] as int,
      trackInventory: (map['track_inventory'] as int) == 1,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}
