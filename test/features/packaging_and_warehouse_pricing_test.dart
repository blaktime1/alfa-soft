import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/domain/entities/catalog.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';
import 'package:alfa_soft/data/repositories/inventory_operation_repository.dart';

void main() {
  late DatabaseService db;
  late CatalogRepository catalogRepo;
  late InventoryOperationRepository inventoryRepo;

  setUp(() {
    db = DatabaseService.inMemory();
    catalogRepo = CatalogRepository(db);
    inventoryRepo = InventoryOperationRepository(db);

    // Seed basic organization
    db.execute('''
      INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code)
      VALUES ('comp_pkg_test', 'شركة التعبئة والتسعير', 'الفا سوفت', '300000000000003', 'SAR');
    ''');
    db.execute('''
      INSERT INTO branches (id, company_id, code, name, is_active)
      VALUES ('branch_1', 'comp_pkg_test', 'BR01', 'الفرع الرئيسي', 1);
    ''');
    db.execute('''
      INSERT INTO warehouses (id, branch_id, code, name, is_active)
      VALUES 
        ('wh_main', 'branch_1', 'WH01', 'المستودع المركزي', 1),
        ('wh_store', 'branch_1', 'WH02', 'مستودع المتجر', 1);
    ''');
    db.execute('''
      INSERT INTO units (id, company_id, code, name)
      VALUES ('unit_pcs', 'comp_pkg_test', 'PCS', 'حبة');
    ''');
    db.execute('''
      INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin, is_active)
      VALUES ('usr_admin', 'comp_pkg_test', 'admin', 'hash', 'مدير النظام', 1, 1);
    ''');
  });

  tearDown(() {
    db.dispose();
  });

  group('نظام التعبئة (كرتون / حبة) وحسابات المخزون', () {
    test('1. formatStockBreakdown يحسب تكسير الكرتون والحبة بدقة', () {
      final productWithCarton = ProductEntity(
        id: 'p1',
        companyId: 'comp_pkg_test',
        baseUnitId: 'unit_pcs',
        sku: 'OIL-1L',
        barcode: '6281001',
        nameAr: 'زيت طعام 1 لتر',
        salePriceCents: 1500, // 15 SAR
        costPriceCents: 1000,
        unitsPerCarton: 12,
        cartonPriceCents: 16000, // 160 SAR (خصم للكرتون)
        cartonCostPriceCents: 11000,
        cartonBarcode: '6281001-BOX',
      );

      expect(productWithCarton.hasCarton, isTrue);
      expect(productWithCarton.unitsPerCarton, 12);
      expect(productWithCarton.cartonPrice, 160.0);

      // 25 pieces = 2 cartons and 1 piece
      expect(productWithCarton.formatStockBreakdown(25), '2 كرتون و 1 حبة (25 حبة)');
      // 24 pieces = exactly 2 cartons
      expect(productWithCarton.formatStockBreakdown(24), '2 كرتون (24 حبة)');
      // 7 pieces = 7 pieces
      expect(productWithCarton.formatStockBreakdown(7), '7 حبة');
      // 0 pieces = 0 حبة
      expect(productWithCarton.formatStockBreakdown(0), '0 حبة');

      // Product without carton
      final productWithoutCarton = ProductEntity(
        id: 'p2',
        companyId: 'comp_pkg_test',
        baseUnitId: 'unit_pcs',
        sku: 'BREAD',
        nameAr: 'خبز',
        salePriceCents: 100,
      );
      expect(productWithoutCarton.hasCarton, isFalse);
      expect(productWithoutCarton.formatStockBreakdown(50), '50 حبة');
    });

    test('2. إضافة صنف مع مواصفات الكرتون وحفظه في قاعدة البيانات', () {
      final product = catalogRepo.createProduct(
        companyId: 'comp_pkg_test',
        baseUnitId: 'unit_pcs',
        sku: 'JUICE-250',
        nameAr: 'عصير برتقال 250 مل',
        barcode: '6282001',
        salePriceCents: 250,
        costPriceCents: 180,
        unitsPerCarton: 24,
        cartonPriceCents: 5500, // 55.00 SAR
        cartonCostPriceCents: 4000,
        cartonBarcode: '6282001-CTN',
      );

      expect(product.id, isNotEmpty);
      expect(product.unitsPerCarton, 24);
      expect(product.cartonPriceCents, 5500);
      expect(product.cartonCostPriceCents, 4000);
      expect(product.cartonBarcode, '6282001-CTN');

      // Verify row in DB
      final rows = db.select('SELECT units_per_carton, carton_price, carton_barcode FROM products WHERE id = ?', [product.id]);
      expect(rows.first['units_per_carton'], 24);
      expect(rows.first['carton_price'], 5500);
      expect(rows.first['carton_barcode'], '6282001-CTN');
    });
  });

  group('التسعير المتعدد لكل مخزن ونقل البضائع مع فارق السعر', () {
    test('3. تسعير خاص بكل مخزن (Warehouse-Specific Price Override)', () {
      final product = catalogRepo.createProduct(
        companyId: 'comp_pkg_test',
        baseUnitId: 'unit_pcs',
        sku: 'WATER-500',
        nameAr: 'مياه 500 مل',
        salePriceCents: 100, // 1.00 SAR base
        minSalePriceCents: 90,
        costPriceCents: 60,
        unitsPerCarton: 40,
        cartonPriceCents: 3500,
      );

      // Default prices for wh_main before override
      var pricesWhMain = catalogRepo.getEffectivePrices(productId: product.id, warehouseId: 'wh_main');
      expect(pricesWhMain['sale_price'], 100);

      // Set custom higher price for wh_store (e.g. airport/remote store: 1.50 SAR retail, 45.00 SAR carton)
      catalogRepo.setWarehousePrice(
        warehouseId: 'wh_store',
        productId: product.id,
        salePriceCents: 150,
        cartonPriceCents: 4500,
      );

      // Verify wh_store has overridden prices
      var pricesWhStore = catalogRepo.getEffectivePrices(productId: product.id, warehouseId: 'wh_store');
      expect(pricesWhStore['sale_price'], 150);
      expect(pricesWhStore['carton_price'], 4500);

      // Verify wh_main still retains base catalog price
      pricesWhMain = catalogRepo.getEffectivePrices(productId: product.id, warehouseId: 'wh_main');
      expect(pricesWhMain['sale_price'], 100);
      expect(pricesWhMain['carton_price'], 3500);
    });

    test('4. نقل كميات بالكرتون من مخزن 1 إلى مخزن 2 مع تفعيل فارق السعر', () {
      final product = catalogRepo.createProduct(
        companyId: 'comp_pkg_test',
        baseUnitId: 'unit_pcs',
        sku: 'MILK-1L',
        nameAr: 'حليب كامل الدسم',
        salePriceCents: 500, // 5.00 SAR in Warehouse 1
        costPriceCents: 350,
        unitsPerCarton: 10,
      );

      // Initialize stock in wh_main: 100 pieces (10 cartons)
      db.execute('''
        INSERT INTO inventory_balances (warehouse_id, product_id, quantity, reserved_quantity, average_cost)
        VALUES ('wh_main', ?, 100, 0, 350);
      ''', [product.id]);

      // Transfer 3 cartons (3 * 10 = 30 pieces) to wh_store
      const cartonsToTransfer = 3;
      final piecesToTransfer = cartonsToTransfer * product.unitsPerCarton; // 30 pieces

      inventoryRepo.transferStock(
        companyId: 'comp_pkg_test',
        fromWarehouseId: 'wh_main',
        toWarehouseId: 'wh_store',
        userId: 'usr_admin',
        transferNumber: 'TR-1001',
        notes: 'تحويل 3 كرتون حليب للمتجر الفرعي مع تعديل السعر',
        items: [
          {
            'productId': product.id,
            'quantity': piecesToTransfer,
            'unitCostCents': product.costPriceCents,
          }
        ],
      );

      // Check balances in DB
      final whMainBalance = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        ['wh_main', product.id],
      ).first['quantity'] as int;
      final whStoreBalance = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        ['wh_store', product.id],
      ).first['quantity'] as int;

      expect(whMainBalance, 70); // 100 - 30 = 70 pieces (7 cartons)
      expect(whStoreBalance, 30); // 0 + 30 = 30 pieces (3 cartons)

      // Apply new higher price in wh_store (6.00 SAR instead of 5.00 SAR)
      catalogRepo.setWarehousePrice(
        warehouseId: 'wh_store',
        productId: product.id,
        salePriceCents: 600,
      );

      final whStorePrices = catalogRepo.getEffectivePrices(productId: product.id, warehouseId: 'wh_store');
      expect(whStorePrices['sale_price'], 600);

      final whMainPrices = catalogRepo.getEffectivePrices(productId: product.id, warehouseId: 'wh_main');
      expect(whMainPrices['sale_price'], 500);
    });
  });
}
