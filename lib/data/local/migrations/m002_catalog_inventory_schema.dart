import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M002CatalogInventorySchema extends Migration {
  const M002CatalogInventorySchema()
      : super(version: 2, name: 'Product Catalog and Inventory Ledger Schema');

  @override
  void up(Database db) {
    db.execute('''
      -- Units of Measurement Table
      CREATE TABLE IF NOT EXISTS units (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(company_id, code)
      );

      -- Categories Table
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        parent_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        code TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1
      );

      -- Products Table
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
        base_unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
        sku TEXT NOT NULL,
        barcode TEXT,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        cost_price INTEGER NOT NULL DEFAULT 0, -- Minor units
        sale_price INTEGER NOT NULL DEFAULT 0,
        min_sale_price INTEGER NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 0,
        has_variants INTEGER NOT NULL DEFAULT 0,
        track_inventory INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(company_id, sku)
      );
      CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);

      -- Inventory Balances Table (Cached read model)
      CREATE TABLE IF NOT EXISTS inventory_balances (
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL DEFAULT 0,
        reserved_quantity INTEGER NOT NULL DEFAULT 0,
        average_cost INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY(warehouse_id, product_id)
      );

      -- Immutable Inventory Movements Table (Ledger-backed)
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        movement_type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        total_cost INTEGER NOT NULL,
        reference_document_type TEXT NOT NULL,
        reference_document_id TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_inv_movement_ref ON inventory_movements(reference_document_type, reference_document_id);
      CREATE INDEX IF NOT EXISTS idx_inv_movement_prod ON inventory_movements(warehouse_id, product_id);
    ''');
  }

  @override
  void down(Database db) {
    db.execute('''
      DROP TABLE IF EXISTS inventory_movements;
      DROP TABLE IF EXISTS inventory_balances;
      DROP TABLE IF EXISTS products;
      DROP TABLE IF EXISTS categories;
      DROP TABLE IF EXISTS units;
    ''');
  }
}
