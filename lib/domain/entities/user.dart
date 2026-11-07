class UserEntity {
  final String id;
  final String companyId;
  final String username;
  final String fullName;
  final String? phone;
  final String? email;
  final bool isAdmin;
  final bool isActive;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    required this.companyId,
    required this.username,
    required this.fullName,
    this.phone,
    this.email,
    this.isAdmin = false,
    this.isActive = true,
    required this.createdAt,
  });

  factory UserEntity.fromMap(Map<String, dynamic> map) {
    return UserEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      username: map['username'] as String,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      isAdmin: (map['is_admin'] as int) == 1,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class RoleEntity {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final List<String> permissions;

  const RoleEntity({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    this.permissions = const [],
  });

  factory RoleEntity.fromMap(Map<String, dynamic> map, [List<String> permissions = const []]) {
    return RoleEntity(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      permissions: permissions,
    );
  }
}
