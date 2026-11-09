import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/providers/app_state_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/theme/app_theme.dart';
import 'data/local/database_service.dart';
import 'features/auth/login_screen.dart';
import 'features/setup/first_run_wizard.dart';
import 'features/shell/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Window Configuration
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1024, 700),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: 'ALFA SOFT — Enterprise Resource Planning',
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {
      // Ignored in test / headless runs
    }
  }

  // Database Initialization (SQLite 3 WAL)
  late final DatabaseService dbService;
  try {
    final appDir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data'));
    if (!dataDir.existsSync()) {
      dataDir.createSync(recursive: true);
    }
    final dbPath = p.join(dataDir.path, 'alfa_soft.db');
    dbService = DatabaseService.openFile(dbPath);
  } catch (_) {
    // Fallback to in-memory if disk access restricted or in test harness
    dbService = DatabaseService.inMemory();
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(dbService),
      ],
      child: const AlfaSoftApp(),
    ),
  );
}

class AlfaSoftApp extends ConsumerWidget {
  const AlfaSoftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'ALFA SOFT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppRootDecider(),
    );
  }
}

class _AppRootDecider extends ConsumerStatefulWidget {
  const _AppRootDecider();

  @override
  ConsumerState<_AppRootDecider> createState() => _AppRootDeciderState();
}

class _AppRootDeciderState extends ConsumerState<_AppRootDecider> {
  bool _hasCompany = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkSetupState();
  }

  void _checkSetupState() {
    final db = ref.read(databaseServiceProvider);
    try {
      final result = db.select('SELECT COUNT(*) as cnt FROM companies');
      final count = result.first['cnt'] as int;
      setState(() {
        _hasCompany = count > 0;
        _isChecking = false;
      });
    } catch (_) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasCompany) {
      return FirstRunWizard(
        onCompleted: () {
          setState(() {
            _hasCompany = true;
          });
        },
      );
    }

    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const LoginScreen();
    }

    return const MainShell();
  }
}
