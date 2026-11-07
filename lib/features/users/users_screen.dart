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
      // Handle gracefully
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
              title: const Text('إضافة مستخدم جديد للنظام', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                          const SizedBox(width: 12),
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fullNameController,
                        decoration: const InputDecoration(labelText: 'الاسم الكامل *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: phoneController,
                              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: emailController,
                              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('منح صلاحيات إدارية كاملة (مدير نظام)'),
                        value: isAdmin,
                        onChanged: (v) => setDialogState(() => isAdmin = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إدارة المستخدمين والصلاحيات (RBAC)',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('حسابات الموظفين، تشفير كلمات المرور، وتوزيع الأدوار والصلاحيات الدقيقة',
                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddUserDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('إضافة مستخدم جديد'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tabs Header
            Card(
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                tabs: [
                  Tab(text: 'حسابات المستخدمين (${_users.length})'),
                  Tab(text: 'الأدوار ومجموعات الصلاحيات (${_roles.length})'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Users View
                  Card(
                    child: _users.isEmpty
                        ? const Center(child: Text('لا يوجد مستخدمون مسجلون'))
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('اسم الدخول')),
                                DataColumn(label: Text('الاسم الكامل')),
                                DataColumn(label: Text('الهاتف')),
                                DataColumn(label: Text('البريد')),
                                DataColumn(label: Text('النوع')),
                                DataColumn(label: Text('الحالة')),
                              ],
                              rows: _users.map((u) {
                                return DataRow(cells: [
                                  DataCell(Text(u.username, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text(u.fullName)),
                                  DataCell(Text(u.phone ?? '—')),
                                  DataCell(Text(u.email ?? '—')),
                                  DataCell(u.isAdmin
                                      ? const Chip(
                                          label: Text('مدير عام', style: TextStyle(fontSize: 11)),
                                          backgroundColor: AppColors.brandAccent,
                                          labelStyle: TextStyle(color: Colors.white),
                                        )
                                      : const Text('موظف / مستخدم')),
                                  DataCell(Chip(
                                    label: Text(u.isActive ? 'نشط' : 'معطل', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: u.isActive
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.danger.withValues(alpha: 0.15),
                                    side: BorderSide.none,
                                  )),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),

                  // Roles View
                  Card(
                    child: _roles.isEmpty
                        ? const Center(child: Text('لا توجد أدوار مسجلة'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _roles.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final role = _roles[index];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandAccent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.security_rounded, color: AppColors.brandAccent),
                                ),
                                title: Text(role.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(role.description ?? 'لا يوجد وصف'),
                                trailing: Chip(
                                  label: Text('${role.permissions.length} صلاحيات محددة'),
                                  backgroundColor: AppColors.info.withValues(alpha: 0.15),
                                ),
                              );
                            },
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
