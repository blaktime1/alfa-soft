import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M007PackagingAndWarehousePricingSchema extends Migration {
  const M007PackagingAndWarehousePricingSchema()
      : super(version: 7, name: 'Packaging Units (Carton/Piece) and Warehouse-Specific Pricing Schema');

  @override
  void up(Database db) {
    // 1. Add packaging fields to products
    try {
      db.execute('ALTER TABLE products ADD COLUMN units_per_carton INTEGER NOT NULL DEFAULT 1;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE products ADD COLUMN carton_price INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE products ADD COLUMN carton_cost_price INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE products ADD COLUMN carton_barcode TEXT;');
    } catch (_) {}

    // 2. Add unit_type and multiplier to invoice items
    try {
      db.execute("ALTER TABLE sales_invoice_items ADD COLUMN unit_type TEXT NOT NULL DEFAULT 'PIECE';");
    } catch (_) {}
    try {
      db.execute("ALTER TABLE sales_invoice_items ADD COLUMN units_per_pack INTEGER NOT NULL DEFAULT 1;");
    } catch (_) {}

    // 3. Add unit_type to stock transfer items
    try {
      db.execute("ALTER TABLE stock_transfer_items ADD COLUMN unit_type TEXT NOT NULL DEFAULT 'PIECE';");
    } catch (_) {}
    try {
      db.execute("ALTER TABLE stock_transfer_items ADD COLUMN units_per_pack INTEGER NOT NULL DEFAULT 1;");
    } catch (_) {}

    // 4. Warehouse Specific Pricing Table
    db.execute('''
      CREATE TABLE IF NOT EXISTS warehouse_product_prices (
        id TEXT PRIMARY KEY,
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        sale_price INTEGER NOT NULL,
        wholesale_price INTEGER,
        carton_price INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(warehouse_id, product_id)
      );
      CREATE INDEX IF NOT EXISTS idx_wh_prod_prices ON warehouse_product_prices(warehouse_id, product_id);
    ''');
  }

  @override
  void down(Database db) {
    db.execute('DROP TABLE IF EXISTS warehouse_product_prices;');
  }
}
