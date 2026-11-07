import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../pos/pos_screen.dart';
import '../inventory/products_screen.dart';
import '../inventory/stock_transfers_screen.dart';
import '../purchases/purchases_screen.dart';
import '../partners/partners_screen.dart';
import '../organization/organization_screen.dart';
import '../users/users_screen.dart';
import '../accounting/accounting_screen.dart';
import '../reports/reports_screen.dart';
import '../sync/sync_screen.dart';
import '../migration/migration_screen.dart';
import '../licensing/licensing_screen.dart';
import '../enterprise/enterprise_screen.dart';

enum ShellNavSection {
  dashboard,
  pos,
  inventory,
  purchases,
  accounting,
  enterprise,
  reports,
  sync,
  customers,
  settings,
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  ShellNavSection _activeSection = ShellNavSection.dashboard;
  String _companyName = 'ALFA SOFT';

  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
  }

  void _loadCompanyInfo() {
    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT trade_name FROM companies LIMIT 1');
    if (compResult.isNotEmpty) {
      setState(() {
        _companyName = compResult.first['trade_name'] as String;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final currentLocale = ref.watch(localeProvider);
    final isArabic = currentLocale.languageCode == 'ar';

    // If POS is selected, open dedicated fullscreen checkout mode
    if (_activeSection == ShellNavSection.pos) {
      return PosScreen(
        onExit: () => setState(() => _activeSection = ShellNavSection.dashboard),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Collapsible Navigation Drawer
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            backgroundColor: theme.colorScheme.surface,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.blur_on_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ALFA SOFT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        _companyName,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
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
                icon: Icon(Icons.business_center_rounded),
                label: Text('الجناح المؤسسي والرواتب'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.print_rounded),
                label: Text('التقارير والمستندات'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.sync_rounded),
                label: Text('المزامنة والشبكة'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_alt_rounded),
                label: Text('العملاء والموردون'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_rounded),
                label: Text('إعدادات النظام'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),

          // Main Screen Content Area
          Expanded(
            child: Column(
              children: [
                // Top Application Bar
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(bottom: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    children: [
                      // Active Branch Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.storefront_rounded, size: 16, color: AppColors.brandAccent),
                            SizedBox(width: 6),
                            Text(
                              'الفرع الرئيسي (BR01)',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandAccent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Offline-Ready Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.success),
                            SizedBox(width: 6),
                            Text(
                              'محلي جاهز (Offline Active)',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Theme Mode Toggle (Dark / Light)
                      IconButton(
                        icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                        tooltip: isDark ? 'التبديل إلى الوضع الفاتح' : 'التبديل إلى الوضع الداكن',
                        onPressed: () {
                          ref.read(themeModeProvider.notifier).toggleTheme();
                        },
                      ),

                      // Language Toggle (Arabic / English)
                      TextButton.icon(
                        icon: const Icon(Icons.language_rounded, size: 18),
                        label: Text(isArabic ? 'English' : 'العربية'),
                        onPressed: () {
                          ref.read(localeProvider.notifier).toggleLocale();
                        },
                      ),
                      const SizedBox(width: 8),

                      // User Profile Avatar
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.brandAccent,
                        child: Icon(Icons.person_rounded, size: 18, color: Colors.white),
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
      case ShellNavSection.enterprise:
        return const EnterpriseScreen();
      case ShellNavSection.reports:
        return const ReportsScreen();
      case ShellNavSection.sync:
        return const SyncScreen();
      case ShellNavSection.customers:
        return const PartnersScreen();
      case ShellNavSection.settings:
        return const _SettingsContainer();
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
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
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

class _SettingsContainer extends StatefulWidget {
  const _SettingsContainer();

  @override
  State<_SettingsContainer> createState() => _SettingsContainerState();
}

class _SettingsContainerState extends State<_SettingsContainer> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.business_rounded), text: 'الهيكل التنظيمي والفروع'),
              Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'المستخدمون والصلاحيات'),
              Tab(icon: Icon(Icons.upload_file_rounded), text: 'مركز استيراد وترحيل البيانات'),
              Tab(icon: Icon(Icons.verified_user_rounded), text: 'إدارة التراخيص وبوابة المطور'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              OrganizationScreen(),
              UsersScreen(),
              MigrationScreen(),
              LicensingScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
