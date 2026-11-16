import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/licensing/license_service.dart';
import '../../core/providers/license_provider.dart';
import '../../core/widgets/operation_success_dialog.dart';

class LicensingScreen extends ConsumerStatefulWidget {
  const LicensingScreen({super.key});

  @override
  ConsumerState<LicensingScreen> createState() => _LicensingScreenState();
}

class _LicensingScreenState extends ConsumerState<LicensingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LicenseService _licenseService = LicenseService();

  late String _hardwareId;
  final TextEditingController _activationKeyController = TextEditingController();

  static const String developerPhone = '781235491';
  static const String developerInstagram = '@mohlabss';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _hardwareId = _licenseService.getMachineHardwareId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _activationKeyController.dispose();
    super.dispose();
  }

  void _copyHardwareId() {
    Clipboard.setData(ClipboardData(text: _hardwareId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ كود بصمة الجهاز إلى الحافظة بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _openWhatsApp() {
    final message = Uri.encodeComponent(
      'مرحباً، أود تفعيل أو تجديد ترخيص نظام ALFA SOFT.\n'
      'كود بصمة الجهاز: $_hardwareId\n'
      'يرجى تزويدي بمفتاح أو ملف الترخيص المعتمد.',
    );
    final url = 'https://wa.me/967$developerPhone?text=$message';

    if (Platform.isWindows) {
      try {
        Process.run('cmd', ['/c', 'start', '', url]);
      } catch (_) {}
    }

    _copyHardwareId();
  }

  Future<void> _handleFileImport() async {
    try {
      final script = '''
      Add-Type -AssemblyName System.Windows.Forms
      \$dialog = New-Object System.Windows.Forms.OpenFileDialog
      \$dialog.Filter = "ملف ترخيص الفا سوفت (*.alfalic)|*.alfalic|جميع الملفات (*.*)|*.*"
      \$dialog.Title = "اختر ملف ترخيص برنامج ALFA SOFT"
      if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Output \$dialog.FileName
      }
      ''';

      final res = Process.runSync('powershell', ['-NoProfile', '-Command', script]);
      if (res.exitCode == 0) {
        final path = (res.stdout as String).trim();
        if (path.isNotEmpty) {
          final file = File(path);
          if (file.existsSync()) {
            final content = file.readAsStringSync().trim();
            _activationKeyController.text = content;
            await _handleActivate();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل استيراد الملف: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _handleActivate() async {
    final key = _activationKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال مفتاح الترخيص أو استيراد ملف الترخيص أولاً')),
      );
      return;
    }

    try {
      final info = await ref.read(licenseInfoProvider.notifier).activate(key);

      if (!mounted) return;

      if (info.isValid) {
        OperationSuccessDialog.show(
          context: context,
          title: 'تم تنشيط وترخيص النظام بنجاح',
          message: 'تم التحقق من الترخيص الرقمي وتثبيته على هذا الجهاز بنجاح.\nالمنشأة: ${info.licenseeName} (${info.tier.labelAr})',
          referenceCode: info.planType,
          amountText: info.isLifetime ? 'دائم مدى الحياة' : '${info.expiresAt?.toIso8601String().substring(0, 10)}',
        );
        _activationKeyController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(info.validationError ?? 'فشل التنشيط: مفتاح الترخيص غير مطابق لهذا الجهاز'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التحقق: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز تراخيص النظام — Licensing Center'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.verified_user_rounded), text: 'بيانات وحالة الترخيص الحالي (Active License)'),
            Tab(icon: Icon(Icons.featured_play_list_rounded), text: 'باقات النظام والميزات (Tiers Matrix)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveLicenseTab(context),
          _buildTiersMatrixTab(context),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: ACTIVE LICENSE
  // -------------------------------------------------------------
  Widget _buildActiveLicenseTab(BuildContext context) {
    final theme = Theme.of(context);
    final lic = ref.watch(licenseInfoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hardware ID Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.brandAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.fingerprint_rounded, color: AppColors.brandAccent, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('معرّف البصمة الرقمية لهذا الجهاز (Hardware ID):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 4),
                            SelectableText(
                              _hardwareId,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, fontFamily: 'monospace', letterSpacing: 2),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _copyHardwareId,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('نسخ البصمة'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _openWhatsApp,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('طلب ترخيص بالواتساب'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('لطلب الترخيص والتفعيل تواصل مع المطور: $developerPhone | إنستغرام: $developerInstagram',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // License Details Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        lic.isValid
                            ? (lic.isExpired ? Icons.warning_rounded : Icons.check_circle_rounded)
                            : Icons.error_outline_rounded,
                        color: lic.isValid
                            ? (lic.isExpired ? Colors.orange : AppColors.success)
                            : AppColors.error,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        lic.isValid
                            ? (lic.isExpired ? 'الترخيص منتهي الصلاحية (وضع الأرشفة والمطالعة)' : 'الترخيص نشط ومفعل رسمياً')
                            : 'النظام غير مرخص (مطلوب تفعيل الترخيص)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: lic.isValid
                              ? (lic.isExpired ? Colors.orange.shade800 : AppColors.success)
                              : AppColors.error,
                        ),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(lic.tier.labelAr, style: const TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: AppColors.brandAccent.withValues(alpha: 0.15),
                        side: BorderSide.none,
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _infoRow('الجهة المرخصة:', lic.licenseeName),
                  _infoRow('الرقم الضريبي للمنشأة:', lic.taxNumber.isEmpty ? 'غير مسجل' : lic.taxNumber),
                  _infoRow('خطة الترخيص:', lic.isLifetime ? 'ترخيص دائم مدى الحياة (Perpetual Lifetime)' : 'اشتراك محدد المدة (${lic.planType})'),
                  _infoRow('تاريخ الإصدار:', DateFormat('yyyy-MM-dd').format(lic.issuedAt)),
                  _infoRow(
                    'تاريخ الانتهاء:',
                    lic.isLifetime
                        ? 'دائم مدى الحياة'
                        : '${lic.expiresAt?.toIso8601String().substring(0, 10)} (${lic.remainingDays ?? 0} يوم متبقي)',
                  ),
                  _infoRow('الحد الأقصى للفروع المصرحة:', '${lic.maxBranches} فرع'),
                  _infoRow('الحد الأقصى لنقاط البيع (POS):', '${lic.maxTerminals} نقطة بيع'),
                  if (lic.validationError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lic.validationError!,
                              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Activation Box
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تنشيط أو تجديد مفتاح ترخيص جديد',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('الصق رمز الترخيص المعتمد أو استورد ملف الترخيص (.alfalic):'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _activationKeyController,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'الصق مفتاح الترخيص هنا...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _handleFileImport,
                        icon: const Icon(Icons.file_open_rounded),
                        label: const Text('استيراد ملف الترخيص (.alfalic)'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _handleActivate,
                        icon: const Icon(Icons.vpn_key_rounded),
                        label: const Text('تنشيط وتحقق فوري من المفتاح'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: TIERS MATRIX
  // -------------------------------------------------------------
  Widget _buildTiersMatrixTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('الميزة / المحددات', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الأساسية (Starter)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المتقدمة (Pro)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المؤسسية (Enterprise)', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: const [
              DataRow(cells: [
                DataCell(Text('عدد الفروع المسموحة')),
                DataCell(Text('1 فرع')),
                DataCell(Text('3 فروع')),
                DataCell(Text('فروع غير محدودة (99)')),
              ]),
              DataRow(cells: [
                DataCell(Text('نقاط البيع المتصلة (POS)')),
                DataCell(Text('2 نقاط بيع')),
                DataCell(Text('5 نقاط بيع')),
                DataCell(Text('غير محدود (99)')),
              ]),
              DataRow(cells: [
                DataCell(Text('شجرة الحسابات والقيود المحاسبية')),
                DataCell(Icon(Icons.check, color: AppColors.success)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
              ]),
              DataRow(cells: [
                DataCell(Text('الربط والمزامنة الشبكية (LAN Sync)')),
                DataCell(Icon(Icons.close, color: Colors.grey)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
              ]),
              DataRow(cells: [
                DataCell(Text('مركز استيراد وترحيل البيانات')),
                DataCell(Icon(Icons.close, color: Colors.grey)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
                DataCell(Icon(Icons.check, color: AppColors.success)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
