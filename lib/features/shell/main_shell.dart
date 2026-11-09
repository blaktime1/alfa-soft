import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../pos/pos_screen.dart';
import '../inventory/products_screen.dart';
import '../inventory/stock_transfers_screen.dart';
import '../purchases/purchases_screen.dart';
import '../partners/partners_screen.dart';
import '../users/users_screen.dart';
import '../accounting/accounting_screen.dart';
import '../reports/reports_screen.dart';
import '../sync/sync_screen.dart';
import '../enterprise/enterprise_screen.dart';
import '../settings/settings_screen.dart';

import 'package:window_manager/window_manager.dart';
import 'app_exit_backup_dialog.dart';

enum ShellNavSection {
  dashboard,
  pos,
  inventory,
  purchases,
  accounting,
  customers,
  reports,
  users,
  enterprise,
  sync,
  settings,
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WindowListener {
  ShellNavSection _activeSection = ShellNavSection.dashboard;
  String _companyName = 'ALFA SOFT';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadCompanyInfo();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose && mounted) {
        AppExitBackupDialog.show(context);
      }
    } catch (_) {
      if (mounted) AppExitBackupDialog.show(context);
    }
  }

  void _loadCompanyInfo() {
    try {
      final db = ref.read(databaseServiceProvider);
      final compResult = db.select('SELECT trade_name FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        setState(() {
          _companyName = compResult.first['trade_name'] as String;
        });
      }
    } catch (_) {}
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightBgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightBorderSubtle),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.danger),
            SizedBox(width: 10),
            Text('تسجيل الخروج من المنظومة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'هل ترغب فعلاً في تسجيل الخروج والعودة لشاشة الدخول الرئيسية؟',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.lightTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(currentUserProvider.notifier).logout();
            },
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final currentLocale = ref.watch(localeProvider);
    final isArabic = currentLocale.languageCode == 'ar';
    final currentUser = ref.watch(currentUserProvider);

    // If POS is selected, open dedicated fullscreen checkout mode
    if (_activeSection == ShellNavSection.pos) {
      return PosScreen(
        onExit: () => setState(() => _activeSection = ShellNavSection.dashboard),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.lightBgCanvas,
      body: Row(
        children: [
          // Collapsible Navigation Drawer
          NavigationRail(
            extended: true,
            minExtendedWidth: 230,
            backgroundColor: AppColors.lightBgSurface,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.corporate_fare_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ALFA SOFT',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.brandPrimary),
                      ),
                      Text(
                        _companyName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.lightTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            trailing: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => AppExitBackupDialog.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.brandGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_rounded, size: 14, color: AppColors.brandGoldDark),
                          SizedBox(width: 6),
                          Text(
                            'إغلاق ونسخ آمن',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandGoldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _confirmLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded, size: 14, color: AppColors.dangerText),
                          SizedBox(width: 6),
                          Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.dangerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            selectedIndex: _activeSection.index,
            onDestinationSelected: (index) {
              setState(() {
                _activeSection = ShellNavSection.values[index];
              });
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_rounded),
                label: Text('لوحة التحكم'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.point_of_sale_rounded),
                label: Text('شاشة الكاشير (POS)'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_rounded),
                label: Text('المخزون والمستودعات'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.shopping_bag_rounded),
                label: Text('المشتريات والتوريد'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_balance_rounded),
                label: Text('المحاسبة والقيود'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_alt_rounded),
                label: Text('العملاء والموردون'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.print_rounded),
                label: Text('التقارير والمستندات'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.manage_accounts_rounded),
                label: Text('المستخدمون والصلاحيات'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.business_center_rounded),
                label: Text('الجناح المؤسسي والرواتب'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.sync_rounded),
                label: Text('المزامنة والشبكة'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_rounded),
                label: Text('إعدادات النظام الشاملة'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, color: AppColors.lightBorderSubtle),

          // Main Screen Content Area
          Expanded(
            child: Column(
              children: [
                // Top Application Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.lightBgSurface,
                    border: Border(bottom: BorderSide(color: AppColors.lightBorderSubtle)),
                  ),
                  child: Row(
                    children: [
                      // Active Branch Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.lightBorderSubtle),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_rounded, size: 16, color: AppColors.brandAccent),
                            SizedBox(width: 6),
                            Text(
                              'الفرع الرئيسي',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Offline-Ready Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.successText),
                            SizedBox(width: 6),
                            Text(
                              'محلي جاهز',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.successText,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Theme Mode Toggle
                      IconButton(
                        icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
                        tooltip: isDark ? 'التبديل إلى الوضع الفاتح' : 'التبديل إلى الوضع الداكن',
                        onPressed: () {
                          ref.read(themeModeProvider.notifier).toggleTheme();
                        },
                      ),

                      // Language Toggle
                      IconButton(
                        icon: const Icon(Icons.language_rounded, size: 20),
                        tooltip: isArabic ? 'English' : 'العربية',
                        onPressed: () {
                          ref.read(localeProvider.notifier).toggleLocale();
                        },
                      ),

                      // User Profile Info Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        constraints: const BoxConstraints(maxWidth: 140),
                        decoration: BoxDecoration(
                          color: AppColors.lightBgSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.lightBorderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.brandPrimary,
                              child: Text(
                                (currentUser?.username.isNotEmpty == true)
                                    ? currentUser!.username.substring(0, 1).toUpperCase()
                                    : 'A',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                currentUser?.fullName ?? 'المدير العام',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.lightTextPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Logout Top Button
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: AppColors.lightTextSecondary, size: 20),
                        tooltip: 'تسجيل الخروج',
                        onPressed: _confirmLogout,
                      ),

                      // Exit & Auto-Backup System Button
                      IconButton(
                        icon: const Icon(Icons.power_settings_new_rounded, color: AppColors.danger, size: 20),
                        tooltip: 'إغلاق المنظومة والنسخ الاحتياطي الآمن',
                        onPressed: () => AppExitBackupDialog.show(context),
                      ),
                    ],
                  ),
                ),

                // Body Page Router
                Expanded(
                  child: _buildActivePage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePage() {
    switch (_activeSection) {
      case ShellNavSection.dashboard:
        return DashboardScreen(
          onOpenPos: () => setState(() => _activeSection = ShellNavSection.pos),
        );
      case ShellNavSection.pos:
        return const SizedBox.shrink(); // Handled in build
      case ShellNavSection.inventory:
        return const _InventoryContainer();
      case ShellNavSection.purchases:
        return const PurchasesScreen();
      case ShellNavSection.accounting:
        return const AccountingScreen();
      case ShellNavSection.customers:
        return const PartnersScreen();
      case ShellNavSection.reports:
        return const ReportsScreen();
      case ShellNavSection.users:
        return const UsersScreen();
      case ShellNavSection.enterprise:
        return const EnterpriseScreen();
      case ShellNavSection.sync:
        return const SyncScreen();
      case ShellNavSection.settings:
        return const SettingsScreen();
    }
  }
}

class _InventoryContainer extends StatefulWidget {
  const _InventoryContainer();

  @override
  State<_InventoryContainer> createState() => _InventoryContainerState();
}

class _InventoryContainerState extends State<_InventoryContainer> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.lightBgSurface,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.brandAccent,
            labelColor: AppColors.brandPrimary,
            unselectedLabelColor: AppColors.lightTextSecondary,
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_rounded), text: 'كتالوج الأصناف والأسعار'),
              Tab(icon: Icon(Icons.swap_horiz_rounded), text: 'التحويلات والتسويات المخزنية'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              ProductsScreen(),
              StockTransfersScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
