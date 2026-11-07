import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/organization.dart';

class OrganizationRepository {
  final DatabaseService _db;
  const OrganizationRepository(this._db);

  List<CompanyEntity> getCompanies() {
    final result = _db.select('SELECT * FROM companies ORDER BY created_at ASC');
    return result.map((r) => CompanyEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  CompanyEntity? getPrimaryCompany() {
    final result = _db.select('SELECT * FROM companies LIMIT 1');
    if (result.isEmpty) return null;
    return CompanyEntity.fromMap(Map<String, dynamic>.from(result.first));
  }

  List<BranchEntity> getBranches(String companyId) {
    final result = _db.select(
      'SELECT * FROM branches WHERE company_id = ? ORDER BY is_main DESC, code ASC',
      [companyId],
    );
    return result.map((r) => BranchEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  BranchEntity createBranch({
    required String companyId,
    required String code,
    required String name,
    String? phone,
    String? address,
    bool isMain = false,
  }) {
    const uuid = Uuid();
    final id = 'br_${uuid.v4()}';

    _db.transaction((tx) {
      if (isMain) {
        tx.execute('UPDATE branches SET is_main = 0 WHERE company_id = ?', [companyId]);
      }
      tx.execute('''
        INSERT INTO branches (id, company_id, code, name, phone, address, is_main, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
      ''', [id, companyId, code.trim(), name.trim(), phone?.trim(), address?.trim(), isMain ? 1 : 0]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_BRANCH', 'BRANCH', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, id, 'Branch: $code - $name']);
    });

    return BranchEntity(
      id: id,
      companyId: companyId,
      code: code,
      name: name,
      phone: phone,
      address: address,
      isMain: isMain,
    );
  }

  List<WarehouseEntity> getWarehouses(String branchId) {
    final result = _db.select(
      'SELECT * FROM warehouses WHERE branch_id = ? ORDER BY code ASC',
      [branchId],
    );
    return result.map((r) => WarehouseEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  WarehouseEntity createWarehouse({
    required String branchId,
    required String code,
    required String name,
  }) {
    const uuid = Uuid();
    final id = 'wh_${uuid.v4()}';

    _db.execute('''
      INSERT INTO warehouses (id, branch_id, code, name, is_active)
      VALUES (?, ?, ?, ?, 1)
    ''', [id, branchId, code.trim(), name.trim()]);

    return WarehouseEntity(
      id: id,
      branchId: branchId,
      code: code,
      name: name,
    );
  }
}
