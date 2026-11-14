import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database_service.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../data/repositories/sales_invoice_repository.dart';
import '../printing/printer_service.dart';
import '../sync/lan_sync_protocol.dart';
import '../sync/lan_sync_server.dart';
import '../sync/lan_sync_client.dart';
import '../sync/outbox_manager.dart';

/// Database service provider initialized at boot
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  throw UnimplementedError('DatabaseService must be initialized in main()');
});

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  return AccountingRepository(ref.watch(databaseServiceProvider));
});

final salesInvoiceRepositoryProvider = Provider<SalesInvoiceRepository>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final accounting = ref.watch(accountingRepositoryProvider);
  return SalesInvoiceRepository(db, accounting);
});

final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService(ref.watch(databaseServiceProvider));
});

final outboxManagerProvider = Provider<OutboxManager>((ref) {
  return OutboxManager(ref.watch(databaseServiceProvider));
});

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final outbox = ref.watch(outboxManagerProvider);
  return LanSyncService(db: db, outboxManager: outbox);
});

final lanSyncServerProvider = Provider<LanSyncServer>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final syncService = ref.watch(lanSyncServiceProvider);
  final server = LanSyncServer(db: db, syncService: syncService);
  ref.onDispose(() {
    server.stop();
  });
  return server;
});

final lanSyncClientProvider = Provider<LanSyncClient>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final outbox = ref.watch(outboxManagerProvider);
  final syncService = ref.watch(lanSyncServiceProvider);
  final client = LanSyncClient(db: db, outboxManager: outbox, syncService: syncService);
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

/// POS Interface Style Provider ('QUICK' for Touch POS vs 'STANDARD' for ERP Invoicing POS)
final posInterfaceStyleProvider = StateNotifierProvider<PosInterfaceStyleNotifier, String>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return PosInterfaceStyleNotifier(db);
});

class PosInterfaceStyleNotifier extends StateNotifier<String> {
  final DatabaseService _db;

  PosInterfaceStyleNotifier(this._db) : super('QUICK') {
    _loadFromDb();
  }

  void _loadFromDb() {
    try {
      final rows = _db.select("SELECT value FROM system_settings WHERE key = 'pos_interface_style' LIMIT 1");
      if (rows.isNotEmpty) {
        state = rows.first['value'] as String;
      }
    } catch (_) {}
  }

  void setStyle(String newStyle) {
    state = newStyle;
    try {
      _db.execute('''
        INSERT OR REPLACE INTO system_settings (key, value, updated_at)
        VALUES ('pos_interface_style', ?, datetime('now'))
      ''', [newStyle]);
    } catch (_) {}
  }
}


/// Theme Mode Provider (Light / Dark)
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light);

  void toggleTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void setTheme(ThemeMode mode) {
    state = mode;
  }
}

/// Language / Locale Provider (Arabic RTL default, English LTR option)
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('ar'));

  void toggleLocale() {
    state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
  }

  void setLocale(Locale locale) {
    state = locale;
  }
}
