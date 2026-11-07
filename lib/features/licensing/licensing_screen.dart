import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/theme/app_colors.dart';
import '../../core/licensing/license_service.dart';

class LicensingScreen extends ConsumerStatefulWidget {
  const LicensingScreen({super.key});

  @override
  ConsumerState<LicensingScreen> createState() => _LicensingScreenState();
}

class _LicensingScreenState extends ConsumerState<LicensingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LicenseService _licenseService = LicenseService();

  late String _hardwareId;
  LicenseInfo? _currentLicense;

  // Activation inputs
  final TextEditingController _activationKeyController = TextEditingController();

  // Developer Generator inputs
  final TextEditingController _devClientNameCtrl = TextEditingController(text: 'شركة التجارة والحلول الحديثة');
  final TextEditingController _devHwidCtrl = TextEditingController();
  final TextEditingController _devTaxCtrl = TextEditingController(text: '310987654300003');
  LicenseTier _devSelectedTier = LicenseTier.enterprise;
  bool _devIsLifetime = true;
  String? _generatedLicenseOutput;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _hardwareId = _licenseService.getMachineHardwareId();
    _devHwidCtrl.text = _hardwareId;
    _loadDefaultTrialLicense();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _activationKeyController.dispose();
    _devClientNameCtrl.dispose();
    _devHwidCtrl.dispose();
    _devTaxCtrl.dispose();
    super.dispose();
  }

  void _loadDefaultTrialLicense() {
    setState(() {
      _currentLicense = LicenseInfo(
        licenseeName: 'شركة ألفا سوفت (نسخة تجريبية محلية)',
        hardwareId: _hardwareId,
        taxNumber: '310123456700003',
        tier: LicenseTier.enterprise,
        maxBranches: 99,
        maxTerminals: 99,
        modules: const ['POS', 'INVENTORY', 'ACCOUNTING', 'PURCHASING', 'SYNC', 'MIGRATION'],
        issuedAt: DateTime.now(),
        isLifetime: true,
        isValid: true,
      );
    });
  }

  Future<void> _handleActivate() async {
    final key = _activationKeyController.text.trim();
    if (key.isEmpty) return;

    final info = await _licenseService.validateLicense(
      rawLicensePackage: key,
      localHardwareId: _hardwareId,
    );

    setState(() {
      _currentLicense = info;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(info.isValid ? 'تم تنشيط الترخيص بنجاح!' : 'فشل التنشيط: ${info.validationError}'),
          backgroundColor: info.isValid ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleDeveloperGenerate() async {
    setState(() => _isGenerating = true);

    try {
      final keyPair = await Ed25519().newKeyPair();
      final licenseString = await _licenseService.issueLicense(
        vendorKeyPair: keyPair,
        licenseeName: _devClientNameCtrl.text.trim(),
        hardwareId: _devHwidCtrl.text.trim(),
        taxNumber: _devTaxCtrl.text.trim(),
        tier: _devSelectedTier,
        expiresAt: _devIsLifetime ? null : DateTime.now().add(const Duration(days: 365)),
      );

      setState(() {
        _generatedLicenseOutput = licenseString;
        _isGenerating = false;
      });
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
    final lic = _currentLicense;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hardware ID Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _hardwareId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ معرّف الجهاز إلى الحافظة بنجاح')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('نسخ البصمة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // License Details Card
          if (lic != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          lic.isValid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: lic.isValid ? AppColors.success : AppColors.error,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          lic.isValid ? 'الترخيص نشط ومفعل رسمياً' : 'الترخيص غير صالح أو غير مفعل',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: lic.isValid ? AppColors.success : AppColors.error,
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
                    _infoRow('الرقم الضريبي للمنشأة:', lic.taxNumber),
                    _infoRow('الحد الأقصى للفروع المصرحة:', '${lic.maxBranches} فرع'),
                    _infoRow('الحد الأقصى لنقاط البيع (POS):', '${lic.maxTerminals} نقطة بيع'),
                    _infoRow('تاريخ الإصدار:', DateFormat('yyyy-MM-dd').format(lic.issuedAt)),
                    _infoRow('نوع الاشتراك:', lic.isLifetime ? 'ترخيص دائم مدى الحياة (Perpetual Lifetime)' : 'اشتراك سنوي'),
                    const SizedBox(height: 16),
                    const Text('الموديلات البرمجية المفعلة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: lic.modules.map((m) {
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تنشيط مفتاح ترخيص جديد',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('الصق رمز الترخيص المشفر المعتمد (Base64 Package) المستلم من الشركة الموزعة:'),
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
                  ElevatedButton.icon(
                    onPressed: _handleActivate,
                    icon: const Icon(Icons.vpn_key_rounded),
                    label: const Text('تنشيط وتحقق فوري من المفتاح'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandAccent),
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
                    'أداة المطور ومزود الخدمة لإصدار تراخيص مشفرة خوارزمياً (Ed25519) ومقيدة بعتاد العميل للعمل 100% دون إنترنت.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
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
                  SwitchListTile(
                    title: const Text('ترخيص دائم مدى الحياة (Perpetual Lifetime)'),
                    subtitle: const Text('تفعيل غير مقيد بتاريخ انتهاء'),
                    value: _devIsLifetime,
                    onChanged: (val) => setState(() => _devIsLifetime = val),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _handleDeveloperGenerate,
                    icon: _isGenerating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.verified_rounded),
                    label: const Text('توليد وتوقيع حزمة الترخيص إلكترونياً (Ed25519)'),
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
              color: Colors.grey.shade900,
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
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _generatedLicenseOutput!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ كود الترخيص بنجاح')),
                            );
                          },
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
