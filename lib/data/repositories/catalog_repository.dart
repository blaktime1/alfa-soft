import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/catalog.dart';

class CatalogRepository {
  final DatabaseService _db;
  const CatalogRepository(this._db);

  List<UnitEntity> getUnits(String companyId) {
    final result = _db.select('SELECT * FROM units WHERE company_id = ? ORDER BY code ASC', [companyId]);
    return result.map((r) => UnitEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  UnitEntity createUnit({
    required String companyId,
    required String code,
    required String name,
  }) {
    const uuid = Uuid();
    final id = 'unit_${uuid.v4()}';

    _db.execute('''
      INSERT INTO units (id, company_id, code, name)
      VALUES (?, ?, ?, ?)
    ''', [id, companyId, code.trim(), name.trim()]);

    return UnitEntity(id: id, companyId: companyId, code: code, name: name);
  }

  List<CategoryEntity> getCategories(String companyId) {
    final result = _db.select('SELECT * FROM categories WHERE company_id = ? ORDER BY name ASC', [companyId]);
    return result.map((r) => CategoryEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  CategoryEntity createCategory({
    required String companyId,
    required String name,
    String? code,
    String? parentId,
  }) {
    const uuid = Uuid();
    final id = 'cat_${uuid.v4()}';

    _db.execute('''
      INSERT INTO categories (id, company_id, parent_id, name, code)
      VALUES (?, ?, ?, ?, ?)
    ''', [id, companyId, parentId, name.trim(), code?.trim()]);

    return CategoryEntity(
      id: id,
      companyId: companyId,
      name: name,
      code: code,
      parentId: parentId,
    );
  }

  List<ProductEntity> getProducts({
    required String companyId,
    String? query,
    String? categoryId,
  }) {
    String sql = 'SELECT * FROM products WHERE company_id = ?';
    final params = <Object?>[companyId];

    if (categoryId != null && categoryId.isNotEmpty) {
      sql += ' AND category_id = ?';
      params.add(categoryId);
    }

    if (query != null && query.trim().isNotEmpty) {
      sql += ' AND (sku LIKE ? OR barcode LIKE ? OR name_ar LIKE ? OR name_en LIKE ?)';
      final q = '%${query.trim()}%';
      params.addAll([q, q, q, q]);
    }

    sql += ' ORDER BY created_at DESC';
    final result = _db.select(sql, params);
    return result.map((r) => ProductEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  ProductEntity createProduct({
    required String companyId,
    String? categoryId,
    required String baseUnitId,
    required String sku,
    String? barcode,
    required String nameAr,
    String? nameEn,
    int costPriceCents = 0,
    int salePriceCents = 0,
    int minSalePriceCents = 0,
    int reorderLevel = 0,
    bool trackInventory = true,
  }) {
    const uuid = Uuid();
    final id = 'prod_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO products (
          id, company_id, category_id, base_unit_id, sku, barcode,
          name_ar, name_en, cost_price, sale_price, min_sale_price,
          reorder_level, track_inventory, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ''', [
        id,
        companyId,
        categoryId,
        baseUnitId,
        sku.trim(),
        barcode?.trim(),
        nameAr.trim(),
        nameEn?.trim(),
        costPriceCents,
        salePriceCents,
        minSalePriceCents,
        reorderLevel,
        trackInventory ? 1 : 0,
      ]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_PRODUCT', 'PRODUCT', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, 'Created SKU: $sku, Name: $nameAr']);
    });

    return ProductEntity(
      id: id,
      companyId: companyId,
      categoryId: categoryId,
      baseUnitId: baseUnitId,
      sku: sku,
      barcode: barcode,
      nameAr: nameAr,
      nameEn: nameEn,
      costPriceCents: costPriceCents,
      salePriceCents: salePriceCents,
      minSalePriceCents: minSalePriceCents,
      reorderLevel: reorderLevel,
      trackInventory: trackInventory,
    );
  }
}
