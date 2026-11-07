import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/types/enums.dart';

class FirstRunWizard extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const FirstRunWizard({super.key, required this.onCompleted});

  @override
  ConsumerState<FirstRunWizard> createState() => _FirstRunWizardState();
}

class _FirstRunWizardState extends ConsumerState<FirstRunWizard> {
  final _formKey = GlobalKey<FormState>();

  final _companyNameController = TextEditingController(text: 'شركة ألفا للتجارة والخدمات');
  final _taxNumberController = TextEditingController(text: '300012345600003');
  final _branchNameController = TextEditingController(text: 'الفرع الرئيسي');
  final _warehouseNameController = TextEditingController(text: 'مستودع المبيعات العام');
  final _adminUsernameController = TextEditingController(text: 'admin');
  final _adminPasswordController = TextEditingController(text: 'Admin@2026');
  final _adminFullNameController = TextEditingController(text: 'المدير العام');

  CurrencyCode _selectedCurrency = CurrencyCode.sar;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _companyNameController.dispose();
    _taxNumberController.dispose();
    _branchNameController.dispose();
    _warehouseNameController.dispose();
    _adminUsernameController.dispose();
    _adminPasswordController.dispose();
    _adminFullNameController.dispose();
    super.dispose();
  }

  void _submitSetup() {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final db = ref.read(databaseServiceProvider);
    const uuid = Uuid();

    try {
      db.transaction((tx) {
        final companyId = 'comp_${uuid.v4()}';
        final branchId = 'br_${uuid.v4()}';
        final warehouseId = 'wh_${uuid.v4()}';
        final userId = 'usr_${uuid.v4()}';
        final roleId = 'role_${uuid.v4()}';

        // 1. Create Company
        tx.execute('''
          INSERT INTO companies (id, legal_name, trade_name, tax_number, currency_code, is_active)
          VALUES (?, ?, ?, ?, ?, 1)
        ''', [
          companyId,
          _companyNameController.text.trim(),
          _companyNameController.text.trim(),
          _taxNumberController.text.trim(),
          _selectedCurrency.code,
        ]);

        // 2. Create Default Main Branch
        tx.execute('''
          INSERT INTO branches (id, company_id, code, name, is_main, is_active)
          VALUES (?, ?, 'BR01', ?, 1, 1)
        ''', [branchId, companyId, _branchNameController.text.trim()]);

        // 3. Create Default Warehouse
        tx.execute('''
          INSERT INTO warehouses (id, branch_id, code, name, is_active)
          VALUES (?, ?, 'WH01', ?, 1)
        ''', [warehouseId, branchId, _warehouseNameController.text.trim()]);

        // 4. Create Super Admin Role with full permissions
        tx.execute('''
          INSERT INTO roles (id, company_id, name, description)
          VALUES (?, ?, 'SUPER_ADMIN', 'صلاحيات كاملة غير مقيدة على المنظومة')
        ''', [roleId, companyId]);

        // 5. Hash Password & Create Master Administrator
        final passwordBytes = utf8.encode(_adminPasswordController.text);
        final passwordHash = sha256.convert(passwordBytes).toString();

        tx.execute('''
          INSERT INTO users (id, company_id, username, password_hash, full_name, is_admin, is_active)
          VALUES (?, ?, ?, ?, ?, 1, 1)
        ''', [
          userId,
          companyId,
          _adminUsernameController.text.trim(),
          passwordHash,
          _adminFullNameController.text.trim(),
        ]);

        // 6. Assign Role
        tx.execute('''
          INSERT INTO user_roles (user_id, role_id)
          VALUES (?, ?)
        ''', [userId, roleId]);

        // 7. Audit Logging
        tx.execute('''
          INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
          VALUES (?, ?, ?, ?, 'DEV_MASTER', 'INITIAL_SYSTEM_BOOT', 'SYSTEM', ?, ?)
        ''', [
          'aud_${uuid.v4()}',
          companyId,
          branchId,
          userId,
          companyId,
          jsonEncode({
            'company': _companyNameController.text.trim(),
            'currency': _selectedCurrency.code,
            'admin': _adminUsernameController.text.trim(),
          }),
        ]);
      });

      widget.onCompleted();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'خطأ أثناء تهيئة المنظومة: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.brandAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.corporate_fare_rounded,
                                color: AppColors.brandAccent, size: 36),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ALFA SOFT — معالج التهيئة الأولية',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'إعداد بيانات الشركة، العملة الأساسية، وحساب المدير العام للتطبيق',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 24),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.danger),
                          ),
                          child: Text(_errorMessage!,
                              style: const TextStyle(color: AppColors.danger)),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Section 1: Company Profile
                      Text('1. بيانات المنشأة التجارية',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _companyNameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الشركة أو المؤسسة *',
                          prefixIcon: Icon(Icons.business_rounded),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المنشأة' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _taxNumberController,
                              decoration: const InputDecoration(
                                labelText: 'الرقم الضريبي (اختياري)',
                                prefixIcon: Icon(Icons.receipt_long_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<CurrencyCode>(
                              isExpanded: true,
                              initialValue: _selectedCurrency,
                              decoration: const InputDecoration(
                                labelText: 'العملة الأساسية *',
                                prefixIcon: Icon(Icons.currency_exchange_rounded),
                              ),
                              items: CurrencyCode.values.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text('${c.code} — ${c.nameAr}', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedCurrency = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Branch & Warehouse
                      Text('2. بيانات الفرع والمستودع الافتراضي',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _branchNameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم الفرع الأول *',
                                prefixIcon: Icon(Icons.storefront_rounded),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _warehouseNameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم المستودع الأول *',
                                prefixIcon: Icon(Icons.warehouse_rounded),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Master Admin Credentials
                      Text('3. بيانات المدير العام (حساب المسؤول الأول)',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _adminFullNameController,
                        decoration: const InputDecoration(
                          labelText: 'الاسم الكامل للمدير *',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'يرجى إدخال الاسم' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _adminUsernameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم المستخدم للولوج *',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _adminPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'كلمة المرور *',
                                prefixIcon: Icon(Icons.lock_rounded),
                              ),
                              validator: (v) =>
                                  v != null && v.length >= 6 ? null : '6 خانات على الأقل',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Submit Button
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitSetup,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.rocket_launch_rounded),
                        label: Text(_isSubmitting
                            ? 'جاري حفظ وتهيئة البيانات...'
                            : 'بدء تشغيل المنظومة والمتابعة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
