import 'dart:io';
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
    // Allows customer to browse and select an .alfalic license file
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

  Future<void> _processActivation(String rawKey) async {
    final cleanKey = rawKey.trim();
    if (cleanKey.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال أو إلصاق مفتاح الترخيص');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final info = await ref.read(licenseInfoProvider.notifier).activate(cleanKey);

      if (!mounted) return;

      if (info.isValid) {
        setState(() => _isProcessing = false);

        await OperationSuccessDialog.show(
          context: context,
          title: 'تم تفعيل وترخيص النظام بنجاح!',
          message: 'تم التحقق من التوقيع الرقمي ومطابقة بصمة عتاد الجهاز بنجاح.\nالمنشأة: ${info.licenseeName}\nالخطة: ${info.isLifetime ? "ترخيص دائم مدى الحياة" : "صالح حتى ${info.expiresAt?.toIso8601String().substring(0, 10)}"}',
          referenceCode: info.hardwareId,
          amountText: info.tier.labelAr,
        );

        widget.onActivated();
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = info.validationError ?? 'مفتاح الترخيص غير صالح أو لا يتطابق مع هذا الجهاز.';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'حدث خطأ أثناء فحص الترخيص: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final licenseService = ref.watch(licenseServiceProvider);
    final hwid = licenseService.getMachineHardwareId();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Navy Background
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Card(
              elevation: 16,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              color: const Color(0xFF1E293B), // Deep Slate
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // System Branding Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.vpn_key_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'ALFA SOFT — بوابة تفعيل وترخيص النظام',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'نظام إدارة وتخطيط الموارد المؤسسية (ERP) — تفعيل محلي مشفر ومقيد بالعتاد',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // SECTION 1: Hardware Fingerprint Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'فريد ومحمي',
                                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF475569)),
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

                          // Contact Developer Actions
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _openWhatsApp(hwid),
                                  icon: const Icon(Icons.send_rounded, size: 18),
                                  label: const Text('طلب التفعيل عبر واتساب المطور'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF22C55E), // WhatsApp Green
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                  side: const BorderSide(color: Color(0xFF64748B)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'هاتف / واتساب المطور: $developerPhone  |  إنستغرام: $developerInstagram',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                              ),
                            ],
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
                          'تفعيل الترخيص المستلم:',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _keyController,
                          maxLines: 4,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            hintText: 'الصق مفتاح الترخيص المشفر (ALFALIC-...) هنا...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF475569)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF475569)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

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
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () => _processActivation(_keyController.text),
                              icon: _isProcessing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.verified_rounded, size: 20),
                              label: Text(_isProcessing ? 'جاري التحقق الرقمي...' : 'تفعيل وترخيص النظام الآن'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                              color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEF4444)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 28),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 14),

                    // Security Badges
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildSecurityPill(Icons.lock_rounded, 'توقيع إلكتروني Ed25519'),
                        _buildSecurityPill(Icons.wifi_off_rounded, 'تحقق أوفلاين 100% دون إنترنت'),
                        _buildSecurityPill(Icons.memory_rounded, 'حماية مشفرة ببصمة العتاد'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityPill(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ],
    );
  }
}
