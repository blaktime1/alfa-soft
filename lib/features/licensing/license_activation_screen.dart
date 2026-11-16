import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/license_provider.dart';
import '../../core/widgets/operation_success_dialog.dart';

class LicenseActivationScreen extends ConsumerStatefulWidget {
  final VoidCallback onActivated;

  const LicenseActivationScreen({
    super.key,
    required this.onActivated,
  });

  @override
  ConsumerState<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends ConsumerState<LicenseActivationScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _filePathController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  static const String developerPhone = '781235491';
  static const String developerInstagram = '@mohlabss';

  @override
  void dispose() {
    _keyController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  void _copyHardwareId(String hwid) {
    Clipboard.setData(ClipboardData(text: hwid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ كود بصمة الجهاز إلى الحافظة بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _openWhatsApp(String hwid) {
    final message = Uri.encodeComponent(
      'مرحباً، أود تفعيل ترخيص نظام ALFA SOFT.\n'
      'كود بصمة هذا الجهاز: $hwid\n'
      'يرجى تزويدي بمفتاح أو ملف الترخيص المعتمد.',
    );
    final url = 'https://wa.me/967$developerPhone?text=$message';

    if (Platform.isWindows) {
      try {
        Process.run('cmd', ['/c', 'start', '', url]);
      } catch (_) {}
    }

    _copyHardwareId(hwid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ كود الجهاز وجاري توجيهك إلى واتساب المطور...'),
        backgroundColor: AppColors.brandPrimary,
      ),
    );
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
              _filePathController.text = path;
              _keyController.text = content;
              _errorMessage = null;
            });
            _processActivation(content);
          }
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'فشل استيراد الملف: $e');
    }
  }

  Future<void> _processActivation(String rawPackage) async {
    final key = rawPackage.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كود الترخيص أو استيراد ملف الترخيص (.alfalic)');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final info = await ref.read(licenseInfoProvider.notifier).activate(key);

      if (!mounted) return;

      if (info.isValid) {
        await OperationSuccessDialog.show(
          context: context,
          title: 'تم تنشيط وترخيص النظام بنجاح',
          message: 'تم التحقق من الترخيص المعتمد وتثبيته بنجاح على هذا الجهاز.\nالمنشأة: ${info.licenseeName} (${info.tier.labelAr})',
          referenceCode: info.planType,
          amountText: info.isLifetime ? 'دائم مدى الحياة' : '${info.expiresAt?.toIso8601String().substring(0, 10)}',
        );
        widget.onActivated();
      } else {
        setState(() {
          _errorMessage = info.validationError ?? 'مفتاح الترخيص غير صالح أو غير مخصص لهذا الجهاز';
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ أثناء معالجة الترخيص: $e';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final licenseService = ref.watch(licenseServiceProvider);
    final hwid = licenseService.getMachineHardwareId();

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: Stack(
        children: [
          // Ambient Liquid Lights Background Orbs
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 480,
              height: 480,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0284C7).withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4F46E5).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 200,
            left: 80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFD97706).withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Central Liquid Glass Container
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 2,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                            blurRadius: 30,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand Logo & Header
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(42),
                                    child: Image.asset(
                                      'assets/images/app_logo.png',
                                      width: 84,
                                      height: 84,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF1E293B),
                                        child: const Icon(
                                          Icons.corporate_fare_rounded,
                                          color: Color(0xFF38BDF8),
                                          size: 44,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'ALFA SOFT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'شركة ألفا للتجارة والخدمات — منظومة إدارة الموارد المؤسسية الذكية (ERP)',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Text(
                                    'بوابة تنشيط وترخيص النظام المعتمد',
                                    style: TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // SECTION 1: Liquid Glass Hardware Fingerprint Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.fingerprint_rounded, color: Color(0xFF38BDF8), size: 24),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'كود بصمة عتاد هذا الجهاز (Hardware Fingerprint):',
                                        style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'فريد ومحمي',
                                        style: TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Machine ID Text Container
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B132B).withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          hwid,
                                          style: const TextStyle(
                                            color: Color(0xFFF8FAFC),
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF38BDF8)),
                                        tooltip: 'نسخ كود الجهاز',
                                        onPressed: () => _copyHardwareId(hwid),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // WhatsApp & Copy Buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                                              blurRadius: 14,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openWhatsApp(hwid),
                                          icon: const Icon(Icons.send_rounded, size: 18),
                                          label: const Text(
                                            'طلب التفعيل عبر واتساب المطور',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => _copyHardwareId(hwid),
                                      icon: const Icon(Icons.copy_rounded, size: 18),
                                      label: const Text('نسخ الكود'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Contact Info Line
                                Center(
                                  child: Text(
                                    'هاتف / واتساب المطور: $developerPhone  |  إنستغرام: $developerInstagram',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // SECTION 2: License Input & Activation
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تفعيل وترخيص النظام:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B132B).withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: TextField(
                                  controller: _keyController,
                                  maxLines: 4,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'الصق مفتاح الترخيص المعتمد هنا...',
                                    hintStyle: TextStyle(color: Colors.grey.shade600),
                                    filled: false,
                                    contentPadding: const EdgeInsets.all(14),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _isProcessing ? null : _handleFileImport,
                                    icon: const Icon(Icons.file_open_rounded, size: 18),
                                    label: const Text('استيراد ملف الترخيص (.alfalic)'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF38BDF8),
                                      side: const BorderSide(color: Color(0xFF38BDF8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _isProcessing ? null : () => _processActivation(_keyController.text),
                                      icon: _isProcessing
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.verified_rounded, size: 20),
                                      label: Text(
                                        _isProcessing ? 'جاري التحقق الرقمي...' : 'تفعيل وترخيص النظام الآن',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Error Banner
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFEF4444)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Color(0xFFFCA5A5),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 24),
                          Divider(color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 12),

                          // Clean Security Badges (Zero cryptographic technical terms)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 18,
                            runSpacing: 8,
                            children: [
                              _buildSecurityPill(Icons.verified_rounded, 'ترخيص رقمي معتمد ومحمي'),
                              _buildSecurityPill(Icons.wifi_off_rounded, 'تحقق أوفلاين 100% دون إنترنت'),
                              _buildSecurityPill(Icons.memory_rounded, 'حماية مقترنة بعتاد الجهاز'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}
