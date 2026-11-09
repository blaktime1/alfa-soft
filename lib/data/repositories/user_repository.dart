import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../local/database_service.dart';
import '../../core/sync/outbox_manager.dart';
import '../../domain/entities/user.dart';

class UserActivitySummary {
  final String userId;
  final String username;
  final String fullName;
  final bool isAdmin;
  final bool isActive;
  final int invoiceCount;
  final int totalSalesHalalas;
  final int totalPaidHalalas;
  final int auditCount;
  final DateTime? lastActiveAt;

  const UserActivitySummary({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.isAdmin,
    required this.isActive,
    required this.invoiceCount,
    required this.totalSalesHalalas,
    required this.totalPaidHalalas,
    required this.auditCount,
    this.lastActiveAt,
  });

  double get totalSales => totalSalesHalalas / 100.0;
  double get totalPaid => totalPaidHalalas / 100.0;
  double get avgInvoiceValue => invoiceCount > 0 ? totalSales / invoiceCount : 0.0;
}

class UserRepository {
  final DatabaseService _db;
  final OutboxManager _outbox;

  UserRepository(this._db) : _outbox = OutboxManager(_db);

  List<UserEntity> getUsers(String companyId) {
    final result = _db.select(
      'SELECT * FROM users WHERE company_id = ? ORDER BY created_at ASC',
      [companyId],
    );
    return result.map((r) => UserEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  UserEntity? authenticate(String username, String password) {
    final passwordBytes = utf8.encode(password);
    final passwordHash = sha256.convert(passwordBytes).toString();

    final result = _db.select(
      'SELECT * FROM users WHERE username = ? AND password_hash = ? AND is_active = 1 LIMIT 1',
      [username.trim(), passwordHash],
    );

    if (result.isEmpty) return null;
    return UserEntity.fromMap(Map<String, dynamic>.from(result.first));
  }

  UserEntity createUser({
    required String companyId,
    required String username,
    required String password,
    required String fullName,
    String? phone,
    String? email,
    bool isAdmin = false,
  }) {
    const uuid = Uuid();
    final id = 'usr_${uuid.v4()}';
    final passwordBytes = utf8.encode(password);
    final passwordHash = sha256.convert(passwordBytes).toString();

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO users (
          id, company_id, username, password_hash, full_name,
          phone, email, is_admin, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
      ''', [
        id,
        companyId,
        username.trim(),
        passwordHash,
        fullName.trim(),
        phone?.trim(),
        email?.trim(),
        isAdmin ? 1 : 0,
      ]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_USER', 'USER', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, 'User: $username - $fullName']);
    });

    // Enqueue to sync outbox for cross-node replication
    try {
      _outbox.enqueue(
        entityType: 'USER',
        entityId: id,
        operation: SyncOperation.create,
        payload: {
          'id': id,
          'company_id': companyId,
          'username': username.trim(),
          'full_name': fullName.trim(),
          'phone': phone?.trim(),
          'email': email?.trim(),
          'is_admin': isAdmin ? 1 : 0,
          'is_active': 1,
        },
      );
    } catch (_) {}

    return UserEntity(
      id: id,
      companyId: companyId,
      username: username,
      fullName: fullName,
      phone: phone,
      email: email,
      isAdmin: isAdmin,
      createdAt: DateTime.now(),
    );
  }

  void updateUser({
    required String userId,
    required String fullName,
    String? phone,
    String? email,
    required bool isAdmin,
    required bool isActive,
    String? newPassword,
  }) {
    _db.transaction((tx) {
      if (newPassword != null && newPassword.trim().isNotEmpty) {
        final passwordBytes = utf8.encode(newPassword.trim());
        final passwordHash = sha256.convert(passwordBytes).toString();
        tx.execute('''
          UPDATE users 
          SET full_name = ?, phone = ?, email = ?, is_admin = ?, is_active = ?, password_hash = ?, updated_at = datetime('now')
          WHERE id = ?
        ''', [fullName.trim(), phone?.trim(), email?.trim(), isAdmin ? 1 : 0, isActive ? 1 : 0, passwordHash, userId]);
      } else {
        tx.execute('''
          UPDATE users 
          SET full_name = ?, phone = ?, email = ?, is_admin = ?, is_active = ?, updated_at = datetime('now')
          WHERE id = ?
        ''', [fullName.trim(), phone?.trim(), email?.trim(), isAdmin ? 1 : 0, isActive ? 1 : 0, userId]);
      }

      const uuid = Uuid();
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, 'SYSTEM', 'ADMIN', 'LOCAL_DESKTOP', 'UPDATE_USER', 'USER', ?, ?)
      ''', ['aud_${uuid.v4()}', userId, 'Updated: $fullName (Admin: $isAdmin, Active: $isActive)']);
    });

    // Enqueue sync event
    try {
      _outbox.enqueue(
        entityType: 'USER',
        entityId: userId,
        operation: SyncOperation.update,
        payload: {
          'id': userId,
          'full_name': fullName.trim(),
          'phone': phone?.trim(),
          'email': email?.trim(),
          'is_admin': isAdmin ? 1 : 0,
          'is_active': isActive ? 1 : 0,
        },
      );
    } catch (_) {}
  }

  void toggleUserStatus(String userId, bool newStatus) {
    _db.execute('UPDATE users SET is_active = ?, updated_at = datetime("now") WHERE id = ?', [
      newStatus ? 1 : 0,
      userId,
    ]);

    try {
      _outbox.enqueue(
        entityType: 'USER',
        entityId: userId,
        operation: SyncOperation.update,
        payload: {'id': userId, 'is_active': newStatus ? 1 : 0},
      );
    } catch (_) {}
  }

  List<RoleEntity> getRoles(String companyId) {
    final rolesResult = _db.select('SELECT * FROM roles WHERE company_id = ?', [companyId]);
    final roles = <RoleEntity>[];

    for (final row in rolesResult) {
      final roleId = row['id'] as String;
      final permsResult = _db.select('SELECT permission_key FROM role_permissions WHERE role_id = ?', [roleId]);
      final permissions = permsResult.map((p) => p['permission_key'] as String).toList();
      roles.add(RoleEntity.fromMap(Map<String, dynamic>.from(row), permissions));
    }

    return roles;
  }

  RoleEntity createRole({
    required String companyId,
    required String name,
    String? description,
    List<String> permissions = const [],
  }) {
    const uuid = Uuid();
    final id = 'role_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO roles (id, company_id, name, description)
        VALUES (?, ?, ?, ?)
      ''', [id, companyId, name.trim(), description?.trim()]);

      for (final perm in permissions) {
        tx.execute('''
          INSERT INTO role_permissions (role_id, permission_key)
          VALUES (?, ?)
        ''', [id, perm]);
      }
    });

    try {
      _outbox.enqueue(
        entityType: 'ROLE',
        entityId: id,
        operation: SyncOperation.create,
        payload: {
          'id': id,
          'company_id': companyId,
          'name': name.trim(),
          'description': description?.trim(),
          'permissions': permissions,
        },
      );
    } catch (_) {}

    return RoleEntity(
      id: id,
      companyId: companyId,
      name: name,
      description: description,
      permissions: permissions,
    );
  }

  void assignRoleToUser(String userId, String roleId, [String? branchId]) {
    _db.execute('''
      INSERT OR REPLACE INTO user_roles (user_id, role_id, branch_id)
      VALUES (?, ?, ?)
    ''', [userId, roleId, branchId]);

    try {
      _outbox.enqueue(
        entityType: 'USER_ROLE',
        entityId: '${userId}_$roleId',
        operation: SyncOperation.create,
        payload: {'user_id': userId, 'role_id': roleId, 'branch_id': branchId},
      );
    } catch (_) {}
  }

  /// Aggregates sales volume, invoice counts, and activity logs per user
  List<UserActivitySummary> getUserActivityReports(String companyId) {
    final query = '''
      SELECT 
        u.id as user_id,
        u.username,
        u.full_name,
        u.is_admin,
        u.is_active,
        COUNT(DISTINCT si.id) as invoice_count,
        COALESCE(SUM(si.grand_total), 0) as total_sales_halalas,
        COALESCE(SUM(si.paid_total), 0) as total_paid_halalas,
        (SELECT COUNT(*) FROM audit_logs al WHERE al.user_id = u.id OR al.user_id = u.username) as audit_count,
        (SELECT MAX(timestamp) FROM audit_logs al WHERE al.user_id = u.id OR al.user_id = u.username) as last_active
      FROM users u
      LEFT JOIN sales_invoices si ON si.created_by_user_id = u.id
      WHERE u.company_id = ?
      GROUP BY u.id
      ORDER BY total_sales_halalas DESC
    ''';

    final rows = _db.select(query, [companyId]);
    return rows.map((r) {
      final lastActiveStr = r['last_active'] as String?;
      return UserActivitySummary(
        userId: r['user_id'] as String,
        username: r['username'] as String,
        fullName: r['full_name'] as String,
        isAdmin: (r['is_admin'] as int) == 1,
        isActive: (r['is_active'] as int) == 1,
        invoiceCount: r['invoice_count'] as int,
        totalSalesHalalas: r['total_sales_halalas'] as int,
        totalPaidHalalas: r['total_paid_halalas'] as int,
        auditCount: r['audit_count'] as int,
        lastActiveAt: lastActiveStr != null ? DateTime.tryParse(lastActiveStr) : null,
      );
    }).toList();
  }

  /// Retrieves detailed audit trail for a specific user
  List<Map<String, dynamic>> getUserAuditTrail(String userId, [String? username]) {
    final rows = _db.select('''
      SELECT action, entity_name, entity_id, timestamp, new_state
      FROM audit_logs
      WHERE user_id = ? OR user_id = ?
      ORDER BY timestamp DESC
      LIMIT 100
    ''', [userId, username ?? userId]);

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
