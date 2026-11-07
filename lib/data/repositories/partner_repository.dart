import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/partner.dart';

class PartnerRepository {
  final DatabaseService _db;
  const PartnerRepository(this._db);

  List<CustomerEntity> getCustomers(String companyId, {String? query}) {
    String sql = 'SELECT * FROM customers WHERE company_id = ?';
    final params = <Object?>[companyId];

    if (query != null && query.trim().isNotEmpty) {
      sql += ' AND (code LIKE ? OR name LIKE ? OR phone LIKE ?)';
      final q = '%${query.trim()}%';
      params.addAll([q, q, q]);
    }

    sql += ' ORDER BY name ASC';
    final result = _db.select(sql, params);
    return result.map((r) => CustomerEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  CustomerEntity createCustomer({
    required String companyId,
    required String code,
    required String name,
    String? phone,
    String? taxNumber,
    int creditLimitCents = 0,
  }) {
    const uuid = Uuid();
    final id = 'cust_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO customers (
          id, company_id, code, name, phone, tax_number,
          credit_limit, current_balance, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1)
      ''', [id, companyId, code.trim(), name.trim(), phone?.trim(), taxNumber?.trim(), creditLimitCents]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_CUSTOMER', 'CUSTOMER', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, 'Customer: $code - $name']);
    });

    return CustomerEntity(
      id: id,
      companyId: companyId,
      code: code,
      name: name,
      phone: phone,
      taxNumber: taxNumber,
      creditLimitCents: creditLimitCents,
    );
  }

  List<SupplierEntity> getSuppliers(String companyId, {String? query}) {
    String sql = 'SELECT * FROM suppliers WHERE company_id = ?';
    final params = <Object?>[companyId];

    if (query != null && query.trim().isNotEmpty) {
      sql += ' AND (code LIKE ? OR name LIKE ? OR phone LIKE ?)';
      final q = '%${query.trim()}%';
      params.addAll([q, q, q]);
    }

    sql += ' ORDER BY name ASC';
    final result = _db.select(sql, params);
    return result.map((r) => SupplierEntity.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  SupplierEntity createSupplier({
    required String companyId,
    required String code,
    required String name,
    String? phone,
    String? taxNumber,
  }) {
    const uuid = Uuid();
    final id = 'supp_${uuid.v4()}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO suppliers (
          id, company_id, code, name, phone, tax_number,
          current_balance, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, 0, 1)
      ''', [id, companyId, code.trim(), name.trim(), phone?.trim(), taxNumber?.trim()]);

      // Audit Log
      tx.execute('''
        INSERT INTO audit_logs (id, company_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, 'SYSTEM', 'LOCAL_DESKTOP', 'CREATE_SUPPLIER', 'SUPPLIER', ?, ?)
      ''', ['aud_${uuid.v4()}', companyId, id, 'Supplier: $code - $name']);
    });

    return SupplierEntity(
      id: id,
      companyId: companyId,
      code: code,
      name: name,
      phone: phone,
      taxNumber: taxNumber,
    );
  }
}
