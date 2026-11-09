import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/partner_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';
import 'package:alfa_soft/data/repositories/organization_repository.dart';

void main() {
  group('Partner Management, Statement Reports & Credit Operations Test Suite', () {
    late DatabaseService db;
    late PartnerRepository partnerRepo;
    late CatalogRepository catalogRepo;
    late OrganizationRepository orgRepo;

    const companyId = 'comp_test_partners';
    late String branchId;
    late String warehouseId;
    late String unitId;
    const userId = 'usr_admin_1';

    setUp(() {
      db = DatabaseService.inMemory();
      partnerRepo = PartnerRepository(db);
      catalogRepo = CatalogRepository(db);
      orgRepo = OrganizationRepository(db);

      // Seed Company
      db.execute('''
        INSERT INTO companies (id, legal_name, trade_name, currency_code, is_active)
        VALUES (?, 'شركة الفا للتجارة والمقاولات', 'الفا ستور', 'SAR', 1)
      ''', [companyId]);

      // Seed Branch & Warehouse
      final branch = orgRepo.createBranch(companyId: companyId, code: 'BR01', name: 'الفرع الرئيسي', isMain: true);
      branchId = branch.id;
      final wh = orgRepo.createWarehouse(branchId: branchId, code: 'WH01', name: 'المستودع الرئيسي');
      warehouseId = wh.id;

      // Seed Admin User
      db.execute('''
        INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin, is_active)
        VALUES (?, ?, 'admin', 'hash_val', 'مدير النظام', 1, 1)
      ''', [userId, companyId]);

      // Seed Unit
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'PCS', name: 'قطعة');
      unitId = unit.id;
    });

    tearDown(() {
      db.dispose();
    });

    test('1. Customer CRUD: create, update, delete (soft-delete), and sync_outbox auditing', () {
      // 1. Create customer
      final customer = partnerRepo.createCustomer(
        companyId: companyId,
        code: 'CUST-001',
        name: 'مؤسسة الرياض التجارية',
        phone: '0551122334',
        creditLimitCents: 5000000, // 50,000.00 SAR
      );

      expect(customer.id, isNotEmpty);
      expect(customer.name, equals('مؤسسة الرياض التجارية'));
      expect(customer.creditLimitCents, equals(5000000));

      // Query raw customer
      var rows = db.select('SELECT * FROM customers WHERE id = ?', [customer.id]);
      expect(rows, isNotEmpty);
      expect(rows.first['name'], equals('مؤسسة الرياض التجارية'));
      expect(rows.first['is_active'], equals(1));

      // 2. Update customer
      partnerRepo.updateCustomer(
        id: customer.id,
        name: 'شركة الرياض العالمية المحدودة',
        phone: '0559988776',
        taxNumber: '310999999900003',
        creditLimitCents: 7500000, // 75,000.00 SAR
      );

      rows = db.select('SELECT * FROM customers WHERE id = ?', [customer.id]);
      expect(rows.first['name'], equals('شركة الرياض العالمية المحدودة'));
      expect(rows.first['phone'], equals('0559988776'));
      expect(rows.first['tax_number'], equals('310999999900003'));
      expect(rows.first['credit_limit'], equals(7500000));

      // 3. Delete customer (soft-delete)
      partnerRepo.deleteCustomer(customer.id);
      rows = db.select('SELECT * FROM customers WHERE id = ?', [customer.id]);
      expect(rows.first['is_active'], equals(0));

      // Active customers list should no longer include deleted customer
      final activeCusts = partnerRepo.getCustomers(companyId);
      expect(activeCusts.where((c) => c.id == customer.id), isEmpty);

      // Verify sync_outbox
      final outbox = db.select(
        'SELECT entity_type, operation FROM sync_outbox WHERE entity_type = "CUSTOMER" ORDER BY created_at ASC',
      );
      expect(outbox.length, equals(3));
      expect(outbox[0]['operation'], equals('CREATE'));
      expect(outbox[1]['operation'], equals('UPDATE'));
      expect(outbox[2]['operation'], equals('DELETE'));
    });

    test('2. Supplier CRUD: create, update, delete, and payment voucher recording', () {
      // 1. Create supplier
      final supplier = partnerRepo.createSupplier(
        companyId: companyId,
        code: 'SUP-001',
        name: 'مؤسسة التوريدات المتقدمة',
        phone: '0112233445',
        taxNumber: '300123456700003',
      );

      expect(supplier.id, isNotEmpty);
      expect(supplier.name, equals('مؤسسة التوريدات المتقدمة'));

      // 2. Update supplier
      partnerRepo.updateSupplier(
        id: supplier.id,
        name: 'شركة التوريدات المتقدمة الدولية',
        phone: '0119988776',
        taxNumber: '300123456700003',
      );

      var rows = db.select('SELECT * FROM suppliers WHERE id = ?', [supplier.id]);
      expect(rows.first['name'], equals('شركة التوريدات المتقدمة الدولية'));
      expect(rows.first['phone'], equals('0119988776'));

      // 3. Record supplier payment (سند صرف نقدي)
      partnerRepo.recordSupplierPayment(
        companyId: companyId,
        branchId: branchId,
        supplierId: supplier.id,
        amountHalalas: 250000, // 2,500.00 SAR
        paymentMethod: 'BANK_TRANSFER',
        referenceNumber: 'TRX-778899',
        notes: 'دفعة مشتريات تحت الحساب',
        userId: userId,
      );

      // Verify supplier statement shows payment as debit (reducing our payable balance)
      final statement = partnerRepo.getSupplierStatement(supplier.id);
      expect(statement.length, equals(1));
      expect(statement.first.docNumber, equals('TRX-778899'));
      expect(statement.first.debit, equals(2500.0));
      expect(statement.first.credit, equals(0.0));

      // 4. Delete supplier (soft-delete)
      partnerRepo.deleteSupplier(supplier.id);
      final activeSuppliers = partnerRepo.getSuppliers(companyId);
      expect(activeSuppliers.where((s) => s.id == supplier.id), isEmpty);
    });

    test('3. Product Catalog Update & Price Maintenance with security audit', () {
      // Create product
      final product = catalogRepo.createProduct(
        companyId: companyId,
        baseUnitId: unitId,
        sku: 'SKU-PRD-01',
        nameAr: 'طابعة باركود حرارية',
        costPriceCents: 45000, // 450.00 SAR
        salePriceCents: 65000, // 650.00 SAR
        minSalePriceCents: 60000, // 600.00 SAR
      );

      // Update product with modified prices and wholesale price
      catalogRepo.updateProduct(
        id: product.id,
        nameAr: 'طابعة باركود حرارية V2 متطورة',
        costPriceCents: 42000, // 420.00 SAR (modified cost price)
        salePriceCents: 69000, // 690.00 SAR (retail)
        minSalePriceCents: 62000,
        reorderLevel: 5,
        modifiedBy: 'admin',
      );

      final rows = db.select('SELECT * FROM products WHERE id = ?', [product.id]);
      expect(rows.first['name_ar'], equals('طابعة باركود حرارية V2 متطورة'));
      expect(rows.first['cost_price'], equals(42000));
      expect(rows.first['sale_price'], equals(69000));

      // Soft delete product
      catalogRepo.deleteProduct(product.id);
      final activeProds = catalogRepo.getProducts(companyId: companyId);
      expect(activeProds.where((p) => p.id == product.id), isEmpty);
    });

    test('4. POS Credit Sales, Payment Receipt (سند قبض) & Chronological Statement with Running Balance', () {
      // 1. Create a customer with credit limit
      final customer = partnerRepo.createCustomer(
        companyId: companyId,
        code: 'CUST-CREDIT-01',
        name: 'عميل آجل: مؤسسة البناء الحديث',
        phone: '0501112233',
        creditLimitCents: 10000000, // 100,000.00 SAR
      );

      // 2. Insert first credit sales invoice: Grand Total = 1,150.00 SAR (115,000 cents), Paid = 0
      final inv1Date = '2026-11-01 10:00:00';
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, grand_total, paid_total,
          status, payment_status, created_by_user_id
        ) VALUES (
          'inv_001', ?, ?, ?, ?,
          'INV-2026-001', ?, 100000, 15000, 115000, 0,
          'POSTED', 'CREDIT', ?
        )
      ''', [companyId, branchId, warehouseId, customer.id, inv1Date, userId]);

      // Update customer balance to reflect credit sale
      db.execute('UPDATE customers SET current_balance = current_balance + 115000 WHERE id = ?', [customer.id]);

      // 3. Insert second credit sales invoice: Grand Total = 2,300.00 SAR (230,000 cents), Advance Paid = 300.00 SAR (30,000 cents)
      final inv2Date = '2026-11-03 14:00:00';
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, grand_total, paid_total,
          status, payment_status, created_by_user_id
        ) VALUES (
          'inv_002', ?, ?, ?, ?,
          'INV-2026-002', ?, 200000, 30000, 230000, 30000,
          'POSTED', 'PARTIAL', ?
        )
      ''', [companyId, branchId, warehouseId, customer.id, inv2Date, userId]);

      // Remaining due from invoice 2 is 2,000.00 SAR (200,000 cents)
      db.execute('UPDATE customers SET current_balance = current_balance + 200000 WHERE id = ?', [customer.id]);

      var custRow = db.select('SELECT current_balance FROM customers WHERE id = ?', [customer.id]).first;
      expect(custRow['current_balance'], equals(315000)); // 3,150.00 SAR total debt

      // 4. Customer returns and pays cash (سند قبض نقدي) 1,500.00 SAR (150,000 cents)
      partnerRepo.recordCustomerPayment(
        companyId: companyId,
        branchId: branchId,
        customerId: customer.id,
        amountHalalas: 150000, // 1,500.00 SAR
        paymentMethod: 'CASH',
        referenceNumber: 'REC-9988',
        notes: 'دفعة سداد نقدية من الحساب الآجل في نقطة البيع',
        userId: userId,
      );

      // Verify customer debt is now 3,150 - 1,500 = 1,650.00 SAR (165,000 cents)
      custRow = db.select('SELECT current_balance FROM customers WHERE id = ?', [customer.id]).first;
      expect(custRow['current_balance'], equals(165000));

      // 5. Generate Customer Statement of Account
      final statement = partnerRepo.getCustomerStatement(customer.id);
      expect(statement.length, equals(3));

      // Entry 1: Invoice 1 (Debit = 1150.0, Credit = 0, Running Balance = 1150.0)
      final e1 = statement[0];
      expect(e1.docNumber, equals('INV-2026-001'));
      expect(e1.debit, equals(1150.0));
      expect(e1.credit, equals(0.0));
      expect(e1.runningBalance, equals(1150.0));

      // Entry 2: Invoice 2 (Debit = 2300.0, Credit = 300.0, Running Balance = 1150 + (2300 - 300) = 3150.0)
      final e2 = statement[1];
      expect(e2.docNumber, equals('INV-2026-002'));
      expect(e2.debit, equals(2300.0));
      expect(e2.credit, equals(300.0));
      expect(e2.runningBalance, equals(3150.0));

      // Entry 3: Payment Receipt (Debit = 0, Credit = 1500.0, Running Balance = 3150 - 1500 = 1650.0)
      final e3 = statement[2];
      expect(e3.docNumber, equals('REC-9988'));
      expect(e3.debit, equals(0.0));
      expect(e3.credit, equals(1500.0));
      expect(e3.runningBalance, equals(1650.0));
      expect(e3.notes, contains('تحصيل وسداد نقدي لحساب آجل'));
    });
  });
}
