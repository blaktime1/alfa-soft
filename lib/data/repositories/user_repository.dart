import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../local/database_service.dart';
import '../../domain/entities/user.dart';

class UserRepository {
  final DatabaseService _db;
  const UserRepository(this._db);

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
  }
}
