import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/partner.dart';
import '../../core/sync/outbox_manager.dart';

class PartnerStatementItem {
  final String date;
  final String docType;
  final String docNumber;
  final int debitHalalas; // مدين (عليه)
  final int creditHalalas; // دائن (له / سدد)
  final int runningBalanceHalalas;
  final String notes;

  const PartnerStatementItem({
    required this.date,
    required this.docType,
    required this.docNumber,
    required this.debitHalalas,
    required this.creditHalalas,
    required this.runningBalanceHalalas,
    required this.notes,
  });

  double get debit => debitHalalas / 100.0;
  double get credit => creditHalalas / 100.0;
  double get runningBalance => runningBalanceHalalas / 100.0;
}

class PartnerRepository {
  final DatabaseService _db;
  final OutboxManager _outbox;

  PartnerRepository(this._db) : _outbox = OutboxManager(_db);

  List<CustomerEntity> getCustomers(String companyId, {String? query}) {
    String sql = 'SELECT * FROM customers WHERE company_id = ? AND is_active = 1';
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

    try {
      _outbox.enqueue(
        entityType: 'CUSTOMER',
        entityId: id,
        operation: SyncOperation.create,
        payload: {
          'id': id,
          'company_id': companyId,
          'code': code.trim(),
          'name': name.trim(),
          'phone': phone?.trim(),
          'tax_number': taxNumber?.trim(),
          'credit_limit': creditLimitCents,
          'current_balance': 0,
          'is_active': 1,
        },
      );
    } catch (_) {}

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

  void updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? taxNumber,
    required int creditLimitCents,
    bool isActive = true,
  }) {
    _db.execute('''
      UPDATE customers 
      SET name = ?, phone = ?, tax_number = ?, credit_limit = ?, is_active = ?, updated_at = datetime('now')
      WHERE id = ?
    ''', [name.trim(), phone?.trim(), taxNumber?.trim(), creditLimitCents, isActive ? 1 : 0, id]);

    try {
      _outbox.enqueue(
        entityType: 'CUSTOMER',
        entityId: id,
        operation: SyncOperation.update,
        payload: {
          'id': id,
          'name': name.trim(),
          'phone': phone?.trim(),
          'tax_number': taxNumber?.trim(),
          'credit_limit': creditLimitCents,
          'is_active': isActive ? 1 : 0,
        },
      );
    } catch (_) {}
  }

  void deleteCustomer(String id) {
    _db.execute('UPDATE customers SET is_active = 0, updated_at = datetime("now") WHERE id = ?', [id]);
    try {
      _outbox.enqueue(
        entityType: 'CUSTOMER',
        entityId: id,
        operation: SyncOperation.delete,
        payload: {'id': id, 'is_active': 0},
      );
    } catch (_) {}
  }

  List<SupplierEntity> getSuppliers(String companyId, {String? query}) {
    String sql = 'SELECT * FROM suppliers WHERE company_id = ? AND is_active = 1';
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

    try {
      _outbox.enqueue(
        entityType: 'SUPPLIER',
        entityId: id,
        operation: SyncOperation.create,
        payload: {
          'id': id,
          'company_id': companyId,
          'code': code.trim(),
          'name': name.trim(),
          'phone': phone?.trim(),
          'tax_number': taxNumber?.trim(),
          'current_balance': 0,
          'is_active': 1,
        },
      );
    } catch (_) {}

    return SupplierEntity(
      id: id,
      companyId: companyId,
      code: code,
      name: name,
      phone: phone,
      taxNumber: taxNumber,
    );
  }

  void updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? taxNumber,
    bool isActive = true,
  }) {
    _db.execute('''
      UPDATE suppliers 
      SET name = ?, phone = ?, tax_number = ?, is_active = ?, updated_at = datetime('now')
      WHERE id = ?
    ''', [name.trim(), phone?.trim(), taxNumber?.trim(), isActive ? 1 : 0, id]);

    try {
      _outbox.enqueue(
        entityType: 'SUPPLIER',
        entityId: id,
        operation: SyncOperation.update,
        payload: {
          'id': id,
          'name': name.trim(),
          'phone': phone?.trim(),
          'tax_number': taxNumber?.trim(),
          'is_active': isActive ? 1 : 0,
        },
      );
    } catch (_) {}
  }

  void deleteSupplier(String id) {
    _db.execute('UPDATE suppliers SET is_active = 0, updated_at = datetime("now") WHERE id = ?', [id]);
    try {
      _outbox.enqueue(
        entityType: 'SUPPLIER',
        entityId: id,
        operation: SyncOperation.delete,
        payload: {'id': id, 'is_active': 0},
      );
    } catch (_) {}
  }

  /// Records a cash / bank payment from a customer to settle deferred debt
  void recordCustomerPayment({
    required String companyId,
    required String branchId,
    required String customerId,
    required int amountHalalas,
    String paymentMethod = 'CASH',
    String? referenceNumber,
    String? notes,
    required String userId,
  }) {
    const uuid = Uuid();
    final paymentId = 'pay_${uuid.v4()}';
    final refNo = referenceNumber ?? 'RCT-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO payments (
          id, company_id, branch_id, document_type, document_id,
          payment_method, amount, reference_number, created_by_user_id
        ) VALUES (?, ?, ?, 'CUSTOMER_PAYMENT', ?, ?, ?, ?, ?)
      ''', [
        paymentId,
        companyId,
        branchId,
        customerId,
        paymentMethod,
        amountHalalas,
        refNo,
        userId,
      ]);

      // Reduce customer's current balance (debt owed by them)
      tx.execute('''
        UPDATE customers 
        SET current_balance = current_balance - ?, updated_at = datetime('now')
        WHERE id = ?
      ''', [amountHalalas, customerId]);

      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'DESKTOP_CLIENT', 'CUSTOMER_PAYMENT', 'CUSTOMER', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        customerId,
        'Amount: ${amountHalalas / 100.0} SAR, Ref: $refNo, Notes: ${notes ?? ""}',
      ]);
    });

    try {
      _outbox.enqueue(
        entityType: 'PAYMENT',
        entityId: paymentId,
        operation: SyncOperation.create,
        payload: {
          'id': paymentId,
          'customer_id': customerId,
          'amount': amountHalalas,
          'method': paymentMethod,
          'reference': refNo,
        },
      );
    } catch (_) {}
  }

  /// Records a cash / bank payment to a supplier
  void recordSupplierPayment({
    required String companyId,
    required String branchId,
    required String supplierId,
    required int amountHalalas,
    String paymentMethod = 'CASH',
    String? referenceNumber,
    String? notes,
    required String userId,
  }) {
    const uuid = Uuid();
    final paymentId = 'pay_${uuid.v4()}';
    final refNo = referenceNumber ?? 'VCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

    _db.transaction((tx) {
      tx.execute('''
        INSERT INTO payments (
          id, company_id, branch_id, document_type, document_id,
          payment_method, amount, reference_number, created_by_user_id
        ) VALUES (?, ?, ?, 'SUPPLIER_PAYMENT', ?, ?, ?, ?, ?)
      ''', [
        paymentId,
        companyId,
        branchId,
        supplierId,
        paymentMethod,
        amountHalalas,
        refNo,
        userId,
      ]);

      // Reduce supplier's current balance (our liability to them)
      tx.execute('''
        UPDATE suppliers 
        SET current_balance = current_balance - ?, updated_at = datetime('now')
        WHERE id = ?
      ''', [amountHalalas, supplierId]);

      tx.execute('''
        INSERT INTO audit_logs (id, company_id, branch_id, user_id, device_id, action, entity_name, entity_id, new_state)
        VALUES (?, ?, ?, ?, 'DESKTOP_CLIENT', 'SUPPLIER_PAYMENT', 'SUPPLIER', ?, ?)
      ''', [
        'aud_${uuid.v4()}',
        companyId,
        branchId,
        userId,
        supplierId,
        'Amount: ${amountHalalas / 100.0} SAR, Ref: $refNo, Notes: ${notes ?? ""}',
      ]);
    });

    try {
      _outbox.enqueue(
        entityType: 'PAYMENT',
        entityId: paymentId,
        operation: SyncOperation.create,
        payload: {
          'id': paymentId,
          'supplier_id': supplierId,
          'amount': amountHalalas,
          'method': paymentMethod,
          'reference': refNo,
        },
      );
    } catch (_) {}
  }

  /// Retrieves chronological statement of account for a customer
  List<PartnerStatementItem> getCustomerStatement(String customerId) {
    final items = <PartnerStatementItem>[];

    // 1. Fetch sales invoices
    final invRows = _db.select('''
      SELECT invoice_number, invoice_date, grand_total, paid_total, payment_status
      FROM sales_invoices
      WHERE customer_id = ?
      ORDER BY invoice_date ASC
    ''', [customerId]);

    for (final row in invRows) {
      final grandTotal = row['grand_total'] as int;
      final paidTotal = row['paid_total'] as int;
      final unpaid = grandTotal - paidTotal;
      final status = row['payment_status'] as String;

      items.add(
        PartnerStatementItem(
          date: (row['invoice_date'] as String).substring(0, 10),
          docType: status == 'PAID' ? 'فاتورة مبيعات (نقدية)' : 'فاتورة مبيعات (آجلة)',
          docNumber: row['invoice_number'] as String,
          debitHalalas: grandTotal,
          creditHalalas: paidTotal,
          runningBalanceHalalas: 0, // will compute sequentially below
          notes: 'إجمالي الفاتورة: ${(grandTotal / 100).toStringAsFixed(2)} | مسدد منها: ${(paidTotal / 100).toStringAsFixed(2)} | متبقي: ${(unpaid / 100).toStringAsFixed(2)}',
        ),
      );
    }

    // 2. Fetch direct payments/receipts
    final payRows = _db.select('''
      SELECT reference_number, amount, payment_method, created_at
      FROM payments
      WHERE document_type = 'CUSTOMER_PAYMENT' AND document_id = ?
      ORDER BY created_at ASC
    ''', [customerId]);

    for (final row in payRows) {
      final amount = row['amount'] as int;
      final method = row['payment_method'] as String;
      items.add(
        PartnerStatementItem(
          date: (row['created_at'] as String).substring(0, 10),
          docType: 'سند قبض نقدي ($method)',
          docNumber: row['reference_number'] as String? ?? '—',
          debitHalalas: 0,
          creditHalalas: amount,
          runningBalanceHalalas: 0,
          notes: 'تحصيل وسداد نقدي لحساب آجل',
        ),
      );
    }

    // Sort all movements by date
    items.sort((a, b) => a.date.compareTo(b.date));

    // Calculate running balance: balance = previous_balance + debit - credit
    int running = 0;
    final finalized = <PartnerStatementItem>[];
    for (final it in items) {
      running += (it.debitHalalas - it.creditHalalas);
      finalized.add(
        PartnerStatementItem(
          date: it.date,
          docType: it.docType,
          docNumber: it.docNumber,
          debitHalalas: it.debitHalalas,
          creditHalalas: it.creditHalalas,
          runningBalanceHalalas: running,
          notes: it.notes,
        ),
      );
    }

    return finalized;
  }

  /// Retrieves chronological statement of account for a supplier
  List<PartnerStatementItem> getSupplierStatement(String supplierId) {
    final items = <PartnerStatementItem>[];

    // 1. Fetch goods receipt notes / purchase orders if table exists
    try {
      final grnRows = _db.select('''
        SELECT grn_number, receipt_date, total_cost
        FROM goods_receipt_notes
        WHERE supplier_id = ?
        ORDER BY receipt_date ASC
      ''', [supplierId]);

      for (final row in grnRows) {
        final total = row['total_cost'] as int? ?? 0;
        items.add(
          PartnerStatementItem(
            date: (row['receipt_date'] as String).substring(0, 10),
            docType: 'سند استلام بضاعة (مشتريات)',
            docNumber: row['grn_number'] as String,
            debitHalalas: 0,
            creditHalalas: total,
            runningBalanceHalalas: 0,
            notes: 'توريد مشتريات للمخزن',
          ),
        );
      }
    } catch (_) {}

    // 2. Fetch payments to this supplier
    final payRows = _db.select('''
      SELECT reference_number, amount, payment_method, created_at
      FROM payments
      WHERE document_type = 'SUPPLIER_PAYMENT' AND document_id = ?
      ORDER BY created_at ASC
    ''', [supplierId]);

    for (final row in payRows) {
      final amount = row['amount'] as int;
      final method = row['payment_method'] as String;
      items.add(
        PartnerStatementItem(
          date: (row['created_at'] as String).substring(0, 10),
          docType: 'سند صرف نقدي ($method)',
          docNumber: row['reference_number'] as String? ?? '—',
          debitHalalas: amount,
          creditHalalas: 0,
          runningBalanceHalalas: 0,
          notes: 'سداد دفعة للمورد',
        ),
      );
    }

    items.sort((a, b) => a.date.compareTo(b.date));

    int running = 0;
    final finalized = <PartnerStatementItem>[];
    for (final it in items) {
      running += (it.creditHalalas - it.debitHalalas);
      finalized.add(
        PartnerStatementItem(
          date: it.date,
          docType: it.docType,
          docNumber: it.docNumber,
          debitHalalas: it.debitHalalas,
          creditHalalas: it.creditHalalas,
          runningBalanceHalalas: running,
          notes: it.notes,
        ),
      );
    }

    return finalized;
  }
}
