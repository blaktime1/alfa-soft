import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/catalog.dart';
import '../../core/sync/outbox_manager.dart';

class CatalogRepository {
  final DatabaseService _db;
  final OutboxManager _outbox;

  CatalogRepository(this._db) : _outbox = OutboxManager(_db);

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
    String sql = 'SELECT * FROM products WHERE company_id = ? AND is_active = 1';
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
    int unitsPerCarton = 1,
    int cartonPriceCents = 0,
    int cartonCostPriceCents = 0,
    String? cartonBarcode,
  }) {
    const uuid = Uuid();
    final id = 'prod_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO products (
          id, company_id, category_id, base_unit_id, sku, barcode,
          name_ar, name_en, cost_price, sale_price, min_sale_price,
          reorder_level, track_inventory, is_active,
          units_per_carton, carton_price, carton_cost_price, carton_barcode
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
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
        unitsPerCarton,
        cartonPriceCents,
        cartonCostPriceCents,
        cartonBarcode?.trim(),
      ]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_PRODUCT', 'PRODUCT', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, 'Created SKU: $sku, Name: $nameAr, Packaging: $unitsPerCarton pcs/carton']);
    });

    try {
      _outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: id,
        operation: SyncOperation.create,
        payload: {
          'id': id,
          'company_id': companyId,
          'sku': sku.trim(),
          'barcode': barcode?.trim(),
          'name_ar': nameAr.trim(),
          'name_en': nameEn?.trim(),
          'cost_price': costPriceCents,
          'sale_price': salePriceCents,
          'min_sale_price': minSalePriceCents,
          'reorder_level': reorderLevel,
          'units_per_carton': unitsPerCarton,
          'carton_price': cartonPriceCents,
          'carton_cost_price': cartonCostPriceCents,
          'carton_barcode': cartonBarcode?.trim(),
          'is_active': 1,
        },
      );
    } catch (_) {}

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
      unitsPerCarton: unitsPerCarton,
      cartonPriceCents: cartonPriceCents,
      cartonCostPriceCents: cartonCostPriceCents,
      cartonBarcode: cartonBarcode,
    );
  }

  void updateProduct({
    required String id,
    required String nameAr,
    String? nameEn,
    String? barcode,
    required int costPriceCents,
    required int salePriceCents,
    required int minSalePriceCents,
    required int reorderLevel,
    String? categoryId,
    String? baseUnitId,
    bool isActive = true,
    int unitsPerCarton = 1,
    int cartonPriceCents = 0,
    int cartonCostPriceCents = 0,
    String? cartonBarcode,
    String? modifiedBy,
  }) {
    _db.transaction((tx) {
      tx.execute('''
        UPDATE products 
        SET name_ar = ?, name_en = ?, barcode = ?, cost_price = ?, sale_price = ?,
            min_sale_price = ?, reorder_level = ?, category_id = ?, base_unit_id = COALESCE(?, base_unit_id),
            is_active = ?, units_per_carton = ?, carton_price = ?, carton_cost_price = ?,
            carton_barcode = ?, updated_at = datetime('now')
        WHERE id = ?
      ''', [
        nameAr.trim(),
        nameEn?.trim(),
        barcode?.trim(),
        costPriceCents,
        salePriceCents,
        minSalePriceCents,
        reorderLevel,
        categoryId,
        baseUnitId,
        isActive ? 1 : 0,
        unitsPerCarton,
        cartonPriceCents,
        cartonCostPriceCents,
        cartonBarcode?.trim(),
        id,
      ]);

      const uuid = Uuid();
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, 'SYSTEM', ?, 'LOCAL_DESKTOP', 'UPDATE_PRODUCT', 'PRODUCT', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        modifiedBy ?? 'ADMIN',
        id,
        'Updated: $nameAr, Cost: ${costPriceCents / 100}, Sale: ${salePriceCents / 100}, Pack: $unitsPerCarton',
      ]);
    });

    try {
      _outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: id,
        operation: SyncOperation.update,
        payload: {
          'id': id,
          'name_ar': nameAr.trim(),
          'name_en': nameEn?.trim(),
          'barcode': barcode?.trim(),
          'cost_price': costPriceCents,
          'sale_price': salePriceCents,
          'min_sale_price': minSalePriceCents,
          'reorder_level': reorderLevel,
          'units_per_carton': unitsPerCarton,
          'carton_price': cartonPriceCents,
          'carton_cost_price': cartonCostPriceCents,
          'carton_barcode': cartonBarcode?.trim(),
          'is_active': isActive ? 1 : 0,
        },
      );
    } catch (_) {}
  }

  void deleteProduct(String id, [String? deletedBy]) {
    _db.execute('UPDATE products SET is_active = 0, updated_at = datetime("now") WHERE id = ?', [id]);

    try {
      const uuid = Uuid();
      _db.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, 'SYSTEM', ?, 'LOCAL_DESKTOP', 'DELETE_PRODUCT', 'PRODUCT', ?, 'Product deactivated')
      ''', ['aud_${uuid.v4()}', deletedBy ?? 'ADMIN', id]);

      _outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: id,
        operation: SyncOperation.delete,
        payload: {'id': id, 'is_active': 0},
      );
    } catch (_) {}
  }

  /// Sets or updates a warehouse-specific price override for a product
  void setWarehousePrice({
    required String warehouseId,
    required String productId,
    required int salePriceCents,
    int? wholesalePriceCents,
    int? cartonPriceCents,
  }) {
    const uuid = Uuid();
    final id = 'whp_${uuid.v4()}';

    _db.execute('''
      INSERT INTO warehouse_product_prices (
        id, warehouse_id, product_id, sale_price, wholesale_price, carton_price, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(warehouse_id, product_id) DO UPDATE SET
        sale_price = excluded.sale_price,
        wholesale_price = excluded.wholesale_price,
        carton_price = excluded.carton_price,
        updated_at = datetime('now')
    ''', [id, warehouseId, productId, salePriceCents, wholesalePriceCents, cartonPriceCents]);
  }

  /// Retrieves warehouse-specific price overrides for a product
  List<Map<String, dynamic>> getWarehousePrices(String productId) {
    final rows = _db.select('''
      SELECT wpp.*, w.name as warehouse_name
      FROM warehouse_product_prices wpp
      JOIN warehouses w ON w.id = wpp.warehouse_id
      WHERE wpp.product_id = ?
    ''', [productId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Returns effective prices for a product in a given warehouse:
  /// checks warehouse override first, then falls back to product default prices.
  Map<String, int> getEffectivePrices({
    required String productId,
    required String warehouseId,
  }) {
    final whPrice = _db.select('''
      SELECT sale_price, wholesale_price, carton_price
      FROM warehouse_product_prices
      WHERE warehouse_id = ? AND product_id = ?
    ''', [warehouseId, productId]);

    final prod = _db.select('''
      SELECT sale_price, min_sale_price, carton_price, units_per_carton
      FROM products
      WHERE id = ?
    ''', [productId]).first;

    final defaultSale = prod['sale_price'] as int? ?? 0;
    final defaultWholesale = prod['min_sale_price'] as int? ?? defaultSale;
    final defaultCarton = prod['carton_price'] as int? ?? 0;

    if (whPrice.isNotEmpty) {
      final wp = whPrice.first;
      return {
        'sale_price': wp['sale_price'] as int? ?? defaultSale,
        'wholesale_price': wp['wholesale_price'] as int? ?? defaultWholesale,
        'carton_price': (wp['carton_price'] != null && (wp['carton_price'] as int) > 0)
            ? wp['carton_price'] as int
            : defaultCarton,
      };
    }

    return {
      'sale_price': defaultSale,
      'wholesale_price': defaultWholesale,
      'carton_price': defaultCarton,
    };
  }
}
