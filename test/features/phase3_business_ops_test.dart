import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/organization_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';
import 'package:alfa_soft/data/repositories/partner_repository.dart';
import 'package:alfa_soft/data/repositories/purchase_repository.dart';
import 'package:alfa_soft/data/repositories/inventory_operation_repository.dart';
import 'package:alfa_soft/data/repositories/pos_repository.dart';

void main() {
  group('Phase 3 — Business Operations & POS Integration Tests', () {
    late DatabaseService db;
    late OrganizationRepository orgRepo;
    late CatalogRepository catalogRepo;
    late PartnerRepository partnerRepo;
    late PurchaseRepository purchaseRepo;
    late InventoryOperationRepository invRepo;
    late PosRepository posRepo;

    late String companyId;
    late String branchId;
    late String warehouse1Id;
    late String warehouse2Id;
    late String supplierId;
    late String productId;
    late String unitId;
    late String userId;

    setUp(() {
      db = DatabaseService.inMemory();
      orgRepo = OrganizationRepository(db);
      catalogRepo = CatalogRepository(db);
      partnerRepo = PartnerRepository(db);
      purchaseRepo = PurchaseRepository(db);
      invRepo = InventoryOperationRepository(db);
      posRepo = PosRepository(db);

      // Seed Root Company
      companyId = 'comp_test_1';
      db.execute('''
        INSERT INTO companies (id, legal_name, trade_name, currency_code, is_active)
        VALUES (?, 'شركة الفا للعمليات', 'الفا سوفت', 'SAR', 1)
      ''', [companyId]);

      // Seed Branch & Warehouses
      final branch = orgRepo.createBranch(
        companyId: companyId,
        code: 'BR01',
        name: 'الفرع الرئيسي',
        isMain: true,
      );
      branchId = branch.id;

      final wh1 = orgRepo.createWarehouse(branchId: branchId, code: 'WH01', name: 'المستودع الرئيسي');
      warehouse1Id = wh1.id;
      final wh2 = orgRepo.createWarehouse(branchId: branchId, code: 'WH02', name: 'مستودع المعرض');
      warehouse2Id = wh2.id;

      // Seed User
      userId = 'usr_test_1';
      db.execute('''
        INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin, is_active)
        VALUES (?, ?, 'admin', 'hash', 'مدير النظام', 1, 1)
      ''', [userId, companyId]);

      // Seed Supplier
      final supplier = partnerRepo.createSupplier(
        companyId: companyId,
        code: 'SUPP-01',
        name: 'شركة الأغذية المتحدة',
      );
      supplierId = supplier.id;

      // Seed Product
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'BOX', name: 'كرتون');
      unitId = unit.id;
      final product = catalogRepo.createProduct(
        companyId: companyId,
        baseUnitId: unit.id,
        sku: 'SKU-OIL-01',
        nameAr: 'زيت زيتون بكر 1 لتر',
        costPriceCents: 5000, // 50.00 SAR
        salePriceCents: 7500, // 75.00 SAR
      );
      productId = product.id;
    });

    tearDown(() {
      db.dispose();
    });

    test('Purchasing: PO creation does NOT increase stock; GRN increments stock and recalculates MAC', () {
      // 1. Create Purchase Order for 10 units at 50.00 SAR
      final po = purchaseRepo.createPurchaseOrder(
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        userId: userId,
        orderNumber: 'PO-2026-001',
        items: [
          {
            'productId': productId,
            'unitId': unitId,
            'quantity': 10,
            'unitCostCents': 5000, // 50.00 SAR
          }
        ],
      );

      expect(po.status, equals('PENDING'));

      // NON-NEGOTIABLE CHECK: Stock must remain ZERO after PO creation
      final preBal = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse1Id, productId],
      );
      expect(preBal, isEmpty);

      // 2. First Physical Goods Receipt (GRN): 10 units at 50.00 SAR
      purchaseRepo.receiveGoods(
        companyId: companyId,
        branchId: branchId,
        warehouseId: warehouse1Id,
        supplierId: supplierId,
        userId: userId,
        purchaseOrderId: po.id,
        receiptNumber: 'GRN-2026-001',
        receivedItems: [
          {
            'productId': productId,
            'quantity': 10,
            'unitCostCents': 5000,
          }
        ],
      );

      final bal1 = db.select(
        'SELECT quantity, average_cost FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse1Id, productId],
      );
      expect(bal1.first['quantity'], equals(10));
      expect(bal1.first['average_cost'], equals(5000)); // 50.00 SAR

      // 3. Second Physical Goods Receipt: 10 units at 70.00 SAR
      // Expected new MAC = (10 * 50 + 10 * 70) / 20 = 1200 / 20 = 60.00 SAR (6000 cents)
      purchaseRepo.receiveGoods(
        companyId: companyId,
        branchId: branchId,
        warehouseId: warehouse1Id,
        supplierId: supplierId,
        userId: userId,
        receiptNumber: 'GRN-2026-002',
        receivedItems: [
          {
            'productId': productId,
            'quantity': 10,
            'unitCostCents': 7000,
          }
        ],
      );

      final bal2 = db.select(
        'SELECT quantity, average_cost FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse1Id, productId],
      );
      expect(bal2.first['quantity'], equals(20));
      expect(bal2.first['average_cost'], equals(6000)); // Exact Moving Average Cost!
    });

    test('Inventory Operations: inter-warehouse transfer and stock adjustment', () {
      // Seed initial 20 items in warehouse 1
      db.execute('''
        INSERT INTO inventory_balances (warehouse_id, product_id, quantity, average_cost)
        VALUES (?, ?, 20, 6000)
      ''', [warehouse1Id, productId]);

      // Transfer 5 items from WH1 to WH2
      invRepo.transferStock(
        companyId: companyId,
        fromWarehouseId: warehouse1Id,
        toWarehouseId: warehouse2Id,
        userId: userId,
        transferNumber: 'TR-001',
        items: [
          {
            'productId': productId,
            'quantity': 5,
            'unitCostCents': 6000,
          }
        ],
      );

      // Verify source warehouse balance deducted (20 - 5 = 15)
      final wh1Bal = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse1Id, productId],
      );
      expect(wh1Bal.first['quantity'], equals(15));

      // Verify destination warehouse balance incremented (0 + 5 = 5)
      final wh2Bal = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse2Id, productId],
      );
      expect(wh2Bal.first['quantity'], equals(5));

      // Perform Stock Adjustment on WH1: deficit of 2 damaged items
      invRepo.adjustStock(
        companyId: companyId,
        warehouseId: warehouse1Id,
        productId: productId,
        userId: userId,
        adjustmentType: 'DEFICIT',
        quantity: 2,
        unitCostCents: 6000,
        reason: 'تلف أثناء النقل الداخلي',
      );

      final wh1BalAfterAdj = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouse1Id, productId],
      );
      expect(wh1BalAfterAdj.first['quantity'], equals(13)); // 15 - 2 = 13
    });

    test('POS Shift: open, register cash sale, blind close and variance calculation', () {
      // 1. Open Shift with 300.00 SAR starting cash
      final shift = posRepo.openShift(
        branchId: branchId,
        userId: userId,
        startingCashCents: 30000, // 300.00 SAR
      );

      expect(shift.status, equals('OPEN'));
      expect(shift.startingCash, equals(300.00));

      // 2. Record a cash payment of 200.00 SAR during this shift
      db.execute('''
        INSERT INTO payments (id, company_id, branch_id, document_type, document_id, payment_method, amount, created_by_user_id)
        VALUES ('pay_1', ?, ?, 'SALES_INVOICE', 'inv_1', 'CASH', 20000, ?)
      ''', [companyId, branchId, userId]);

      // 3. Blind Close Shift with actual cash in drawer = 490.00 SAR (49000 cents)
      // Expected = 300.00 + 200.00 = 500.00 SAR (50000 cents)
      // Difference = 490.00 - 500.00 = -10.00 SAR (10 SAR deficit)
      final closedShift = posRepo.closeShift(
        shiftId: shift.id,
        actualCashCents: 49000,
        notes: 'عجز طفيف بقيمة 10 ريال',
      );

      expect(closedShift.status, equals('CLOSED'));
      expect(closedShift.expectedCash, equals(500.00));
      expect(closedShift.actualCash, equals(490.00));
      expect(closedShift.difference, equals(-10.00));
    });

    test('POS Suspended Sales: hold and resume cart', () {
      const payload = '[{"productId":"prod_1","qty":2,"price":150}]';

      final held = posRepo.suspendSale(
        branchId: branchId,
        userId: userId,
        holdReference: 'طاولة 4',
        cartPayload: payload,
      );

      final list = posRepo.getSuspendedSales(branchId);
      expect(list.length, equals(1));
      expect(list.first.holdReference, equals('طاولة 4'));

      final retrieved = posRepo.resumeSale(held.id);
      expect(retrieved, equals(payload));

      final emptyList = posRepo.getSuspendedSales(branchId);
      expect(emptyList, isEmpty); // Deleted after resume
    });
  });
}
