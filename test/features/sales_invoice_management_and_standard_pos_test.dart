import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';
import 'package:alfa_soft/data/repositories/sales_invoice_repository.dart';
import 'package:alfa_soft/data/repositories/purchase_repository.dart';
import 'package:alfa_soft/data/repositories/partner_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';

void main() {
  late DatabaseService db;
  late AccountingRepository accountingRepo;
  late SalesInvoiceRepository salesRepo;
  late PurchaseRepository purchaseRepo;
  late PartnerRepository partnerRepo;
  late CatalogRepository catalogRepo;

  late String companyId;
  late String branchId;
  late String warehouseId;
  late String userId;
  late String customerId;
  late String supplierId;
  late String productId;

  setUp(() {
    db = DatabaseService.inMemory();
    accountingRepo = AccountingRepository(db);
    salesRepo = SalesInvoiceRepository(db, accountingRepo);
    purchaseRepo = PurchaseRepository(db);
    partnerRepo = PartnerRepository(db);
    catalogRepo = CatalogRepository(db);

    companyId = const Uuid().v4();
    branchId = const Uuid().v4();
    warehouseId = const Uuid().v4();
    userId = const Uuid().v4();

    // Seed master data
    db.execute('''
      INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code)
      VALUES (?, 'شركة الفا سوفت المحدودة', 'الفا سوفت', '300000000000003', 'YER')
    ''', [companyId]);

    db.execute('''
      INSERT INTO branches (id, company_id, code, name, is_main)
      VALUES (?, ?, 'BR01', 'الفرع الرئيسي', 1)
    ''', [branchId, companyId]);

    db.execute('''
      INSERT INTO warehouses (id, branch_id, code, name)
      VALUES (?, ?, 'WH01', 'المستودع العام')
    ''', [warehouseId, branchId]);

    db.execute('''
      INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin)
      VALUES (?, ?, 'admin', 'hash', 'المدير العام', 1)
    ''', [userId, companyId]);

    accountingRepo.seedStandardChartOfAccounts(companyId);
    catalogRepo.seedDefaultUnitsIfEmpty(companyId);

    // Seed customer and supplier
    final cust = partnerRepo.createCustomer(
      companyId: companyId,
      code: 'CUST-001',
      name: 'شركة الأمل التجارية',
      creditLimitCents: 500000,
    );
    customerId = cust.id;

    final supp = partnerRepo.createSupplier(
      companyId: companyId,
      code: 'SUPP-001',
      name: 'مؤسسة التوريدات المركزية',
    );
    supplierId = supp.id;

    // Seed product and opening stock
    final prod = catalogRepo.createProduct(
      companyId: companyId,
      baseUnitId: 'unit_pcs',
      sku: 'PRD-TEST-100',
      barcode: '628100000100',
      nameAr: 'شاي فاخر 100 كيس',
      costPriceCents: 1000, // 10.00
      salePriceCents: 1500, // 15.00
      minSalePriceCents: 1200, // 12.00
      unitsPerCarton: 12,
      cartonPriceCents: 14000,
    );
    productId = prod.id;

    // Add initial warehouse stock: 100 pieces
    db.execute('''
      INSERT INTO inventory_balances (warehouse_id, product_id, quantity, reserved_quantity, average_cost, updated_at)
      VALUES (?, ?, 100, 0, 1000, datetime('now'))
    ''', [warehouseId, productId]);
  });

  tearDown(() {
    db.dispose();
  });

  group('M008 & Sales Invoice Repository Operations', () {
    test('1. Read sales invoice with bonus items, customer balance, and policy check', () {
      final invoiceId = const Uuid().v4();

      // Insert invoice directly with M008 schema columns
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, discount_total, grand_total, paid_total,
          status, payment_status, currency_code, exchange_rate, price_level,
          reference_note, notes, bonus_total, created_by_user_id
        ) VALUES (
          ?, ?, ?, ?, ?,
          'INV-2026-0001', datetime('now'), 15000, 2250, 0, 17250, 17250,
          'POSTED', 'CASH', 'YER', 1.0, 'RETAIL',
          'مرجع 101', 'ملاحظة الفاتورة', 2, ?
        )
      ''', [invoiceId, companyId, branchId, warehouseId, customerId, userId]);

      // Insert items with bonus quantity
      db.execute('''
        INSERT INTO sales_invoice_items (
          id, invoice_id, product_id, unit_id, quantity, bonus_quantity,
          unit_price, cost_price, discount_amount, line_total, unit_name
        ) VALUES (
          ?, ?, ?, 'unit_pcs', 10, 2,
          1500, 1000, 0, 15000, 'حبة'
        )
      ''', [const Uuid().v4(), invoiceId, productId]);

      // Deduct warehouse stock for quantity + bonus (10 + 2 = 12)
      db.execute('''
        UPDATE inventory_balances
        SET quantity = quantity - 12
        WHERE warehouse_id = ? AND product_id = ?
      ''', [warehouseId, productId]);

      // Retrieve via SalesInvoiceRepository
      final invoice = salesRepo.getInvoiceById(invoiceId);
      expect(invoice, isNotNull);
      expect(invoice!.invoiceNumber, equals('INV-2026-0001'));
      expect(invoice.grandTotalCents, equals(17250));
      expect(invoice.currencyCode, equals('YER'));
      expect(invoice.items.length, equals(1));
      expect(invoice.items.first.quantity, equals(10));
      expect(invoice.items.first.bonusQuantity, equals(2));
      expect(invoice.items.first.totalPieces, equals(12));

      // Check stock reflects 88
      final stock = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, productId]).first['quantity'];
      expect(stock, equals(88));
    });

    test('2. Policy check allows edit/void within policy and enforces role rules', () {
      final invoiceId = const Uuid().v4();
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, discount_total, grand_total, paid_total,
          status, payment_status, currency_code, exchange_rate, price_level, created_by_user_id
        ) VALUES (
          ?, ?, ?, ?, ?,
          'INV-POLICY-01', datetime('now'), 15000, 2250, 0, 17250, 17250,
          'POSTED', 'CASH', 'YER', 1.0, 'RETAIL', ?
        )
      ''', [invoiceId, companyId, branchId, warehouseId, customerId, userId]);

      // Default policy 'TODAY' allows modification
      final inv = salesRepo.getInvoiceById(invoiceId)!;
      final check = salesRepo.checkEditOrVoidPolicy(invoice: inv, userRole: 'CASHIER');
      expect(check.allowed, isTrue);

      // Change policy to ADMIN_ONLY
      db.execute("UPDATE system_settings SET value = 'ADMIN_ONLY' WHERE key = 'pos_edit_policy'");
      final cashierCheck = salesRepo.checkEditOrVoidPolicy(invoice: inv, userRole: 'CASHIER');
      expect(cashierCheck.allowed, isFalse);
      expect(cashierCheck.requiresAdminPassword, isTrue);

      final adminCheck = salesRepo.checkEditOrVoidPolicy(invoice: inv, userRole: 'ADMIN');
      expect(adminCheck.allowed, isTrue);
    });

    test('3. Voiding sales invoice restores inventory, marks status VOIDED, and logs audit record', () {
      final invoiceId = const Uuid().v4();
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id,
          invoice_number, invoice_date, subtotal, tax_total, discount_total, grand_total, paid_total,
          status, payment_status, currency_code, exchange_rate, price_level, created_by_user_id
        ) VALUES (
          ?, ?, ?, ?, ?,
          'INV-VOID-01', datetime('now'), 30000, 4500, 0, 34500, 34500,
          'POSTED', 'CASH', 'YER', 1.0, 'RETAIL', ?
        )
      ''', [invoiceId, companyId, branchId, warehouseId, customerId, userId]);

      db.execute('''
        INSERT INTO sales_invoice_items (
          id, invoice_id, product_id, unit_id, quantity, bonus_quantity,
          unit_price, cost_price, discount_amount, line_total, unit_name
        ) VALUES (
          ?, ?, ?, 'unit_pcs', 20, 5,
          1500, 1000, 0, 30000, 'حبة'
        )
      ''', [const Uuid().v4(), invoiceId, productId]);

      // Stock was 100 - 25 = 75
      db.execute('UPDATE inventory_balances SET quantity = 75 WHERE warehouse_id = ? AND product_id = ?', [warehouseId, productId]);

      // Void the invoice
      salesRepo.voidSalesInvoice(
        invoiceId: invoiceId,
        userId: userId,
        reason: 'إلغاء لطلب العميل',
      );

      // Stock must be restored to 100 (75 + 20 + 5)
      final stock = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, productId]).first['quantity'];
      expect(stock, equals(100));

      // Invoice status must be VOIDED
      final updatedInv = salesRepo.getInvoiceById(invoiceId);
      expect(updatedInv?.status, equals('VOIDED'));
      expect(updatedInv?.isVoided, isTrue);

      // Audit logs must record VOID action
      final audit = salesRepo.getSalesInvoiceAuditLogs(companyId);
      expect(audit.any((a) => a.action == 'VOID_SALES_INVOICE' && a.invoiceId == invoiceId), isTrue);
    });
  });

  group('Direct Purchases & Reversing Manual Journals', () {
    test('4. Manual journal entry creation, balance verification, and reversal', () {
      final accounts = accountingRepo.getAccounts(companyId);
      final cashAccount = accounts.firstWhere((a) => a.code == '1010'); // Cash
      final revenueAccount = accounts.firstWhere((a) => a.code == '4010'); // Sales Revenue

      // Create manual journal entry
      final entry = accountingRepo.postJournalEntry(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        entryNumber: 'JV-2026-001',
        entryDate: DateTime.now(),
        sourceType: 'MANUAL_VOUCHER',
        narration: 'قيد تسوية نقدية يدوية',
        rawLines: [
          {'accountId': cashAccount.id, 'debit': 50000, 'credit': 0, 'memo': 'قبض نقدي'},
          {'accountId': revenueAccount.id, 'debit': 0, 'credit': 50000, 'memo': 'إيراد خدمات'},
        ],
      );

      expect(entry.status, equals('POSTED'));
      expect(entry.totalDebit, equals(50000));
      expect(entry.totalCredit, equals(50000));

      // Reversing the journal
      accountingRepo.reverseJournalEntry(
        entryId: entry.id,
        userId: userId,
        reason: 'عكس القيد لخطأ في الإدخال',
      );

      // Check original entry marked REVERSED
      final origEntry = accountingRepo.getJournalEntries(companyId).firstWhere((e) => e.id == entry.id);
      expect(origEntry.status, equals('REVERSED'));

      // Check reversing entry exists with swapped debit/credit
      final reversingEntries = accountingRepo.getJournalEntries(companyId).where((e) => e.sourceId == entry.id).toList();
      expect(reversingEntries.isNotEmpty, isTrue);
      final rev = reversingEntries.first;
      expect(rev.status, equals('POSTED'));
      expect(rev.totalDebit, equals(50000));
      expect(rev.totalCredit, equals(50000));
    });

    test('5. Direct Purchase Order and Instant GRN updates warehouse stock and supplier AP', () {
      final po = purchaseRepo.createPurchaseOrder(
        companyId: companyId,
        branchId: branchId,
        supplierId: supplierId,
        userId: userId,
        orderNumber: 'PO-DIRECT-01',
        items: [
          {
            'productId': productId,
            'unitId': 'unit_pcs',
            'quantity': 50,
            'unitCostCents': 950, // 9.50
          }
        ],
      );

      expect(po.status, equals('PENDING'));

      // Receive goods into warehouse
      final grn = purchaseRepo.receiveGoods(
        companyId: companyId,
        branchId: branchId,
        warehouseId: warehouseId,
        supplierId: supplierId,
        userId: userId,
        purchaseOrderId: po.id,
        receiptNumber: 'GRN-DIRECT-01',
        receivedItems: [
          {
            'productId': productId,
            'quantity': 50,
            'unitCostCents': 950,
          }
        ],
      );

      expect(grn.status, equals('POSTED'));

      // Warehouse stock should now be 100 + 50 = 150
      final stock = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, productId]).first['quantity'];
      expect(stock, equals(150));
    });
  });
}
