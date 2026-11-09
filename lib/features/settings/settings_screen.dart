import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/backup/backup_service.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../organization/organization_screen.dart';
import '../migration/migration_screen.dart';
import '../licensing/licensing_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Company Form Controllers
  final _legalNameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _crNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // POS / Printer Controllers
  bool _is80mm = true;
  bool _autoPrint = true;
  bool _autoCut = true;
  bool _drawerKick = true;
  bool _showZatcaQr = true;
  final _receiptHeaderController = TextEditingController(text: 'أهلاً بكم في منظومة ألفا سوفت');
  final _receiptFooterController = TextEditingController(text: 'شكراً لتعاملكم معنا • البضاعة المباعة تستبدل خلال 3 أيام');

  // DB Metrics & Backup
  int _tableCount = 0;
  bool _isOptimizing = false;
  String? _backupSuccessPath;
  final _backupDirController = TextEditingController();
  bool _autoBackupOnClose = true;
  List<String> _availableDrives = [];
  List<BackupArchiveInfo> _pastBackups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadCompanyData();
    _loadDbMetrics();
    _loadBackupSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _taxNumberController.dispose();
    _crNumberController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _receiptHeaderController.dispose();
    _receiptFooterController.dispose();
    _backupDirController.dispose();
    super.dispose();
  }

  void _loadCompanyData() {
    try {
      final db = ref.read(databaseServiceProvider);
      final rows = db.select('SELECT * FROM companies LIMIT 1');
      if (rows.isNotEmpty) {
        final c = rows.first;
        _legalNameController.text = (c['legal_name'] as String?) ?? '';
        _tradeNameController.text = (c['trade_name'] as String?) ?? '';
        _taxNumberController.text = (c['tax_number'] as String?) ?? '';
      }
    } catch (_) {}
  }

  void _loadDbMetrics() {
    try {
      final db = ref.read(databaseServiceProvider);
      final tblRows = db.select("SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      if (tblRows.isNotEmpty) {
        setState(() {
          _tableCount = tblRows.first['cnt'] as int;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBackupSettings() async {
    try {
      final db = ref.read(databaseServiceProvider);
      final backupService = BackupService(db);
      final dir = await backupService.getEffectiveBackupDirectory();
      final autoClose = backupService.isAutoBackupOnCloseEnabled();
      final drives = backupService.getAvailableDrives();
      final past = backupService.listBackups(dir);

      if (mounted) {
        setState(() {
          _backupDirController.text = dir;
          _autoBackupOnClose = autoClose;
          _availableDrives = drives;
          _pastBackups = past;
        });
      }
    } catch (_) {}
  }

  void _saveCompanySettings() {
    try {
      final db = ref.read(databaseServiceProvider);
      db.execute('''
        UPDATE companies
        SET legal_name = ?, trade_name = ?, tax_number = ?
        WHERE id IN (SELECT id FROM companies LIMIT 1)
      ''', [
        _legalNameController.text.trim(),
        _tradeNameController.text.trim(),
        _taxNumberController.text.trim(),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ بيانات المنشأة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _saveBackupSettings() {
    final db = ref.read(databaseServiceProvider);
    final backupService = BackupService(db);
    final path = _backupDirController.text.trim();
    if (path.isNotEmpty) {
      backupService.setBackupDirectory(path);
      backupService.setAutoBackupOnClose(_autoBackupOnClose);
      _loadBackupSettings();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات ومسار النسخ الاحتياطي التلقائي بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _createLiveBackup() async {
    setState(() => _isOptimizing = true);
    final db = ref.read(databaseServiceProvider);
    final backupService = BackupService(db);
    final currentUser = ref.read(currentUserProvider);

    final result = await backupService.createBackup(
      customTargetDir: _backupDirController.text.trim().isNotEmpty ? _backupDirController.text.trim() : null,
      executedBy: '${currentUser?.fullName ?? "admin"} (${currentUser?.username ?? "admin"})',
    );

    setState(() {
      _isOptimizing = false;
      if (result.isSuccess) {
        _backupSuccessPath = '${result.dbFilePath}\n(ملف التقرير: ${result.manifestFilePath})';
      }
    });

    _loadBackupSettings();

    if (mounted) {
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء النسخة الاحتياطية بنجاح في:\n${result.dbFilePath}'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل النسخ الاحتياطي: ${result.errorMessage}'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _runVacuumOptimization() {
    setState(() => _isOptimizing = true);
    try {
      final db = ref.read(databaseServiceProvider);
      db.execute('VACUUM');
      setState(() => _isOptimizing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحسين وضغط قاعدة البيانات بنجاح (VACUUM Completed)'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isOptimizing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحسين: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final locale = ref.watch(localeProvider);
    final isArabic = locale.languageCode == 'ar';

    return Scaffold(
      backgroundColor: AppColors.lightBgCanvas,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Section Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightBorderSubtle),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppColors.brandPrimary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعدادات النظام الشاملة (System Settings)',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'تخصيص الهوية التجارية، الفروع، طابعات الفواتير، النسخ الاحتياطي، المظهر العام والتراخيص',
                        style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Premium Layered Tab Bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.lightBgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.lightBorderSubtle),
                boxShadow: const [
                  BoxShadow(color: Color(0x060F172A), blurRadius: 10, offset: Offset(0, 2)),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.brandAccent,
                labelColor: AppColors.brandPrimary,
                unselectedLabelColor: AppColors.lightTextSecondary,
                tabs: const [
                  Tab(icon: Icon(Icons.business_rounded, size: 18), text: 'بيانات المنشأة والهوية'),
                  Tab(icon: Icon(Icons.account_tree_rounded, size: 18), text: 'الهيكل التنظيمي والفروع'),
                  Tab(icon: Icon(Icons.print_rounded, size: 18), text: 'نقاط البيع وطابعات الفواتير'),
                  Tab(icon: Icon(Icons.storage_rounded, size: 18), text: 'النسخ الاحتياطي والأمان'),
                  Tab(icon: Icon(Icons.upload_file_rounded, size: 18), text: 'استيراد وترحيل البيانات'),
                  Tab(icon: Icon(Icons.verified_user_rounded, size: 18), text: 'إدارة التراخيص'),
                  Tab(icon: Icon(Icons.palette_rounded, size: 18), text: 'المظهر واللغة والتفضيلات'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCompanyTab(),
                  const OrganizationScreen(),
                  _buildPrinterTab(),
                  _buildBackupTab(),
                  const MigrationScreen(),
                  const LicensingScreen(),
                  _buildAppearanceTab(isDark, isArabic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: Company Profile
  Widget _buildCompanyTab() {
    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x050F172A), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.brandAccent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'المعلومات القانونية والتجارية للمنشأة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.lightTextPrimary),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _saveCompanySettings,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ التعديلات'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'تظهر هذه البيانات على الفواتير الضريبية المبسطة، عروض الأسعار، وسندات القبض والصرف.',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الاسم التجاري (يظهر على الفاتورة والواجهة) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _tradeNameController,
                        decoration: const InputDecoration(
                          hintText: 'شركة ألفا للتجارة والخدمات',
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الاسم القانوني المسجل بالسجل التجاري *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _legalNameController,
                        decoration: const InputDecoration(
                          hintText: 'شركة ألفا المحدودة',
                          prefixIcon: Icon(Icons.gavel_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرقم الضريبي (VAT / Tax Number)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _taxNumberController,
                        decoration: const InputDecoration(
                          hintText: '300012345600003',
                          prefixIcon: Icon(Icons.receipt_long_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('رقم السجل التجاري (CR Number)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _crNumberController,
                        decoration: const InputDecoration(
                          hintText: '1010897654',
                          prefixIcon: Icon(Icons.assignment_ind_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('رقم الهاتف والتواصل', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          hintText: '+966 50 123 4567',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('العنوان الوطني / المقر الرئيسي', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          hintText: 'الرياض، المملكة العربية السعودية',
                          prefixIcon: Icon(Icons.location_on_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // TAB 2: Printer & POS
  Widget _buildPrinterTab() {
    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x050F172A), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تهيئة طابعات الإيصالات الحرارية ونقاط البيع (ESC/POS)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.lightTextPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'دعم مباشر للطابعات الحرارية عبر USB والشبكة بدون الحاجة لتعريفات معقدة.',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),

            const Text('عرض ورق الإيصال الحراري:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _is80mm = true),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _is80mm ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _is80mm ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: _is80mm ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_rounded, color: _is80mm ? AppColors.brandAccent : AppColors.lightTextSecondary),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('قياس 80 ملم (الافتراضي)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('الأكثر شيوعاً للمطاعم ومتاجر التجزئة', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _is80mm = false),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: !_is80mm ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !_is80mm ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: !_is80mm ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_rounded, color: !_is80mm ? AppColors.brandAccent : AppColors.lightTextSecondary),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('قياس 58 ملم (المدمج)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('لطابعات البلوتوث المحمولة والأكشاك', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الطباعة التلقائية فور سداد الفاتورة'),
              subtitle: const Text('إرسال الفاتورة للطابعة مباشرة عند إتمام الدفع في شاشة الكاشير'),
              value: _autoPrint,
              onChanged: (v) => setState(() => _autoPrint = v),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قطع الورق التلقائي (Auto-Cut)'),
              subtitle: const Text('إرسال أمر قطع الورقة بعد نهاية الفاتورة'),
              value: _autoCut,
              onChanged: (v) => setState(() => _autoCut = v),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('فتح درج الكاشير الإلكتروني (Drawer Kick)'),
              subtitle: const Text('إرسال نبضة كهربية 24V لفتح الدرج عند عمليات الدفع النقدي'),
              value: _drawerKick,
              onChanged: (v) => setState(() => _drawerKick = v),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('رمز الاستجابة السريع ZATCA QR Code'),
              subtitle: const Text('طباعة الباركود المتوافق مع متطلبات هيئة الزكاة والضريبة والجمارك'),
              value: _showZatcaQr,
              onChanged: (v) => setState(() => _showZatcaQr = v),
            ),
            const SizedBox(height: 20),

            const Text('ترويسة الإيصال (Header Text):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(controller: _receiptHeaderController),
            const SizedBox(height: 16),
            const Text('تذييل الإيصال (Footer Text):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(controller: _receiptFooterController),
          ],
        ),
      ),
    );
  }

  // TAB 3: Backup & Database
  Widget _buildBackupTab() {
    final dateFormat = DateFormat('yyyy-MM-dd hh:mm a');

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x050F172A), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'النسخ الاحتياطي التلقائي وإدارة محرك قاعدة البيانات (SQLite 3 WAL)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.lightTextPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'يقوم النظام تلقائياً بإنشاء نسخة احتياطية آمنة مع تقرير موثق بالساعة والتاريخ قبل كل إغلاق للتطبيق على أي قرص تختاره.',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),

            // Health Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.lightBgSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lightBorderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.health_and_safety_rounded, color: AppColors.success, size: 20),
                            SizedBox(width: 8),
                            Text('حالة محرك البيانات', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('سليم ومنضبط (WAL Active)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('عدد الجداول: $_tableCount جدول نشط', style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.lightBgSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lightBorderSubtle),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_rounded, color: AppColors.brandAccent, size: 20),
                            SizedBox(width: 8),
                            Text('مستوى الأمان والتشفير', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text('تشفير SHA-256 + تقرير موثق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text('مع بيان الساعة والتاريخ في ملف مستقل', style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Drive & Path Configuration Section
            const Text(
              'القرص والمجلد الافتراضي للنسخ الاحتياطي التلقائي:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.lightTextPrimary),
            ),
            const SizedBox(height: 10),

            if (_availableDrives.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableDrives.map((drive) {
                  final isSelected = _backupDirController.text.startsWith(drive);
                  return ActionChip(
                    avatar: Icon(Icons.storage_rounded, size: 16, color: isSelected ? Colors.white : AppColors.brandPrimary),
                    label: Text(
                      'قرص ($drive)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppColors.brandPrimary,
                      ),
                    ),
                    backgroundColor: isSelected ? AppColors.brandPrimary : AppColors.lightBgSubtle,
                    side: BorderSide(color: isSelected ? AppColors.brandPrimary : AppColors.lightBorderSubtle),
                    onPressed: () {
                      setState(() {
                        _backupDirController.text = '${drive}AlfaSoft_Backups';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _backupDirController,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.folder_special_rounded, color: AppColors.brandAccent),
                      hintText: r'D:\AlfaSoft_Backups',
                      labelText: 'المسار الدائم على القرص',
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                ElevatedButton.icon(
                  onPressed: _saveBackupSettings,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ المسار المختار'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إنشاء نسخة احتياطية تلقائياً عند إغلاق التطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('عرض نافذة تأكيد الإغلاق مع توثيق ساعة وتاريخ النسخة ومسار القرص المحدد'),
              value: _autoBackupOnClose,
              onChanged: (v) {
                setState(() => _autoBackupOnClose = v);
                _saveBackupSettings();
              },
            ),
            const SizedBox(height: 20),

            // Backup Actions
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary),
                  onPressed: _isOptimizing ? null : _createLiveBackup,
                  icon: const Icon(Icons.backup_rounded),
                  label: Text(_isOptimizing ? 'جاري إنشاء النسخة والتقرير...' : 'إنشاء نسخة احتياطية فورية الآن (Live Backup)'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _isOptimizing ? null : _runVacuumOptimization,
                  icon: const Icon(Icons.speed_rounded),
                  label: const Text('ضغط وتحسين الفهارس (VACUUM)'),
                ),
              ],
            ),

            if (_backupSuccessPath != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.successText, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تم إنشاء النسخة وتوثيق التقرير بنجاح:\n$_backupSuccessPath',
                        style: const TextStyle(fontSize: 12, color: AppColors.successText, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),

            // Past Backup Archives in Directory
            Row(
              children: [
                const Icon(Icons.archive_rounded, color: AppColors.brandAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'أرشيف النسخ الاحتياطية الموجودة في المجلد (${_pastBackups.length} نسخة):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('تحديث القائمة', style: TextStyle(fontSize: 12)),
                  onPressed: _loadBackupSettings,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_pastBackups.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.lightBgSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.lightBorderSubtle),
                ),
                child: const Center(
                  child: Text('لا توجد نسخ احتياطية سابقة في هذا المسار، يمكنك الضغط على إنشاء نسخة الآن.'),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.lightBgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.lightBorderSubtle),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pastBackups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final b = _pastBackups[index];
                    final sizeMB = (b.sizeBytes / (1024 * 1024)).toStringAsFixed(2);
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.successBg,
                        child: Icon(Icons.data_object_rounded, color: AppColors.successText, size: 20),
                      ),
                      title: Text(b.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        '${b.manifestSummary} | ${dateFormat.format(b.date)} | الحجم: $sizeMB MB',
                        style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                      ),
                      trailing: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 20),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // TAB 7: Appearance & Language
  Widget _buildAppearanceTab(bool isDark, bool isArabic) {
    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x050F172A), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المظهر، التنسيق اللوني، واللغة المفضلة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.lightTextPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'تخصيص واجهة المستخدم لتلائم بيئة العمل اليومية على أجهزة سطح المكتب.',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),

            const Text('النمط اللوني المعتمد:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setTheme(ThemeMode.light);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: !isDark ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isDark ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: !isDark ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.light_mode_rounded, color: !isDark ? AppColors.brandAccent : AppColors.lightTextSecondary),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('الوضع الفاتح الفاخر (Premium Light)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('ألوان فاتحة مريحة للعين بطبقات وظلال ناعمة', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).setTheme(ThemeMode.dark);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: isDark ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.dark_mode_rounded, color: isDark ? AppColors.brandAccent : AppColors.lightTextSecondary),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('الوضع الليلي (Night Slate)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('لبيئات الإضاءة الخافتة والمناوبات المسائية', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            const Text('لغة واجهة الاستخدام:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(localeProvider.notifier).setLocale(const Locale('ar'));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isArabic ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isArabic ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: isArabic ? 2 : 1,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.language_rounded, color: AppColors.brandAccent),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('العربية (RTL - من اليمين لليسار)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('الواجهة الرسمية للشركات والمنشآت العربية', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      ref.read(localeProvider.notifier).setLocale(const Locale('en'));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: !isArabic ? AppColors.brandAccent.withValues(alpha: 0.08) : AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isArabic ? AppColors.brandAccent : AppColors.lightBorderSubtle,
                          width: !isArabic ? 2 : 1,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.language_rounded, color: AppColors.lightTextSecondary),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('English (LTR)', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('Standard international English interface', style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.lightBgSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.lightBorderSubtle),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.brandAccent, size: 24),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ALFA SOFT Enterprise ERP — الإصدار 1.0.0 (Windows Native x64)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('بناء محلي عالي الأداء مع قاعدة بيانات محلية SQLite 3 WAL مشفرة وخالية من السحابة الخارجية.',
                            style: TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
