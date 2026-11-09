import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
                  Text('إضافة مستخدم جديد للنظام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 520,
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
                        const SizedBox(height: 16),
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
                            subtitle: const Text('الوصول لكافة فروع النظام، التقارير والإعدادات', style: TextStyle(fontSize: 11)),
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

                    repo.createUser(
                      companyId: companyId,
                      username: usernameController.text.trim(),
                      password: passwordController.text,
                      fullName: fullNameController.text.trim(),
                      phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                      email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                      isAdmin: isAdmin,
                    );

                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('حفظ المستخدم'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleUserStatus(UserEntity user) {
    try {
      final db = ref.read(databaseServiceProvider);
      final newStatus = user.isActive ? 0 : 1;
      db.execute('UPDATE users SET is_active = ? WHERE id = ?', [newStatus, user.id]);
      _loadData();
    } catch (_) {}
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
                        'إدارة المستخدمين والصلاحيات (Users & RBAC)',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'إدارة حسابات الموظفين، تحديد الصلاحيات الدقيقة، ومراقبة نشاط الدخول إلى المنظومة',
                        style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 320,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم المستخدم أو الاسم الكامل...',
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_rounded, size: 48, color: AppColors.lightTextMuted),
              SizedBox(height: 12),
              Text('لم يتم العثور على أي مستخدمين مسجلين', style: TextStyle(color: AppColors.lightTextSecondary)),
            ],
          ),
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
          child: Row(
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
        );
      },
    );
  }
}
