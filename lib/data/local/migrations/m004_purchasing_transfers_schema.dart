import 'package:sqlite3/sqlite3.dart';
import 'migration.dart';

class M004PurchasingTransfersSchema extends Migration {
  const M004PurchasingTransfersSchema()
      : super(version: 4, name: 'Purchasing, GRN, Stock Transfers and Suspended Carts Schema');

  @override
  void up(Database db) {
    db.execute('''
      -- Purchase Orders Table
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        supplier_id TEXT NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        order_number TEXT NOT NULL,
        order_date TEXT NOT NULL DEFAULT (datetime('now')),
        expected_date TEXT,
        subtotal INTEGER NOT NULL DEFAULT 0,
        tax_total INTEGER NOT NULL DEFAULT 0,
        grand_total INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED'
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        UNIQUE(company_id, order_number)
      );

      -- Purchase Order Items Table
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id TEXT PRIMARY KEY,
        purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL,
        received_quantity INTEGER NOT NULL DEFAULT 0,
        unit_cost INTEGER NOT NULL,
        line_total INTEGER NOT NULL
      );

      -- Goods Received Notes (GRN) Table - Physical Receipt
      CREATE TABLE IF NOT EXISTS goods_receipt_notes (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        purchase_order_id TEXT REFERENCES purchase_orders(id) ON DELETE SET NULL,
        supplier_id TEXT NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        receipt_number TEXT NOT NULL,
        receipt_date TEXT NOT NULL DEFAULT (datetime('now')),
        total_cost INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'POSTED',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        UNIQUE(company_id, receipt_number)
      );

      -- Goods Receipt Items Table
      CREATE TABLE IF NOT EXISTS goods_receipt_items (
        id TEXT PRIMARY KEY,
        receipt_id TEXT NOT NULL REFERENCES goods_receipt_notes(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        total_cost INTEGER NOT NULL
      );

      -- Inter-Warehouse Stock Transfers Table
      CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        transfer_number TEXT NOT NULL,
        from_warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        to_warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        status TEXT NOT NULL DEFAULT 'COMPLETED', -- 'PENDING', 'IN_TRANSIT', 'COMPLETED', 'CANCELLED'
        transfer_date TEXT NOT NULL DEFAULT (datetime('now')),
        notes TEXT,
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        UNIQUE(company_id, transfer_number)
      );

      -- Stock Transfer Items Table
      CREATE TABLE IF NOT EXISTS stock_transfer_items (
        id TEXT PRIMARY KEY,
        transfer_id TEXT NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL
      );

      -- Stock Adjustments Table (Physical inventory surplus / deficit)
      CREATE TABLE IF NOT EXISTS stock_adjustments (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
        product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        adjustment_type TEXT NOT NULL, -- 'SURPLUS', 'DEFICIT', 'DAMAGED'
        quantity INTEGER NOT NULL, -- Positive for surplus, negative for deficit
        unit_cost INTEGER NOT NULL,
        reason TEXT NOT NULL,
        adjustment_date TEXT NOT NULL DEFAULT (datetime('now')),
        created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
      );

      -- POS Suspended Carts Table
      CREATE TABLE IF NOT EXISTS pos_suspended_sales (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
        hold_reference TEXT NOT NULL,
        cart_payload TEXT NOT NULL, -- JSON serialized items
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    ''');
  }

  @override
  void down(Database db) {
    db.execute('''
      DROP TABLE IF EXISTS pos_suspended_sales;
      DROP TABLE IF EXISTS stock_adjustments;
      DROP TABLE IF EXISTS stock_transfer_items;
      DROP TABLE IF EXISTS stock_transfers;
      DROP TABLE IF EXISTS goods_receipt_items;
      DROP TABLE IF EXISTS goods_receipt_notes;
      DROP TABLE IF EXISTS purchase_order_items;
      DROP TABLE IF EXISTS purchase_orders;
    ''');
  }
}
