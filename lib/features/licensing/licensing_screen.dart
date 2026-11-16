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

  // Activation inputs
  final TextEditingController _activationKeyController = TextEditingController();

  // Developer Generator inputs
  final TextEditingController _devClientNameCtrl = TextEditingController(text: 'شركة التجارة والحلول الحديثة');
  final TextEditingController _devHwidCtrl = TextEditingController();
  final TextEditingController _devTaxCtrl = TextEditingController(text: '310987654300003');
  final TextEditingController _devDaysCtrl = TextEditingController(text: '365');
  LicenseTier _devSelectedTier = LicenseTier.enterprise;
  String _devPlanType = 'LIFETIME'; // 'LIFETIME', 'ANNUAL', 'SEMI_ANNUAL', 'MONTHLY', 'CUSTOM'
  String? _generatedLicenseOutput;
  bool _isGenerating = false;

  static const String developerPhone = '781235491';
  static const String developerInstagram = '@mohlabss';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _hardwareId = _licenseService.getMachineHardwareId();
    _devHwidCtrl.text = _hardwareId;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _activationKeyController.dispose();
    _devClientNameCtrl.dispose();
    _devHwidCtrl.dispose();
    _devTaxCtrl.dispose();
    _devDaysCtrl.dispose();
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
            setState(() {
              _activationKeyController.text = content;
            });
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
        const SnackBar(content: Text('يرجى إدخال أو إلصاق مفتاح الترخيص أولاً'), backgroundColor: AppColors.error),
      );
      return;
    }

    final info = await ref.read(licenseInfoProvider.notifier).activate(key);

    if (mounted) {
      if (info.isValid) {
        _activationKeyController.clear();
        OperationSuccessDialog.show(
          context: context,
          title: 'تم تنشيط وحفظ الترخيص بنجاح!',
          message: 'تم تفعيل الترخيص ومطابقة التوقيع وبصمة الجهاز بنجاح.\nالمنشأة: ${info.licenseeName}\nالخطة: ${info.isLifetime ? "دائم مدى الحياة" : "صالح حتى ${info.expiresAt?.toIso8601String().substring(0, 10)}"}',
          referenceCode: info.hardwareId,
          amountText: info.tier.labelAr,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التنشيط: ${info.validationError}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDeveloperGenerate() async {
    setState(() => _isGenerating = true);

    try {
      DateTime? expiresAt;
      if (_devPlanType == 'ANNUAL') {
        expiresAt = DateTime.now().add(const Duration(days: 365));
      } else if (_devPlanType == 'SEMI_ANNUAL') {
        expiresAt = DateTime.now().add(const Duration(days: 180));
      } else if (_devPlanType == 'MONTHLY') {
        expiresAt = DateTime.now().add(const Duration(days: 30));
      } else if (_devPlanType == 'CUSTOM') {
        final days = int.tryParse(_devDaysCtrl.text.trim()) ?? 30;
        expiresAt = DateTime.now().add(Duration(days: days));
      }

      final licenseString = await _licenseService.issueLicense(
        licenseeName: _devClientNameCtrl.text.trim(),
        hardwareId: _devHwidCtrl.text.trim(),
        taxNumber: _devTaxCtrl.text.trim(),
        tier: _devSelectedTier,
        planType: _devPlanType,
        expiresAt: expiresAt,
        notes: 'ترخيص نظام ألفا سوفت صادر من بوابة المطور',
      );

      // Also write file to Desktop / root
      final safeName = _devClientNameCtrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final fileName = 'alfa_license_${safeName}_${_devHwidCtrl.text.trim().substring(_devHwidCtrl.text.trim().length - 4)}.alfalic';
      final file = File(fileName);
      file.writeAsStringSync(licenseString);

      setState(() {
        _generatedLicenseOutput = licenseString;
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم توليد وحفظ ملف الترخيص: $fileName بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التوليد: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة التراخيص وبوابة المطور — Cryptographic Licensing Center'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.verified_user_rounded), text: 'حالة الترخيص الحالي (Active License)'),
            Tab(icon: Icon(Icons.key_rounded), text: 'بوابة المطور ومولد المفاتيح (Key Generator)'),
            Tab(icon: Icon(Icons.featured_play_list_rounded), text: 'مصفوفة الباقات والميزات (Tiers Matrix)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveLicenseTab(context),
          _buildKeyGeneratorTab(context),
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
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('الموديلات البرمجية المفعلة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (lic.modules.isEmpty ? ['لا توجد'] : lic.modules).map((m) {
                      return Chip(
                        avatar: const Icon(Icons.check, size: 16, color: AppColors.success),
                        label: Text(m, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      );
                    }).toList(),
                  ),
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
                  const Text('الصق رمز الترخيص المشفر المعتمد (ALFALIC-...) أو استورد ملف الترخيص (.alfalic):'),
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
  // TAB 2: DEVELOPER KEY GENERATOR
  // -------------------------------------------------------------
  Widget _buildKeyGeneratorTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.brandAccent),
            ),
            child: const Row(
              children: [
                Icon(Icons.security_rounded, color: AppColors.brandAccent),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'بوابة المطور لإصدار تراخيص مشفرة خوارزمياً بنواة Ed25519 وموقعة رقمياً بالمفتاح الرئيسي ومقيدة بفرادة عتاد العميل للعمل 100% دون إنترنت.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _devClientNameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم المنشأة المرخصة (العميل) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _devHwidCtrl,
                    decoration: const InputDecoration(labelText: 'معرف عتاد جهاز العميل (Hardware ID) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _devTaxCtrl,
                    decoration: const InputDecoration(labelText: 'الرقم الضريبي للمنشأة *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<LicenseTier>(
                    initialValue: _devSelectedTier,
                    decoration: const InputDecoration(labelText: 'باقة الترخيص (Tier)'),
                    items: LicenseTier.values.map((t) {
                      return DropdownMenuItem(value: t, child: Text(t.labelAr));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _devSelectedTier = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _devPlanType,
                    decoration: const InputDecoration(labelText: 'نوع ومدة الاشتراك المصرح به'),
                    items: const [
                      DropdownMenuItem(value: 'LIFETIME', child: Text('دائم مدى الحياة (Perpetual Lifetime)')),
                      DropdownMenuItem(value: 'ANNUAL', child: Text('اشتراك سنوي (365 يوم)')),
                      DropdownMenuItem(value: 'SEMI_ANNUAL', child: Text('اشتراك نصف سنوي (180 يوم)')),
                      DropdownMenuItem(value: 'MONTHLY', child: Text('اشتراك شهري (30 يوم)')),
                      DropdownMenuItem(value: 'CUSTOM', child: Text('عدد أيام مخصص')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _devPlanType = val);
                    },
                  ),
                  if (_devPlanType == 'CUSTOM') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _devDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'عدد الأيام المصرح بها *'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _handleDeveloperGenerate,
                    icon: _isGenerating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.verified_rounded),
                    label: const Text('توليد وتوقيع حزمة الترخيص إلكترونياً (Ed25519) وتصدير الملف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_generatedLicenseOutput != null) ...[
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF0F172A),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('حزمة الترخيص المولدة والموقعة (Ready to Deliver):',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                _activationKeyController.text = _generatedLicenseOutput!;
                                _tabController.animateTo(0);
                                _handleActivate();
                              },
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                              label: const Text('تفعيل مباشر بهذا الجهاز'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPrimary),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.white),
                              tooltip: 'نسخ الكود',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _generatedLicenseOutput!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم نسخ كود الترخيص بنجاح')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _generatedLicenseOutput!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: TIERS MATRIX
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
