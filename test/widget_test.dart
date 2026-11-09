import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alfa_soft/main.dart';
import 'package:alfa_soft/core/providers/app_state_provider.dart';
import 'package:alfa_soft/core/providers/auth_provider.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/data/repositories/user_repository.dart';

void main() {
  testWidgets('ALFA SOFT app boots into FirstRunWizard when empty', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dbService = DatabaseService.inMemory();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(dbService),
        ],
        child: const AlfaSoftApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ALFA SOFT — معالج التهيئة الأولية'), findsOneWidget);
    expect(find.text('1. بيانات المنشأة التجارية'), findsOneWidget);

    dbService.dispose();
  });

  testWidgets('ALFA SOFT app prompts for LoginScreen on launch when company exists', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dbService = DatabaseService.inMemory();

    // Seed company & user
    dbService.execute('''
      INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code, is_active)
      VALUES ('comp_1', 'شركة ألفا للتجارة', 'شركة ألفا للتجارة', '300012345600003', 'SAR', 1);
    ''');
    dbService.execute('''
      INSERT INTO branches (id, company_id, code, name, is_main, is_active)
      VALUES ('br_1', 'comp_1', 'BR01', 'الفرع الرئيسي', 1, 1);
    ''');

    final userRepo = UserRepository(dbService);
    userRepo.createUser(
      companyId: 'comp_1',
      username: 'admin',
      password: 'Admin@2026',
      fullName: 'المدير العام',
      isAdmin: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(dbService),
        ],
        child: const AlfaSoftApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Login Screen is displayed
    expect(find.text('ALFA SOFT'), findsOneWidget);
    expect(find.text('منظومة إدارة الموارد المؤسسية الذكية — ERP'), findsOneWidget);
    expect(find.text('تسجيل الدخول للنظام'), findsOneWidget);
    expect(find.text('حساب المسؤول الافتراضي:'), findsOneWidget);

    dbService.dispose();
  });

  testWidgets('ALFA SOFT allows login and displays MainShell with Users & Settings navigation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dbService = DatabaseService.inMemory();

    dbService.execute('''
      INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code, is_active)
      VALUES ('comp_1', 'شركة ألفا للتجارة', 'شركة ألفا للتجارة', '300012345600003', 'SAR', 1);
    ''');
    dbService.execute('''
      INSERT INTO branches (id, company_id, code, name, is_main, is_active)
      VALUES ('br_1', 'comp_1', 'BR01', 'الفرع الرئيسي', 1, 1);
    ''');

    final userRepo = UserRepository(dbService);
    final user = userRepo.createUser(
      companyId: 'comp_1',
      username: 'admin',
      password: 'Admin@2026',
      fullName: 'المدير العام',
      isAdmin: true,
    );

    final container = ProviderContainer(
      overrides: [
        databaseServiceProvider.overrideWithValue(dbService),
      ],
    );
    addTearDown(container.dispose);

    // Set logged in user directly in session
    container.read(currentUserProvider.notifier).setUser(user);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AlfaSoftApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify MainShell is rendered with Users and Settings in Navigation Rail
    expect(find.text('المستخدمون والصلاحيات'), findsOneWidget);
    expect(find.text('إعدادات النظام الشاملة'), findsOneWidget);
    expect(find.text('المدير العام'), findsOneWidget);

    dbService.dispose();
  });
}
