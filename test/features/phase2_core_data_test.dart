import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/organization_repository.dart';
import 'package:alfa_soft/data/repositories/catalog_repository.dart';
import 'package:alfa_soft/data/repositories/partner_repository.dart';
import 'package:alfa_soft/data/repositories/user_repository.dart';

void main() {
  group('Phase 2 — Core Business Data Integration Tests', () {
    late DatabaseService db;
    late OrganizationRepository orgRepo;
    late CatalogRepository catalogRepo;
    late PartnerRepository partnerRepo;
    late UserRepository userRepo;
    late String companyId;

    setUp(() {
      db = DatabaseService.inMemory();
      orgRepo = OrganizationRepository(db);
      catalogRepo = CatalogRepository(db);
      partnerRepo = PartnerRepository(db);
      userRepo = UserRepository(db);

      // Seed root company
      companyId = 'comp_test_1';
      db.execute('''
        INSERT INTO companies (id, legal_name, trade_name, currency_code, is_active)
        VALUES (?, 'شركة الفا للتجارة', 'الفا سوفت', 'SAR', 1)
      ''', [companyId]);
    });

    tearDown(() {
      db.dispose();
    });

    test('Organization: create branch and warehouse hierarchy', () {
      final branch1 = orgRepo.createBranch(
        companyId: companyId,
        code: 'BR01',
        name: 'فرع الرياض الرئيسي',
        phone: '0501234567',
        isMain: true,
      );
      expect(branch1.isMain, isTrue);

      final branch2 = orgRepo.createBranch(
        companyId: companyId,
        code: 'BR02',
        name: 'فرع جدة',
        isMain: true, // Should unset branch1 as main
      );

      final branches = orgRepo.getBranches(companyId);
      expect(branches.length, equals(2));
      final b1Updated = branches.firstWhere((b) => b.id == branch1.id);
      expect(b1Updated.isMain, isFalse); // Enforces single main branch

      final wh1 = orgRepo.createWarehouse(
        branchId: branch2.id,
        code: 'WH_JED',
        name: 'مستودع جدة المركزي',
      );
      final warehouses = orgRepo.getWarehouses(branch2.id);
      expect(warehouses.length, equals(1));
      expect(warehouses.first.id, equals(wh1.id));
    });

    test('Catalog: create category, unit, and product with pricing', () {
      final unit = catalogRepo.createUnit(
        companyId: companyId,
        code: 'BOX',
        name: 'كرتون 12 حبة',
      );
      expect(unit.code, equals('BOX'));

      final category = catalogRepo.createCategory(
        companyId: companyId,
        name: 'مواد غذائية',
        code: 'FOOD',
      );
      expect(category.name, equals('مواد غذائية'));

      final product = catalogRepo.createProduct(
        companyId: companyId,
        categoryId: category.id,
        baseUnitId: unit.id,
        sku: 'SKU-FOOD-001',
        barcode: '6281001234567',
        nameAr: 'أرز بسمتي فاخر 10 كجم',
        costPriceCents: 6500, // 65.00 SAR
        salePriceCents: 8500, // 85.00 SAR
        minSalePriceCents: 7500,
        reorderLevel: 25,
      );

      expect(product.salePrice, equals(85.00));
      expect(product.costPrice, equals(65.00));

      // Test Query
      final searchResult = catalogRepo.getProducts(
        companyId: companyId,
        query: 'بسمتي',
      );
      expect(searchResult.length, equals(1));
      expect(searchResult.first.sku, equals('SKU-FOOD-001'));
    });

    test('Partners: manage customers with credit limits and suppliers', () {
      final customer = partnerRepo.createCustomer(
        companyId: companyId,
        code: 'CUST-001',
        name: 'مؤسسة الأفق للمقاولات',
        phone: '0559988776',
        creditLimitCents: 1500000, // 15,000.00 SAR
      );

      expect(customer.creditLimit, equals(15000.00));
      expect(customer.currentBalance, equals(0.0));

      final supplier = partnerRepo.createSupplier(
        companyId: companyId,
        code: 'SUPP-001',
        name: 'شركة التوريدات العالمية',
        phone: '0112233445',
        taxNumber: '310022334400003',
      );

      expect(supplier.name, equals('شركة التوريدات العالمية'));

      final customersList = partnerRepo.getCustomers(companyId, query: 'الأفق');
      expect(customersList.length, equals(1));

      final suppliersList = partnerRepo.getSuppliers(companyId, query: 'التوريدات');
      expect(suppliersList.length, equals(1));
    });

    test('Users & RBAC: authentication and role assignment', () {
      final user = userRepo.createUser(
        companyId: companyId,
        username: 'cashier1',
        password: 'Password@123',
        fullName: 'أحمد الكاشير',
        isAdmin: false,
      );

      expect(user.username, equals('cashier1'));

      // Test valid authentication
      final authSuccess = userRepo.authenticate('cashier1', 'Password@123');
      expect(authSuccess, isNotNull);
      expect(authSuccess!.id, equals(user.id));

      // Test invalid password
      final authFail = userRepo.authenticate('cashier1', 'WrongPassword');
      expect(authFail, isNull);

      // Create Role and assign
      final role = userRepo.createRole(
        companyId: companyId,
        name: 'CASHIER_ROLE',
        description: 'صلاحيات نقطة البيع فقط',
        permissions: ['pos:access', 'pos:create'],
      );

      expect(role.permissions, contains('pos:access'));
      userRepo.assignRoleToUser(user.id, role.id);
    });
  });
}
