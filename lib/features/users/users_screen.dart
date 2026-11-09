import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/entities/user.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<UserEntity> _users = [];
  List<RoleEntity> _roles = [];
  List<UserActivitySummary> _userReports = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    final db = ref.read(databaseServiceProvider);
    final repo = UserRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;
        _users = repo.getUsers(companyId);
        _roles = repo.getRoles(companyId);
        _userReports = repo.getUserActivityReports(companyId);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddUserDialog() {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    bool isAdmin = false;
    String? selectedRoleId = _roles.isNotEmpty ? _roles.first.id : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.lightBorderSubtle),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded, color: AppColors.brandAccent),
                  SizedBox(width: 10),
                  Text('إضافة مستخدم جديد للنظام ومزامنته', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: usernameController,
                                decoration: const InputDecoration(labelText: 'اسم الدخول (Username) *'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextFormField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'كلمة المرور *'),
                                validator: (v) => v != null && v.length >= 6 ? null : '6 خانات على الأقل',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: fullNameController,
                          decoration: const InputDecoration(labelText: 'الاسم الكامل للموظف *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: phoneController,
                                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextFormField(
                                controller: emailController,
                                decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_roles.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            initialValue: selectedRoleId,
                            decoration: const InputDecoration(
                              labelText: 'مجموعة الصلاحيات (الدور الوظيفي) *',
                              prefixIcon: Icon(Icons.shield_outlined),
                            ),
                            items: _roles.map((r) {
                              return DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.name} (${r.permissions.length} صلاحيات)'),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(() => selectedRoleId = v),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.lightBgSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.lightBorderSubtle),
                          ),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('صلاحيات إدارية كاملة (مدير عام)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: const Text('إمكانية الوصول للإعدادات الحساسة، التراخيص وسجلات النظام', style: TextStyle(fontSize: 11)),
                            value: isAdmin,
                            onChanged: (v) => setDialogState(() => isAdmin = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(color: AppColors.lightTextSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final db = ref.read(databaseServiceProvider);
                    final repo = UserRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                    final newUser = repo.createUser(
                      companyId: companyId,
                      username: usernameController.text.trim(),
                      password: passwordController.text,
                      fullName: fullNameController.text.trim(),
                      phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                      email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                      isAdmin: isAdmin,
                    );

                    if (selectedRoleId != null) {
                      repo.assignRoleToUser(newUser.id, selectedRoleId!);
                    }

                    Navigator.pop(ctx);
                    _loadData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم إنشاء المستخدم "${newUser.username}" وتم جدولته للمزامنة التلقائية'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  child: const Text('حفظ ومزامنة المستخدم'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateRoleDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final selectedPermissions = <String>{'pos_checkout', 'inventory_view', 'reports_financial'};

    final allPermissions = [
      {'key': 'pos_checkout', 'title': 'إتمام المبيعات والفواتير (POS Cashier)'},
      {'key': 'pos_discount', 'title': 'منح خصومات على الفاتورة وتعديل الأسعار'},
      {'key': 'inventory_view', 'title': 'استعراض كتالوج المخزون والأسعار'},
      {'key': 'inventory_adjust', 'title': 'إجراء التسويات والتحويلات المخزنية'},
      {'key': 'purchases_create', 'title': 'إنشاء فواتير وأوامر الشراء والتوريد'},
      {'key': 'accounting_journal', 'title': 'تسجيل ومطابقة القيود اليومية وسندات الصرف'},
      {'key': 'reports_financial', 'title': 'الاطلاع على التقارير المالية والإقرارات'},
      {'key': 'reports_user_sales', 'title': 'استعراض تقارير مبيعات المستخدمين والكاشير'},
      {'key': 'users_manage', 'title': 'إدارة حسابات المستخدمين ومنح الصلاحيات'},
      {'key': 'settings_manage', 'title': 'تعديل إعدادات المنشأة وطابعات الفواتير'},
      {'key': 'backup_manage', 'title': 'إنشاء النسخ الاحتياطية وإدارة قاعدة البيانات'},
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.lightBgSurface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.lightBorderSubtle),
              ),
              title: const Row(
                children: [
                  Icon(Icons.security_rounded, color: AppColors.brandPrimary),
                  SizedBox(width: 10),
                  Text('إنشاء مجموعة صلاحيات جديدة (Role)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'اسم الدور الوظيفي (مثال: كاشير مسائي) *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descController,
                          decoration: const InputDecoration(labelText: 'وصف مختصر للدور والمسؤوليات'),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'حدد الصلاحيات الممنوحة لهذا الدور:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.lightTextPrimary),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.lightBgSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.lightBorderSubtle),
                          ),
                          child: Column(
                            children: allPermissions.map((perm) {
                              final key = perm['key']!;
                              final isChecked = selectedPermissions.contains(key);
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(perm['title']!, style: const TextStyle(fontSize: 12)),
                                value: isChecked,
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedPermissions.add(key);
                                    } else {
                                      selectedPermissions.remove(key);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(color: AppColors.lightTextSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final db = ref.read(databaseServiceProvider);
                    final repo = UserRepository(db);
                    final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;

                    repo.createRole(
                      companyId: companyId,
                      name: nameController.text.trim(),
                      description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                      permissions: selectedPermissions.toList(),
                    );

                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('حفظ ومزامنة الدور'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showUserAuditTrailModal(UserActivitySummary summary) {
    final db = ref.read(databaseServiceProvider);
    final repo = UserRepository(db);
    final auditLogs = repo.getUserAuditTrail(summary.userId, summary.username);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.lightBgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.brandPrimary,
                        child: Text(
                          summary.username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'سجل تدقيق نشاط: ${summary.fullName} (${summary.username})',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'إجمالي العمليات المسجلة: ${auditLogs.length} عملية',
                              style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: auditLogs.isEmpty
                        ? const Center(child: Text('لا توجد عمليات مسجلة لهذا المستخدم حتى الآن'))
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: auditLogs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final log = auditLogs[i];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.infoBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.infoText, size: 20),
                                ),
                                title: Text(
                                  '${log['action']} — ${log['entity_name']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  log['new_state']?.toString() ?? 'بدون تفاصيل إضافية',
                                  style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary),
                                ),
                                trailing: Text(
                                  log['timestamp']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 11, color: AppColors.lightTextMuted),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleUserStatus(UserEntity user) {
    final db = ref.read(databaseServiceProvider);
    final repo = UserRepository(db);
    repo.toggleUserStatus(user.id, !user.isActive);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.lightBgCanvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredUsers = _users.where((u) {
      if (_searchQuery.isEmpty) return true;
      return u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.fullName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final adminCount = _users.where((u) => u.isAdmin).length;
    final activeCount = _users.where((u) => u.isActive).length;

    return Scaffold(
      backgroundColor: AppColors.lightBgCanvas,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightBorderSubtle),
                  ),
                  child: const Icon(Icons.manage_accounts_rounded, color: AppColors.brandPrimary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة المستخدمين والصلاحيات والتقارير (Users & RBAC Hub)',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'إدارة الموظفين، تحديد الصلاحيات الدقيقة، مزامنة الشبكة التلقائية، وعرض تقارير المبيعات لكل مستخدم',
                        style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showCreateRoleDialog,
                  icon: const Icon(Icons.shield_rounded, size: 18),
                  label: const Text('إنشاء دور جديد'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAddUserDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('إضافة مستخدم جديد'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Layered KPI Summary Tiles
            Row(
              children: [
                _buildKpiCard('إجمالي المستخدمين', '${_users.length}', Icons.group_rounded, AppColors.brandAccent),
                const SizedBox(width: 16),
                _buildKpiCard('المدراء والمشرفون', '$adminCount', Icons.shield_rounded, AppColors.brandGold),
                const SizedBox(width: 16),
                _buildKpiCard('الحسابات النشطة', '$activeCount', Icons.check_circle_rounded, AppColors.success),
                const SizedBox(width: 16),
                _buildKpiCard('مجموعات الصلاحيات', '${_roles.length}', Icons.admin_panel_settings_rounded, AppColors.info),
              ],
            ),
            const SizedBox(height: 20),

            // Tabs Bar & Search
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.lightBgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lightBorderSubtle),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.brandAccent,
                      labelColor: AppColors.brandPrimary,
                      unselectedLabelColor: AppColors.lightTextSecondary,
                      tabs: [
                        Tab(text: 'حسابات المستخدمين (${_users.length})'),
                        Tab(text: 'الأدوار ومصفوفة الصلاحيات (${_roles.length})'),
                        Tab(text: 'تقارير أداء ومبيعات المستخدمين (${_userReports.length})'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم المستخدم أو الاسم...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      fillColor: AppColors.lightBgSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUsersTab(filteredUsers),
                  _buildRolesTab(),
                  _buildReportsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Color(0x050F172A), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: AppColors.lightTextSecondary)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.lightTextPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab(List<UserEntity> users) {
    if (users.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorderSubtle),
        ),
        child: const Center(
          child: Text('لم يتم العثور على أي مستخدمين مسجلين', style: TextStyle(color: AppColors.lightTextSecondary)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightBgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorderSubtle),
        boxShadow: const [
          BoxShadow(color: Color(0x050F172A), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('المستخدم', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الاسم الكامل', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('رقم الهاتف', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('البريد الإلكتروني', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('نوع الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الإجراءات', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: users.map((u) {
              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.1),
                          child: Text(
                            u.username.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(u.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  DataCell(Text(u.fullName)),
                  DataCell(Text(u.phone ?? '—')),
                  DataCell(Text(u.email ?? '—')),
                  DataCell(
                    u.isAdmin
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brandGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                            ),
                            child: const Text('مدير عام', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brandGoldDark)),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brandAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('موظف / مستخدم', style: TextStyle(fontSize: 11, color: AppColors.brandAccent)),
                          ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: u.isActive ? AppColors.successBg : AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: u.isActive ? AppColors.success.withValues(alpha: 0.3) : AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        u.isActive ? 'نشط' : 'معطل',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: u.isActive ? AppColors.successText : AppColors.dangerText,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            u.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                            size: 18,
                            color: u.isActive ? AppColors.danger : AppColors.success,
                          ),
                          tooltip: u.isActive ? 'تعطيل الحساب' : 'تفعيل الحساب',
                          onPressed: () => _toggleUserStatus(u),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildRolesTab() {
    if (_roles.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorderSubtle),
        ),
        child: const Center(child: Text('لا توجد مجموعات صلاحيات مسجلة')),
      );
    }

    return ListView.separated(
      itemCount: _roles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final role = _roles[index];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.lightBgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.lightBorderSubtle),
            boxShadow: const [
              BoxShadow(color: Color(0x040F172A), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.security_rounded, color: AppColors.brandPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(role.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(role.description ?? 'صلاحيات قياسية للنظام', style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      '${role.permissions.length} صلاحيات محددة',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.infoText),
                    ),
                  ),
                ],
              ),
              if (role.permissions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: role.permissions.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.lightBgSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.lightBorderSubtle),
                      ),
                      child: Text(p, style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // TAB 3: Per-User Performance & Sales Reports
  Widget _buildReportsTab() {
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    if (_userReports.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.lightBgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorderSubtle),
        ),
        child: const Center(
          child: Text('لا توجد بيانات مبيعات أو نشاط مسجلة للمستخدمين حتى الآن'),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightBgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorderSubtle),
        boxShadow: const [
          BoxShadow(color: Color(0x050F172A), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.lightBgSubtle),
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('المستخدم (الكاشير)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الاسم الكامل', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('عدد الفواتير', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('إجمالي المبيعات', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المحصل نقدياً', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('متوسط الفاتورة', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('العمليات بالسجل', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('سجل النشاط', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _userReports.map((report) {
              return DataRow(
                cells: [
                  DataCell(Text(report.username, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(report.fullName)),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${report.invoiceCount} فاتورة', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${currencyFormat.format(report.totalSales)} ر.س',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.successText),
                    ),
                  ),
                  DataCell(Text('${currencyFormat.format(report.totalPaid)} ر.س')),
                  DataCell(Text('${currencyFormat.format(report.avgInvoiceValue)} ر.س')),
                  DataCell(Text('${report.auditCount} عملية')),
                  DataCell(
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: const Text('سجل التدقيق', style: TextStyle(fontSize: 11)),
                      onPressed: () => _showUserAuditTrailModal(report),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
