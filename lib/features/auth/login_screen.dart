import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import 'package:printing/printing.dart';
import '../../core/printing/printer_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  String _companyName = 'ALFA SOFT';
  List<Map<String, String>> _branches = [];
  String? _selectedBranchId;
  List<Printer> _availablePrinters = [];
  String? _selectedPrinterName;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    try {
      final db = ref.read(databaseServiceProvider);
      final compRows = db.select('SELECT trade_name FROM companies LIMIT 1');
      if (compRows.isNotEmpty) {
        _companyName = compRows.first['trade_name'] as String;
      }

      final branchRows = db.select('SELECT id, code, name FROM branches WHERE is_active = 1 ORDER BY is_main DESC');
      if (branchRows.isNotEmpty) {
        _branches = branchRows.map((b) => {
          'id': b['id'] as String,
          'code': b['code'] as String,
          'name': b['name'] as String,
        }).toList();
        _selectedBranchId = _branches.first['id'];
      }

      final printerService = PrinterService(db);
      final savedPrinter = printerService.getSelectedPrinter();
      Printing.listPrinters().then((printers) {
        if (mounted) {
          setState(() {
            _availablePrinters = printers;
            if (savedPrinter != null && printers.any((p) => p.name == savedPrinter)) {
              _selectedPrinterName = savedPrinter;
            } else if (printers.any((p) => p.isDefault)) {
              _selectedPrinterName = printers.firstWhere((p) => p.isDefault).name;
            } else if (printers.isNotEmpty) {
              _selectedPrinterName = printers.first.name;
            }
          });
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPrinterName != null) {
      try {
        final db = ref.read(databaseServiceProvider);
        PrinterService(db).setSelectedPrinter(_selectedPrinterName);
      } catch (_) {}
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final success = ref.read(currentUserProvider.notifier).login(username, password);

    if (mounted) {
      if (!success) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'اسم المستخدم أو كلمة المرور غير صحيحة، يرجى المحاولة مجدداً.';
        });
      } else {
        // Active user updated in Riverpod; _AppRootDecider will automatically transition to MainShell
      }
    }
  }

  void _fillDefaultCredentials() {
    setState(() {
      _usernameController.text = 'admin';
      _passwordController.text = 'Admin@2026';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.lightBgCanvas,
      body: Stack(
        children: [
          // Ambient Layered Backdrop
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandAccent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandGold.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Layered Centered Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.lightBgSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.lightBorderSubtle, width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Color(0x040F172A),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Brand Icon & Identity Layer
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.lightBorderSubtle, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.brandGold.withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(40),
                                child: Image.asset(
                                  'assets/images/app_logo.png',
                                  width: 68,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 68,
                                    height: 68,
                                    decoration: const BoxDecoration(
                                      color: AppColors.brandPrimary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.corporate_fare_rounded,
                                        color: Colors.white, size: 36),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Titles
                          Text(
                            'ALFA SOFT',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'منظومة إدارة الموارد المؤسسية الذكية — ERP',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.lightTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Company & Branch Badge
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.lightBgSubtle,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.lightBorderSubtle),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded, size: 14, color: AppColors.brandAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    _companyName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brandPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Error Display
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.dangerBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.dangerText),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: AppColors.dangerText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Username Field
                          Text(
                            'اسم المستخدم',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _usernameController,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            decoration: InputDecoration(
                              hintText: 'أدخل اسم المستخدم (مثال: admin)',
                              prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.lightTextSecondary),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المستخدم' : null,
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          Text(
                            'كلمة المرور',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.lightTextSecondary),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: AppColors.lightTextSecondary,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال كلمة المرور' : null,
                            onFieldSubmitted: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 16),

                          // Branch Selector Dropdown
                          if (_branches.isNotEmpty) ...[
                            Text(
                              'فرع تسجيل الدخول',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBranchId,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.storefront_rounded, color: AppColors.lightTextSecondary),
                              ),
                              items: _branches.map((b) {
                                return DropdownMenuItem(
                                  value: b['id'],
                                  child: Text('${b['name']} (${b['code']})', style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedBranchId = v);
                              },
                            ),
                            const SizedBox(height: 16),
                          ] else
                            const SizedBox(height: 8),

                          // POS Printer Selector
                          Text(
                            'طابعة فواتير الكاشير (POS Printer)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPrinterName,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.print_rounded, color: AppColors.lightTextSecondary),
                              hintText: 'اختر طابعة الفواتير المعتمدة',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('معاينة النظام الافتراضية (PDF)', style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary)),
                              ),
                              ..._availablePrinters.map((p) {
                                return DropdownMenuItem(
                                  value: p.name,
                                  child: Text(
                                    '${p.name}${p.isDefault ? ' (الافتراضية)' : ''}',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (v) {
                              setState(() => _selectedPrinterName = v);
                              if (v != null) {
                                try {
                                  final db = ref.read(databaseServiceProvider);
                                  PrinterService(db).setSelectedPrinter(v);
                                } catch (_) {}
                              }
                            },
                          ),
                          const SizedBox(height: 24),

                          // Submit Login Button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandPrimary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isLoading ? null : _handleLogin,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'تسجيل الدخول للنظام',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Quick Credential Assist Card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.lightBgSubtle,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.lightBorderSubtle),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.key_rounded, size: 18, color: AppColors.brandGold),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'حساب المسؤول الافتراضي:',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.lightTextSecondary),
                                      ),
                                      Text(
                                        'admin / Admin@2026',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.lightTextPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: _fillDefaultCredentials,
                                  child: const Text('تعبئة سريعة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
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
}
