import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../pos/pos_screen.dart';

enum ShellNavSection {
  dashboard,
  pos,
  inventory,
  accounting,
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.blur_on_rounded, color: Colors.white, size: 24),
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
                icon: Icon(Icons.account_balance_rounded),
                label: Text('المحاسبة والقيود'),
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
        return _PlaceholderSection(
          title: 'المخزون والمستودعات',
          icon: Icons.inventory_2_rounded,
          description: 'بطاقات الأصناف، حركات الوارد والمنصرف، الجرد الفعلي، والتكلفة المتوسطة / FIFO',
        );
      case ShellNavSection.accounting:
        return _PlaceholderSection(
          title: 'المحاسبة العامة وشجرة الحسابات',
          icon: Icons.account_balance_rounded,
          description: 'دليل الحسابات، قيود اليومية الآلية، موازين المراجعة، وقائمة الدخل',
        );
      case ShellNavSection.customers:
        return _PlaceholderSection(
          title: 'إدارة العملاء والموردين',
          icon: Icons.people_alt_rounded,
          description: 'سجلات العملاء، حدود الائتمان، كشوفات الحساب، ومتابعة المديونيات',
        );
      case ShellNavSection.settings:
        return _PlaceholderSection(
          title: 'إعدادات النظام والتراخيص',
          icon: Icons.settings_rounded,
          description: 'تراخيص Ed25519، إعدادات الطابعات الحرارية، والنسخ الاحتياطي المشفر',
        );
    }
  }
}

class _PlaceholderSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const _PlaceholderSection({
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: AppColors.brandAccent),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
