import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alfa_soft/main.dart';
import 'package:alfa_soft/core/providers/app_state_provider.dart';
import 'package:alfa_soft/data/local/database_service.dart';

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

    // Verify FirstRunWizard is displayed
    expect(find.text('ALFA SOFT — معالج التهيئة الأولية'), findsOneWidget);
    expect(find.text('1. بيانات المنشأة التجارية'), findsOneWidget);

    dbService.dispose();
  });
}
