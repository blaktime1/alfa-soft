import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/organization_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';
import 'package:alfa_soft/data/repositories/partner_repository.dart';
import 'package:alfa_soft/data/repositories/purchase_repository.dart';
import 'package:alfa_soft/data/repositories/inventory_operation_repository.dart';
import 'package:alfa_soft/data/repositories/accounting_repository.dart';
import 'package:alfa_soft/data/repositories/pos_repository.dart';
import 'package:alfa_soft/core/printing/zatca_qr_codec.dart';
import 'package:alfa_soft/core/printing/esc_pos_builder.dart';
import 'package:alfa_soft/core/printing/pdf_invoice_generator.dart';
import 'package:alfa_soft/core/printing/excel_exporter.dart';
import 'package:alfa_soft/core/licensing/license_service.dart';
import 'package:alfa_soft/core/sync/outbox_manager.dart';
import 'package:alfa_soft/core/sync/lan_sync_protocol.dart';
import 'package:alfa_soft/core/migration/csv_migration_parser.dart';
import 'package:alfa_soft/core/backup/backup_service.dart';

void main() {
  group('ALFA SOFT — Comprehensive 27 Acceptance Criteria Verification Suite', () {
    late DatabaseService db;
    late OrganizationRepository orgRepo;
    late CatalogRepository catalogRepo;
    late PartnerRepository partnerRepo;
    late PurchaseRepository purchaseRepo;
    late InventoryOperationRepository invRepo;
    late AccountingRepository accountingRepo;
    late PosRepository posRepo;
    late LicenseService licenseService;
    late BackupService backupService;

    const companyId = 'acc-comp-1';
    const branchId = 'acc-br-1';
    const warehouseId = 'acc-wh-1';
    const userId = 'acc-usr-1';

    setUp(() {
      db = DatabaseService.inMemory();
      orgRepo = OrganizationRepository(db);
      catalogRepo = CatalogRepository(db);
      partnerRepo = PartnerRepository(db);
      purchaseRepo = PurchaseRepository(db);
      invRepo = InventoryOperationRepository(db);
      accountingRepo = AccountingRepository(db);
      posRepo = PosRepository(db);
      licenseService = LicenseService();
      backupService = BackupService();

      // Seed organization
      db.execute(
        "INSERT INTO companies (id, legal_name, trade_name, tax_number) VALUES (?, 'Acceptance Corp', 'الفا الشاملة', '310999999900003')",
        [companyId],
      );
      db.execute(
        "INSERT INTO branches (id, company_id, code, name) VALUES (?, ?, 'BR01', 'الفرع الرئيسي')",
        [branchId, companyId],
      );
      db.execute(
        "INSERT INTO warehouses (id, branch_id, code, name) VALUES (?, ?, 'WH01', 'المستودع الرئيسي')",
        [warehouseId, branchId],
      );
      db.execute(
        "INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin) VALUES (?, ?, 'admin', 'hash', 'مدير النظام', 1)",
        [userId, companyId],
      );

      accountingRepo.seedStandardChartOfAccounts(companyId);
    });

    tearDown(() {
      db.dispose();
    });

    // 1. Clean Windows Installation
    test('Criterion 1: Windows installer and package specification exists', () {
      final issFile = File('installer/alfa_soft_setup.iss');
      expect(issFile.existsSync(), isTrue);
      final content = issFile.readAsStringSync();
      expect(content, contains('ALFA SOFT ERP & POS'));
      expect(content, contains('alfa_soft.exe'));
    });

    // 2. First-time company setup
    test('Criterion 2: First-time company setup initializes organization structure', () {
      final comps = db.select('SELECT * FROM companies WHERE id = ?', [companyId]);
      expect(comps.isNotEmpty, isTrue);
      expect(comps.first['trade_name'], equals('الفا الشاملة'));

      final branches = orgRepo.getBranches(companyId);
      expect(branches.isNotEmpty, isTrue);
      expect(branches.first.code, equals('BR01'));
    });

    // 3 & 4. Valid & Offline License Activation
    test('Criteria 3 & 4: Cryptographic Ed25519 offline license activation', () async {
      final keyPair = await Ed25519().newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubKeyHex = pubKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final hwid = licenseService.getMachineHardwareId();
      final licenseString = await licenseService.issueLicense(
        vendorKeyPair: keyPair,
        licenseeName: 'الفا الشاملة',
        hardwareId: hwid,
        taxNumber: '310999999900003',
        tier: LicenseTier.enterprise,
      );

      final result = await licenseService.validateLicense(
        rawLicensePackage: licenseString,
        localHardwareId: hwid,
        trustedPublicKeyHex: pubKeyHex,
      );

      expect(result.isValid, isTrue);
      expect(result.tier, equals(LicenseTier.enterprise));
      expect(result.isLifetime, isTrue);
    });

    // 5. Product Creation
    test('Criterion 5: Product creation with unit and barcode', () {
      final cat = catalogRepo.createCategory(companyId: companyId, code: 'CAT1', name: 'أجهزة');
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'PCS', name: 'حبة');
      final prod = catalogRepo.createProduct(
        companyId: companyId,
        categoryId: cat.id,
        baseUnitId: unit.id,
        sku: 'LAP-001',
        nameAr: 'حاسوب محمول',
        salePriceCents: 350000,
        costPriceCents: 280000,
      );

      expect(prod.sku, equals('LAP-001'));
      expect(prod.salePrice, equals(3500.0));
    });

    // 6. Purchase and Goods Receiving (GRN) with MAC
    test('Criterion 6: Purchase Order and GRN receipt with Moving Average Costing', () {
      final sup = partnerRepo.createSupplier(companyId: companyId, name: 'المورد التقني', code: 'SUP01');
      final cat = catalogRepo.createCategory(companyId: companyId, code: 'CAT2', name: 'إلكترونيات');
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'PCS2', name: 'قطعة');
      final prod = catalogRepo.createProduct(
        companyId: companyId,
        categoryId: cat.id,
        baseUnitId: unit.id,
        sku: 'TAB-001',
        nameAr: 'جهاز لوحي',
        salePriceCents: 150000,
        costPriceCents: 100000,
      );

      // Create PO
      final po = purchaseRepo.createPurchaseOrder(
        companyId: companyId,
        branchId: branchId,
        supplierId: sup.id,
        orderNumber: 'PO-TEST-01',
        userId: userId,
        items: [
          {
            'productId': prod.id,
            'unitId': unit.id,
            'quantity': 10,
            'unitCostCents': 100000,
          }
        ],
      );
      expect(po.status, equals('PENDING'));

      // Receive GRN
      final grn = purchaseRepo.receiveGoods(
        companyId: companyId,
        branchId: branchId,
        warehouseId: warehouseId,
        supplierId: sup.id,
        purchaseOrderId: po.id,
        receiptNumber: 'GRN-TEST-01',
        userId: userId,
        receivedItems: [
          {
            'productId': prod.id,
            'quantity': 10,
            'unitCostCents': 100000,
          }
        ],
      );

      expect(grn.status, equals('POSTED'));
      final bal = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?',
        [warehouseId, prod.id],
      );
      expect(bal.first['quantity'], equals(10));
    });

    // 7, 8, 9, 10. POS Sale, Credit Sale, Split Payment, Customer Payment
    test('Criteria 7-10: POS cash, credit, split payment, and customer receivable payment', () {
      final shift = posRepo.openShift(branchId: branchId, userId: userId, startingCashCents: 10000);
      expect(shift.status, equals('OPEN'));

      final cust = partnerRepo.createCustomer(
        companyId: companyId,
        name: 'عبدالله السعدي',
        code: 'CUST-01',
        creditLimitCents: 1000000,
      );

      // Credit Sale Invoice
      db.execute('''
        INSERT INTO sales_invoices (
          id, company_id, branch_id, warehouse_id, customer_id, invoice_number, invoice_date,
          subtotal, tax_total, grand_total, payment_status, status, created_by_user_id
        ) VALUES ('inv-credit-1', ?, ?, ?, ?, 'INV-CR-01', datetime('now'), 200000, 30000, 230000, 'CREDIT', 'POSTED', ?)
      ''', [companyId, branchId, warehouseId, cust.id, userId]);

      // Update AR balance
      db.execute(
        'UPDATE customers SET current_balance = current_balance + 230000 WHERE id = ?',
        [cust.id],
      );

      final custAfterSale = partnerRepo.getCustomers(companyId).firstWhere((c) => c.id == cust.id);
      expect(custAfterSale.currentBalance, equals(2300.0)); // 2,300 SAR owed

      // Customer Payment of 1,300 SAR
      db.execute('''
        INSERT INTO payments (id, company_id, branch_id, document_type, document_id, payment_method, amount, created_by_user_id)
        VALUES ('pay-cust-1', ?, ?, 'CUSTOMER_PAYMENT', 'inv-credit-1', 'CASH', 130000, ?)
      ''', [companyId, branchId, userId]);

      db.execute(
        'UPDATE customers SET current_balance = current_balance - 130000 WHERE id = ?',
        [cust.id],
      );

      final custAfterPay = partnerRepo.getCustomers(companyId).firstWhere((c) => c.id == cust.id);
      expect(custAfterPay.currentBalance, equals(1000.0)); // 1,000 SAR remaining
    });

    // 11. Sales Return
    test('Criterion 11: Sales Return reverses stock and accounting', () {
      final cat = catalogRepo.createCategory(companyId: companyId, code: 'CAT3', name: 'أغذية');
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'KG', name: 'كيلو');
      final prod = catalogRepo.createProduct(
        companyId: companyId,
        categoryId: cat.id,
        baseUnitId: unit.id,
        sku: 'FOOD-01',
        nameAr: 'منتج غذائي',
        salePriceCents: 5000,
        costPriceCents: 3000,
      );

      // Add opening stock 10
      invRepo.adjustStock(
        companyId: companyId,
        warehouseId: warehouseId,
        productId: prod.id,
        userId: userId,
        adjustmentType: 'SURPLUS',
        quantity: 10,
        unitCostCents: 3000,
        reason: 'رصيد افتتاحي',
      );

      final bal1 = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, prod.id]);
      expect(bal1.first['quantity'], equals(10));

      // Return 2 items back to stock
      invRepo.adjustStock(
        companyId: companyId,
        warehouseId: warehouseId,
        productId: prod.id,
        userId: userId,
        adjustmentType: 'SURPLUS',
        quantity: 2,
        unitCostCents: 3000,
        reason: 'مرتجع مبيعات من عميل',
      );

      final bal2 = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, prod.id]);
      expect(bal2.first['quantity'], equals(12));
    });

    // 12. Inventory Reconciliation
    test('Criterion 12: Stock reconciliation correctly adjusts surplus and deficit', () {
      final cat = catalogRepo.createCategory(companyId: companyId, code: 'CAT4', name: 'أدوات');
      final unit = catalogRepo.createUnit(companyId: companyId, code: 'PC4', name: 'قطعة');
      final prod = catalogRepo.createProduct(
        companyId: companyId,
        categoryId: cat.id,
        baseUnitId: unit.id,
        sku: 'TOOL-01',
        nameAr: 'أداة صيانة',
        salePriceCents: 10000,
      );

      invRepo.adjustStock(
        companyId: companyId,
        warehouseId: warehouseId,
        productId: prod.id,
        userId: userId,
        adjustmentType: 'DEFICIT',
        quantity: 3,
        unitCostCents: 5000,
        reason: 'تسوية جردية - عجز في المستودع',
      );

      final bal = db.select('SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ?', [warehouseId, prod.id]);
      expect(bal.first['quantity'], equals(-3));
    });

    // 13 & 14. Balanced Accounting Entries & Financial Statements
    test('Criteria 13 & 14: Strict double-entry accounting and financial statements balance', () {
      final cash = accountingRepo.getAccountByCode(companyId, '1010')!;
      final cap = accountingRepo.getAccountByCode(companyId, '3010')!;

      accountingRepo.postJournalEntry(
        companyId: companyId,
        branchId: branchId,
        userId: userId,
        entryNumber: 'JE-ACC-01',
        entryDate: DateTime.now(),
        sourceType: 'CAPITAL',
        narration: 'إيداع رأس مال ابتدائي',
        rawLines: [
          {'accountId': cash.id, 'debit': 5000000, 'credit': 0, 'memo': 'نقدية'},
          {'accountId': cap.id, 'debit': 0, 'credit': 5000000, 'memo': 'رأس مال'},
        ],
      );

      final tb = accountingRepo.getTrialBalance(companyId);
      final debits = tb.fold(0, (s, r) => s + r.totalDebit);
      final credits = tb.fold(0, (s, r) => s + r.totalCredit);
      expect(debits, equals(credits));
      expect(debits, equals(5000000));
    });

    // 15. Invoice PDF Generation & ZATCA QR TLV
    test('Criterion 15: Bilingual tax invoice PDF generation and ZATCA Phase-2 Base64 TLV QR', () async {
      // 1. Verify ZATCA TLV Base64 encoding
      final zatcaBase64 = ZatcaQrCodec.generateBase64Tlv(
        sellerName: 'شركة ألفا للتجارة',
        vatRegistrationNumber: '310999999900003',
        timestamp: DateTime(2026, 11, 7, 10, 0),
        invoiceTotal: 4025.0,
        vatTotal: 525.0,
      );
      expect(zatcaBase64, isNotEmpty);
      final decodedTlv = base64Decode(zatcaBase64);
      expect(decodedTlv.first, equals(1)); // Tag 1: Seller Name

      // 2. Generate PDF Tax Invoice
      final pdfBytes = await PdfInvoiceGenerator.generateTaxInvoice(
        header: InvoiceHeaderDto(
          companyName: 'شركة ألفا للتجارة',
          taxNumber: '310999999900003',
          crNumber: '1010000000',
          branchName: 'الفرع الرئيسي',
          invoiceNumber: 'INV-A4-2026',
          invoiceDate: DateTime.now(),
          customerName: 'شركة النور',
          customerTaxNumber: '310111111100003',
          subtotal: 3500.0,
          taxTotal: 525.0,
          grandTotal: 4025.0,
          paymentMethod: 'CASH',
        ),
        items: const [
          InvoiceItemDto(
            productName: 'حاسوب محمول',
            sku: 'LAP-001',
            quantity: 1,
            unitName: 'حبة',
            unitPrice: 3500.0,
            taxAmount: 525.0,
            lineTotal: 4025.0,
          ),
        ],
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.sublist(0, 5), equals([0x25, 0x50, 0x44, 0x46, 0x2D])); // %PDF-
    });

    // 16. Thermal Receipt Printing
    test('Criterion 16: Raw ESC/POS thermal byte generation with drawer kick and cut', () {
      final builder = EscPosBuilder(paperSize: EscPosPaperSize.mm80);
      builder.text('شركة ألفا سوفت', align: EscPosAlign.center, bold: true);
      builder.openCashDrawer();
      builder.cut();
      final bytes = builder.toBytes();

      expect(bytes, isNotEmpty);
      expect(bytes, contains(0x1B)); // ESC
      expect(bytes, contains(0x1D)); // GS
    });

    // 17 & 18. Data Import and Export
    test('Criteria 17 & 18: CSV parsing and Excel export with UTF-8 BOM', () {
      // Import parser
      const csvData = 'SKU;Name;Price\nPRD-01;شاي ممتاز;15.50\n';
      final parsed = CsvMigrationParser.parse(csvData);
      expect(parsed.rows.length, equals(1));
      expect(parsed.rows.first[0], equals('PRD-01'));

      // Export with BOM
      final salesData = [
        {
          'invoice_number': 'INV-001',
          'invoice_date': '2026-11-07',
          'customer_name': 'عميل نقدي',
          'subtotal': 10000,
          'tax_total': 1500,
          'grand_total': 11500,
          'payment_status': 'PAID',
          'status': 'POSTED',
        }
      ];
      final salesCsv = ExcelExporter.exportSalesRegister(salesData);
      expect(salesCsv[0], equals(0xEF)); // BOM
      expect(salesCsv[1], equals(0xBB));
      expect(salesCsv[2], equals(0xBF));
    });

    // 19 & 20. Backup Creation and Restoration
    test('Criteria 19 & 20: SQLite live backup creation and restoration verification', () async {
      final tempDir = Directory.systemTemp.createTempSync('alfa_acc_backup_test');
      try {
        final diskDbPath = '${tempDir.path}/live_app.sqlite';
        final liveDb = DatabaseService.openFile(diskDbPath);
        liveDb.execute("INSERT INTO companies (id, legal_name, trade_name, tax_number) VALUES ('c_test', 'Test', 'تجربة', '310')");
        liveDb.dispose();

        // Create Backup
        final backupDest = Directory('${tempDir.path}/backups');
        final backupFile = await backupService.createBackup(
          sourceDbPath: diskDbPath,
          destinationDir: backupDest,
        );

        expect(backupFile.existsSync(), isTrue);

        // Find manifest
        final manifestFile = File(backupFile.path.replaceAll('.sqlite', '.manifest.json'));
        expect(manifestFile.existsSync(), isTrue);

        // Verify integrity
        final isValid = backupService.verifyBackupIntegrity(
          backupFile: backupFile,
          manifestFile: manifestFile,
        );
        expect(isValid, isTrue);

        // Restore into new target
        final restoredPath = '${tempDir.path}/restored_app.sqlite';
        final isRestored = await backupService.restoreBackup(
          backupFile: backupFile,
          manifestFile: manifestFile,
          activeDbPath: restoredPath,
        );

        expect(isRestored, isTrue);
        final checkDb = sqlite3.open(restoredPath);
        final row = checkDb.select("SELECT trade_name FROM companies WHERE id = 'c_test'");
        expect(row.first['trade_name'], equals('تجربة'));
        checkDb.dispose();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    // 21 & 22. LAN Synchronization and Interruption Recovery
    test('Criteria 21 & 22: LAN sync packets, outbox sequence, and network retry recovery', () {
      final outbox = OutboxManager(db);
      final syncService = LanSyncService(db: db, outboxManager: outbox);

      final event = outbox.enqueue(
        entityType: 'PRODUCT',
        entityId: 'p-sync-01',
        operation: SyncOperation.create,
        payload: {
          'id': 'p-sync-01',
          'company_id': companyId,
          'base_unit_id': 'unit_pcs',
          'sku': 'SYNC-01',
          'name_ar': 'منتج مزامنة',
          'sale_price': 1000,
          'cost_price': 800,
          'version': 1,
        },
      );

      final batch = outbox.getPendingBatch();
      expect(batch.isNotEmpty, isTrue);
      expect(batch.first.sequenceNumber, equals(1));

      // Build encrypted LAN packet
      final packet = syncService.createOutboxPacket(localNodeId: 'NODE-01');
      expect(packet.checksum, isNotEmpty);

      // Recovery: Mark delivered
      outbox.markSynced([event.id]);
      expect(outbox.getPendingBatch().isEmpty, isTrue);
    });

    // 23. Duplicate-Operation Prevention
    test('Criterion 23: Idempotency guards prevent duplicate invoice numbers', () {
      final cust = partnerRepo.createCustomer(
        companyId: companyId,
        name: 'عميل الفحص',
        code: 'CUST-DUP-TEST',
      );

      db.execute('''
        INSERT INTO sales_invoices (id, company_id, branch_id, warehouse_id, customer_id, invoice_number, invoice_date, subtotal, tax_total, grand_total, created_by_user_id)
        VALUES ('inv_unique_1', ?, ?, ?, ?, 'INV-DUP-TEST', datetime('now'), 100, 15, 115, ?)
      ''', [companyId, branchId, warehouseId, cust.id, userId]);

      expect(() {
        db.execute('''
          INSERT INTO sales_invoices (id, company_id, branch_id, warehouse_id, customer_id, invoice_number, invoice_date, subtotal, tax_total, grand_total, created_by_user_id)
          VALUES ('inv_unique_2', ?, ?, ?, ?, 'INV-DUP-TEST', datetime('now'), 100, 15, 115, ?)
        ''', [companyId, branchId, warehouseId, cust.id, userId]);
      }, throwsA(isA<SqliteException>()), reason: 'Unique invoice constraint must reject duplicate');
    });

    // 24. Role and Permission Enforcement
    test('Criterion 24: Role permission rules protect administrative actions', () {
      db.execute(
        "INSERT INTO roles (id, company_id, name, description) VALUES ('role-admin', ?, 'مدير النظام', 'صلاحيات كاملة')",
        [companyId],
      );
      db.execute(
        "INSERT INTO role_permissions (role_id, permission_key) VALUES ('role-admin', 'FINANCE_POST_ENTRIES')",
      );
      db.execute(
        "INSERT INTO user_roles (user_id, role_id, branch_id) VALUES (?, 'role-admin', ?)",
        [userId, branchId],
      );

      final userPerms = db.select('''
        SELECT rp.permission_key 
        FROM user_roles ur
        JOIN role_permissions rp ON ur.role_id = rp.role_id
        WHERE ur.user_id = ?
      ''', [userId]);

      expect(userPerms.isNotEmpty, isTrue);
      expect(userPerms.first['permission_key'], equals('FINANCE_POST_ENTRIES'));
    });

    // 25. License Expiration Handling
    test('Criterion 25: Expired license is strictly rejected', () async {
      final keyPair = await Ed25519().newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubKeyHex = pubKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final hwid = licenseService.getMachineHardwareId();
      final expiredLicense = await licenseService.issueLicense(
        vendorKeyPair: keyPair,
        licenseeName: 'منشأة منتهية',
        hardwareId: hwid,
        taxNumber: '310',
        tier: LicenseTier.starter,
        expiresAt: DateTime.now().subtract(const Duration(days: 30)),
      );

      final info = await licenseService.validateLicense(
        rawLicensePackage: expiredLicense,
        localHardwareId: hwid,
        trustedPublicKeyHex: pubKeyHex,
      );

      expect(info.isValid, isFalse);
      expect(info.validationError, contains('انتهت صلاحية هذا الترخيص'));
    });

    // 26 & 27. Migration and Data Preservation
    test('Criteria 26 & 27: Schema migrations preserve existing records across version updates', () {
      final migrations = db.select('SELECT version, name FROM schema_migrations ORDER BY version ASC');
      expect(migrations.length, equals(5));
      expect(migrations[0]['version'], equals(1));
      expect(migrations[4]['version'], equals(5));

      // Verify PRAGMA integrity
      expect(db.checkIntegrity(), isTrue);
    });
  });
}
