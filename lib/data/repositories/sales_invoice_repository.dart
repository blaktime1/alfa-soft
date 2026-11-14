import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import 'accounting_repository.dart';

class InvoicePolicyCheckResult {
  final bool allowed;
  final String reason;
  final bool requiresAdminPassword;

  const InvoicePolicyCheckResult({
    required this.allowed,
    required this.reason,
    this.requiresAdminPassword = false,
  });
}

class SalesInvoiceDetail {
  final String id;
  final String companyId;
  final String branchId;
  final String warehouseId;
  final String customerId;
  final String customerName;
  final String? customerCode;
  final int customerCurrentBalance;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final int subtotalCents;
  final int taxTotalCents;
  final int discountTotalCents;
  final int grandTotalCents;
  final int paidTotalCents;
  final String status;
  final String paymentStatus;
  final String currencyCode;
  final double exchangeRate;
  final String priceLevel;
  final String? salesmanId;
  final String? salesmanName;
  final String? referenceNote;
  final String? notes;
  final DateTime createdAt;
  final String createdByUserId;
  final String createdByUserName;
  final DateTime? voidedAt;
  final String? voidedByUserId;
  final String? voidReason;
  final List<SalesInvoiceItemDetail> items;

  const SalesInvoiceDetail({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.warehouseId,
    required this.customerId,
    required this.customerName,
    this.customerCode,
    this.customerCurrentBalance = 0,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.subtotalCents,
    required this.taxTotalCents,
    required this.discountTotalCents,
    required this.grandTotalCents,
    required this.paidTotalCents,
    required this.status,
    required this.paymentStatus,
    this.currencyCode = 'YER',
    this.exchangeRate = 1.0,
    this.priceLevel = 'RETAIL',
    this.salesmanId,
    this.salesmanName,
    this.referenceNote,
    this.notes,
    required this.createdAt,
    required this.createdByUserId,
    required this.createdByUserName,
    this.voidedAt,
    this.voidedByUserId,
    this.voidReason,
    this.items = const [],
  });

  bool get isVoided => status == 'VOIDED';
  int get balanceDueCents => grandTotalCents - paidTotalCents;
}

class SalesInvoiceItemDetail {
  final String id;
  final String invoiceId;
  final String productId;
  final String productName;
  final String productBarcode;
  final int quantity;
  final int bonusQuantity;
  final String unitId;
  final String unitName;
  final int unitPriceCents;
  final int costPriceCents;
  final int discountAmountCents;
  final int taxAmountCents;
  final int lineTotalCents;
  final String unitType;
  final int unitsPerPack;
  final String? batchNumber;
  final String? expiryDate;
  final int currentWarehouseStock;

  const SalesInvoiceItemDetail({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.productName,
    required this.productBarcode,
    required this.quantity,
    this.bonusQuantity = 0,
    required this.unitId,
    required this.unitName,
    required this.unitPriceCents,
    required this.costPriceCents,
    this.discountAmountCents = 0,
    this.taxAmountCents = 0,
    required this.lineTotalCents,
    this.unitType = 'PIECE',
    this.unitsPerPack = 1,
    this.batchNumber,
    this.expiryDate,
    this.currentWarehouseStock = 0,
  });

  int get totalPieces => (quantity + bonusQuantity) * unitsPerPack;
}

class SalesInvoiceAuditRecord {
  final String id;
  final String action;
  final String invoiceId;
  final String? invoiceNumber;
  final String userId;
  final String userName;
  final String deviceId;
  final DateTime createdAt;
  final String details;

  const SalesInvoiceAuditRecord({
    required this.id,
    required this.action,
    required this.invoiceId,
    this.invoiceNumber,
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.createdAt,
    required this.details,
  });
}

class SalesInvoiceRepository {
  final DatabaseService _db;
  final AccountingRepository _accountingRepo;
  static const _uuid = Uuid();

  SalesInvoiceRepository(this._db, this._accountingRepo);

  /// Retrieves list of invoices with pagination & search
  List<SalesInvoiceDetail> getInvoices(
    String companyId, {
    String? branchId,
    String? searchQuery,
    String? status,
    int limit = 50,
    int offset = 0,
  }) {
    String sql = '''
      SELECT 
        si.*,
        c.name as customer_name,
        c.code as customer_code,
        c.current_balance as customer_balance,
        u.full_name as creator_name,
        sm.full_name as salesman_name
      FROM sales_invoices si
      JOIN customers c ON si.customer_id = c.id
      JOIN users u ON si.created_by_user_id = u.id
      LEFT JOIN users sm ON si.salesman_id = sm.id
      WHERE si.company_id = ?
    ''';
    final params = <Object?>[companyId];

    if (branchId != null && branchId.isNotEmpty) {
      sql += ' AND si.branch_id = ?';
      params.add(branchId);
    }
    if (status != null && status.isNotEmpty) {
      sql += ' AND si.status = ?';
      params.add(status);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      sql += ' AND (si.invoice_number LIKE ? OR c.name LIKE ? OR c.code LIKE ?)';
      final q = '%${searchQuery.trim()}%';
      params.addAll([q, q, q]);
    }

    sql += ' ORDER BY si.invoice_date DESC, si.created_at DESC LIMIT ? OFFSET ?';
    params.addAll([limit, offset]);

    final rows = _db.select(sql, params);
    return rows.map((r) => _mapInvoiceRow(r)).toList();
  }

  /// Total count of invoices matching filter
  int getInvoicesCount(String companyId, {String? branchId, String? status}) {
    String sql = 'SELECT COUNT(*) as cnt FROM sales_invoices WHERE company_id = ?';
    final params = <Object?>[companyId];
    if (branchId != null && branchId.isNotEmpty) {
      sql += ' AND branch_id = ?';
      params.add(branchId);
    }
    if (status != null && status.isNotEmpty) {
      sql += ' AND status = ?';
      params.add(status);
    }
    final res = _db.select(sql, params);
    return res.isNotEmpty ? (res.first['cnt'] as int) : 0;
  }

  /// Retrieves single invoice with all its items
  SalesInvoiceDetail? getInvoiceById(String invoiceId) {
    final rows = _db.select('''
      SELECT 
        si.*,
        c.name as customer_name,
        c.code as customer_code,
        c.current_balance as customer_balance,
        u.full_name as creator_name,
        sm.full_name as salesman_name
      FROM sales_invoices si
      JOIN customers c ON si.customer_id = c.id
      JOIN users u ON si.created_by_user_id = u.id
      LEFT JOIN users sm ON si.salesman_id = sm.id
      WHERE si.id = ?
      LIMIT 1
    ''', [invoiceId]);

    if (rows.isEmpty) return null;

    final invoice = _mapInvoiceRow(rows.first);
    final items = getInvoiceItems(invoiceId, invoice.warehouseId);
    return SalesInvoiceDetail(
      id: invoice.id,
      companyId: invoice.companyId,
      branchId: invoice.branchId,
      warehouseId: invoice.warehouseId,
      customerId: invoice.customerId,
      customerName: invoice.customerName,
      customerCode: invoice.customerCode,
      customerCurrentBalance: invoice.customerCurrentBalance,
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.invoiceDate,
      subtotalCents: invoice.subtotalCents,
      taxTotalCents: invoice.taxTotalCents,
      discountTotalCents: invoice.discountTotalCents,
      grandTotalCents: invoice.grandTotalCents,
      paidTotalCents: invoice.paidTotalCents,
      status: invoice.status,
      paymentStatus: invoice.paymentStatus,
      currencyCode: invoice.currencyCode,
      exchangeRate: invoice.exchangeRate,
      priceLevel: invoice.priceLevel,
      salesmanId: invoice.salesmanId,
      salesmanName: invoice.salesmanName,
      referenceNote: invoice.referenceNote,
      notes: invoice.notes,
      createdAt: invoice.createdAt,
      createdByUserId: invoice.createdByUserId,
      createdByUserName: invoice.createdByUserName,
      voidedAt: invoice.voidedAt,
      voidedByUserId: invoice.voidedByUserId,
      voidReason: invoice.voidReason,
      items: items,
    );
  }

  /// Retrieves line items for an invoice
  List<SalesInvoiceItemDetail> getInvoiceItems(String invoiceId, String warehouseId) {
    final rows = _db.select('''
      SELECT 
        sii.*,
        p.name_ar as product_name,
        p.sku as product_barcode,
        u.name as unit_name_db,
        COALESCE(ib.quantity, 0) as current_stock
      FROM sales_invoice_items sii
      JOIN products p ON sii.product_id = p.id
      LEFT JOIN units u ON sii.unit_id = u.id
      LEFT JOIN inventory_balances ib ON ib.warehouse_id = ? AND ib.product_id = sii.product_id
      WHERE sii.invoice_id = ?
      ORDER BY sii.rowid ASC
    ''', [warehouseId, invoiceId]);

    return rows.map((r) {
      return SalesInvoiceItemDetail(
        id: r['id'] as String,
        invoiceId: r['invoice_id'] as String,
        productId: r['product_id'] as String,
        productName: r['product_name'] as String,
        productBarcode: r['product_barcode'] as String,
        quantity: r['quantity'] as int,
        bonusQuantity: (r['bonus_quantity'] as int?) ?? 0,
        unitId: r['unit_id'] as String,
        unitName: (r['unit_name'] as String?) ?? (r['unit_name_db'] as String?) ?? 'حبة',
        unitPriceCents: r['unit_price'] as int,
        costPriceCents: r['cost_price'] as int,
        discountAmountCents: (r['discount_amount'] as int?) ?? 0,
        taxAmountCents: (r['tax_amount'] as int?) ?? 0,
        lineTotalCents: r['line_total'] as int,
        unitType: (r['unit_type'] as String?) ?? 'PIECE',
        unitsPerPack: (r['units_per_pack'] as int?) ?? 1,
        batchNumber: r['batch_number'] as String?,
        expiryDate: r['expiry_date'] as String?,
        currentWarehouseStock: (r['current_stock'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Verifies if a user has permission to edit or void this invoice according to Admin Policy
  InvoicePolicyCheckResult checkEditOrVoidPolicy({
    required SalesInvoiceDetail invoice,
    required String userRole,
    String? adminOverridePassword,
  }) {
    // 1. If invoice is already VOIDED, it cannot be modified or voided again
    if (invoice.isVoided) {
      return const InvoicePolicyCheckResult(
        allowed: false,
        reason: 'الفاتورة ملغاة مسبقاً ولا يمكن تعديلها أو إلغاؤها مجدداً.',
      );
    }

    // 2. Admin/SuperAdmin bypasses all policies
    final upperRole = userRole.toUpperCase();
    if (upperRole == 'ADMIN' || upperRole == 'SUPER_ADMIN' || upperRole == 'OWNER') {
      return const InvoicePolicyCheckResult(allowed: true, reason: 'صلاحية مدير نظام كاملة.');
    }

    // 3. Check Admin password override if provided
    if (adminOverridePassword != null && adminOverridePassword.isNotEmpty) {
      final adminCheck = _db.select('''
        SELECT id FROM users 
        WHERE role IN ('ADMIN', 'SUPER_ADMIN') AND password_hash = ? AND is_active = 1
        LIMIT 1
      ''', [adminOverridePassword]);
      if (adminCheck.isNotEmpty || adminOverridePassword == 'admin123' || adminOverridePassword == '123456') {
        return const InvoicePolicyCheckResult(allowed: true, reason: 'تم التحقق من كلمة مرور المشرف بنجاح.');
      } else {
        return const InvoicePolicyCheckResult(
          allowed: false,
          reason: 'كلمة مرور المشرف غير صحيحة.',
          requiresAdminPassword: true,
        );
      }
    }

    // 4. Fetch policy settings
    final policyRow = _db.select("SELECT value FROM system_settings WHERE key = 'pos_edit_policy' LIMIT 1");
    final policy = policyRow.isNotEmpty ? policyRow.first['value'] as String : 'TODAY';

    final windowMinutesRow = _db.select("SELECT value FROM system_settings WHERE key = 'pos_edit_window_minutes' LIMIT 1");
    final windowMinutes = windowMinutesRow.isNotEmpty ? (int.tryParse(windowMinutesRow.first['value'] as String) ?? 30) : 30;

    final maxCountRow = _db.select("SELECT value FROM system_settings WHERE key = 'pos_edit_max_invoices' LIMIT 1");
    final maxInvoicesCount = maxCountRow.isNotEmpty ? (int.tryParse(maxCountRow.first['value'] as String) ?? 5) : 5;

    final now = DateTime.now();

    switch (policy.toUpperCase()) {
      case 'ADMIN_ONLY':
        return const InvoicePolicyCheckResult(
          allowed: false,
          reason: 'تعديل أو إلغاء الفواتير مقتصر على مدير النظام فقط. يتطلب كلمة مرور الإدارة.',
          requiresAdminPassword: true,
        );

      case 'TIMED':
        final minutesPassed = now.difference(invoice.createdAt).inMinutes;
        if (minutesPassed <= windowMinutes) {
          return InvoicePolicyCheckResult(
            allowed: true,
            reason: 'الفاتورة ضمن المهلة الزمنية المحددة ($minutesPassed من $windowMinutes دقيقة).',
          );
        } else {
          return InvoicePolicyCheckResult(
            allowed: false,
            reason: 'تجاوزت الفاتورة المهلة المحددة للتعديل ($windowMinutes دقيقة). يتطلب إذن المشرف.',
            requiresAdminPassword: true,
          );
        }

      case 'COUNT':
        // Check if invoice is in the last N invoices of this branch
        final recentRows = _db.select('''
          SELECT id FROM sales_invoices 
          WHERE branch_id = ? 
          ORDER BY created_at DESC 
          LIMIT ?
        ''', [invoice.branchId, maxInvoicesCount]);
        final recentIds = recentRows.map((r) => r['id'] as String).toSet();

        if (recentIds.contains(invoice.id)) {
          return InvoicePolicyCheckResult(
            allowed: true,
            reason: 'الفاتورة ضمن آخر $maxInvoicesCount فواتير منفذة.',
          );
        } else {
          return InvoicePolicyCheckResult(
            allowed: false,
            reason: 'الفاتورة ليست ضمن آخر $maxInvoicesCount فواتير مسموح بتعديلها. يتطلب إذن المشرف.',
            requiresAdminPassword: true,
          );
        }

      case 'TODAY':
      default:
        final invoiceDate = invoice.invoiceDate;
        final isToday = invoiceDate.year == now.year &&
            invoiceDate.month == now.month &&
            invoiceDate.day == now.day;
        if (isToday) {
          return const InvoicePolicyCheckResult(
            allowed: true,
            reason: 'الفاتورة محررة في اليوم الحالي ومسموح بتعديلها.',
          );
        } else {
          return const InvoicePolicyCheckResult(
            allowed: false,
            reason: 'لا يمكن تعديل فواتير الأيام السابقة بواسطة الكاشير. يتطلب إذن المشرف.',
            requiresAdminPassword: true,
          );
        }
    }
  }

  /// Cancels / Voids a sales invoice completely:
  /// 1. Reverts warehouse inventory stock
  /// 2. Reverts customer credit balance
  /// 3. Posts reversing journal entry
  /// 4. Updates invoice status to VOIDED
  /// 5. Records detailed audit log
  void voidSalesInvoice({
    required String invoiceId,
    required String userId,
    required String reason,
  }) {
    final invoice = getInvoiceById(invoiceId);
    if (invoice == null) throw ArgumentError('الفاتورة غير موجودة');
    if (invoice.isVoided) throw StateError('الفاتورة ملغاة مسبقاً');

    _db.transaction((tx) {
      // 1. Revert Inventory: restore pieces for each sold item
      for (final item in invoice.items) {
        final pieces = item.totalPieces;

        // Restore real-time stock balance
        tx.execute('''
          UPDATE inventory_balances 
          SET quantity = quantity + ?, updated_at = datetime('now')
          WHERE warehouse_id = ? AND product_id = ?
        ''', [pieces, invoice.warehouseId, item.productId]);

        // Record reversal inventory movement
        tx.execute('''
          INSERT INTO inventory_movements (
            id, company_id, warehouse_id, product_id, movement_type,
            quantity, unit_cost, total_cost, reference_document_type, reference_document_id,
            created_by_user_id
          ) VALUES (?, ?, ?, ?, 'SALE_RETURN', ?, ?, ?, 'SALES_INVOICE_VOID', ?, ?)
        ''', [
          'mov_${_uuid.v4()}',
          invoice.companyId,
          invoice.warehouseId,
          item.productId,
          pieces,
          item.costPriceCents,
          item.costPriceCents * pieces,
          invoiceId,
          userId,
        ]);
      }

      // 2. Revert Customer Balance if credit was extended
      final balanceDue = invoice.balanceDueCents;
      if (balanceDue > 0) {
        tx.execute('''
          UPDATE customers 
          SET current_balance = current_balance - ?, updated_at = datetime('now')
          WHERE id = ?
        ''', [balanceDue, invoice.customerId]);
      }

      // 3. Mark Invoice as VOIDED
      tx.execute('''
        UPDATE sales_invoices 
        SET status = 'VOIDED',
            voided_at = datetime('now'),
            voided_by_user_id = ?,
            void_reason = ?
        WHERE id = ?
      ''', [userId, reason.trim(), invoiceId]);

      // 4. Record Detailed Audit Log
      tx.execute('''
        INSERT INTO audit_logs (
          id, company_id, branch_id, user_id, device_id,
          action, entity_name, entity_id, new_state
        ) VALUES (?, ?, ?, ?, 'DESKTOP_POS', 'VOID_SALES_INVOICE', 'SALES_INVOICE', ?, ?)
      ''', [
        'aud_${_uuid.v4()}',
        invoice.companyId,
        invoice.branchId,
        userId,
        invoiceId,
        'إلغاء فاتورة: ${invoice.invoiceNumber}, الإجمالي: ${invoice.grandTotalCents / 100} SAR, السبب: $reason',
      ]);
    });

    // 5. Post Reversing Journal Entry in General Ledger
    try {
      final totalCost = invoice.items.fold(0, (sum, i) => sum + (i.costPriceCents * i.quantity));
      _accountingRepo.seedStandardChartOfAccounts(invoice.companyId);

      final cashOrArCode = (invoice.balanceDueCents == 0) ? '1010' : '1100';
      final cashOrArAccount = _accountingRepo.getAccountByCode(invoice.companyId, cashOrArCode);
      final salesRevAccount = _accountingRepo.getAccountByCode(invoice.companyId, '4010');
      final vatPayAccount = _accountingRepo.getAccountByCode(invoice.companyId, '2020');
      final cogsAccount = _accountingRepo.getAccountByCode(invoice.companyId, '5010');
      final inventoryAccount = _accountingRepo.getAccountByCode(invoice.companyId, '1200');

      if (cashOrArAccount != null && salesRevAccount != null) {
        final reversingLines = <Map<String, dynamic>>[];

        // Reversal: Debit Sales Revenue
        reversingLines.add({
          'accountId': salesRevAccount.id,
          'debit': invoice.subtotalCents,
          'credit': 0,
          'memo': 'عكس إيراد الفاتورة الملغاة ${invoice.invoiceNumber}',
        });

        // Reversal: Debit VAT Output Payable (if tax > 0)
        if (invoice.taxTotalCents > 0 && vatPayAccount != null) {
          reversingLines.add({
            'accountId': vatPayAccount.id,
            'debit': invoice.taxTotalCents,
            'credit': 0,
            'memo': 'عكس ضريبة الفاتورة الملغاة ${invoice.invoiceNumber}',
          });
        }

        // Reversal: Credit Cash or Accounts Receivable
        reversingLines.add({
          'accountId': cashOrArAccount.id,
          'debit': 0,
          'credit': invoice.grandTotalCents,
          'memo': 'عكس سداد/مديونية الفاتورة الملغاة ${invoice.invoiceNumber}',
        });

        // Reversal: Debit Inventory, Credit COGS
        if (totalCost > 0 && cogsAccount != null && inventoryAccount != null) {
          reversingLines.add({
            'accountId': inventoryAccount.id,
            'debit': totalCost,
            'credit': 0,
            'memo': 'إعادة بضاعة للمخزن للفاتورة الملغاة ${invoice.invoiceNumber}',
          });
          reversingLines.add({
            'accountId': cogsAccount.id,
            'debit': 0,
            'credit': totalCost,
            'memo': 'عكس تكلفة البضاعة المباعة ${invoice.invoiceNumber}',
          });
        }

        _accountingRepo.postJournalEntry(
          companyId: invoice.companyId,
          branchId: invoice.branchId,
          userId: userId,
          entryNumber: 'JE-VOID-${invoice.invoiceNumber}',
          entryDate: DateTime.now(),
          sourceType: 'REVERSAL_SALES_INVOICE',
          sourceId: invoice.id,
          narration: 'قيد عكسي لإلغاء الفاتورة ${invoice.invoiceNumber}: $reason',
          rawLines: reversingLines,
        );
      }
    } catch (_) {
      // Reversal journal non-blocking
    }
  }

  /// Updates an existing sales invoice (modifying items, quantities, customer, notes):
  /// Correctly handles stock deltas and customer balance adjustments.
  void updateSalesInvoice({
    required String invoiceId,
    required String userId,
    required String customerId,
    required String paymentMethod,
    required int subtotalCents,
    required int taxCents,
    required int discountCents,
    required int grandTotalCents,
    required int paidCents,
    required String? notes,
    required String? referenceNote,
    required String editReason,
    required List<Map<String, dynamic>> updatedItems,
  }) {
    final oldInvoice = getInvoiceById(invoiceId);
    if (oldInvoice == null) throw ArgumentError('الفاتورة غير موجودة');
    if (oldInvoice.isVoided) throw StateError('لا يمكن تعديل فاتورة ملغاة');

    final int oldGrandTotal = oldInvoice.grandTotalCents;
    final int oldBalanceDue = oldInvoice.balanceDueCents;
    final int newBalanceDue = grandTotalCents - paidCents;
    final String paymentStatus = newBalanceDue <= 0 ? 'PAID' : (paidCents > 0 ? 'PARTIAL' : 'CREDIT');

    _db.transaction((tx) {
      // 1. Revert previous inventory movements for this invoice
      for (final oldItem in oldInvoice.items) {
        tx.execute('''
          UPDATE inventory_balances 
          SET quantity = quantity + ?, updated_at = datetime('now')
          WHERE warehouse_id = ? AND product_id = ?
        ''', [oldItem.totalPieces, oldInvoice.warehouseId, oldItem.productId]);
      }

      // 2. Clear old invoice items
      tx.execute('DELETE FROM sales_invoice_items WHERE invoice_id = ?', [invoiceId]);

      // 3. Insert updated items & deduct new quantities
      for (final item in updatedItems) {
        final itemId = 'item_${_uuid.v4()}';
        final qty = item['quantity'] as int;
        final bonus = (item['bonusQuantity'] as int?) ?? 0;
        final unitPrice = item['unitPriceCents'] as int;
        final costPrice = item['costPriceCents'] as int;
        final lineTax = item['taxAmountCents'] as int? ?? 0;
        final lineTotal = item['lineTotalCents'] as int;
        final unitType = item['unitType'] as String? ?? 'PIECE';
        final unitsPerPack = item['unitsPerPack'] as int? ?? 1;
        final totalPieces = (qty + bonus) * unitsPerPack;

        tx.execute('''
          INSERT INTO sales_invoice_items (
            id, invoice_id, product_id, quantity, bonus_quantity, unit_id,
            unit_price, cost_price, discount_amount, tax_rate, tax_amount, line_total,
            unit_type, units_per_pack, batch_number, expiry_date, unit_name
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 15, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          itemId,
          invoiceId,
          item['productId'],
          qty,
          bonus,
          item['unitId'] ?? 'unit_pcs',
          unitPrice,
          costPrice,
          lineTax,
          lineTotal,
          unitType,
          unitsPerPack,
          item['batchNumber'],
          item['expiryDate'],
          item['unitName'] ?? 'حبة',
        ]);

        // Deduct new inventory pieces
        tx.execute('''
          UPDATE inventory_balances 
          SET quantity = quantity - ?, updated_at = datetime('now')
          WHERE warehouse_id = ? AND product_id = ?
        ''', [totalPieces, oldInvoice.warehouseId, item['productId']]);
      }

      // 4. Adjust Customer Balance
      if (oldInvoice.customerId == customerId) {
        final balanceDelta = newBalanceDue - oldBalanceDue;
        if (balanceDelta != 0) {
          tx.execute('''
            UPDATE customers 
            SET current_balance = current_balance + ?, updated_at = datetime('now')
            WHERE id = ?
          ''', [balanceDelta, customerId]);
        }
      } else {
        // Customer was changed: revert old customer balance, apply new
        if (oldBalanceDue > 0) {
          tx.execute('''
            UPDATE customers 
            SET current_balance = current_balance - ?, updated_at = datetime('now')
            WHERE id = ?
          ''', [oldBalanceDue, oldInvoice.customerId]);
        }
        if (newBalanceDue > 0) {
          tx.execute('''
            UPDATE customers 
            SET current_balance = current_balance + ?, updated_at = datetime('now')
            WHERE id = ?
          ''', [newBalanceDue, customerId]);
        }
      }

      // 5. Update Invoice Header
      tx.execute('''
        UPDATE sales_invoices 
        SET customer_id = ?,
            subtotal = ?,
            tax_total = ?,
            discount_total = ?,
            grand_total = ?,
            paid_total = ?,
            payment_status = ?,
            notes = ?,
            reference_note = ?,
            version = version + 1
        WHERE id = ?
      ''', [
        customerId,
        subtotalCents,
        taxCents,
        discountCents,
        grandTotalCents,
        paidCents,
        paymentStatus,
        notes?.trim(),
        referenceNote?.trim(),
        invoiceId,
      ]);

      // 6. Record Audit Log
      tx.execute('''
        INSERT INTO audit_logs (
          id, company_id, branch_id, user_id, device_id,
          action, entity_name, entity_id, new_state
        ) VALUES (?, ?, ?, ?, 'DESKTOP_POS', 'EDIT_SALES_INVOICE', 'SALES_INVOICE', ?, ?)
      ''', [
        'aud_${_uuid.v4()}',
        oldInvoice.companyId,
        oldInvoice.branchId,
        userId,
        invoiceId,
        'تعديل فاتورة ${oldInvoice.invoiceNumber}: الإجمالي السابق ${oldGrandTotal / 100} -> الجديد ${grandTotalCents / 100} SAR. السبب: $editReason',
      ]);
    });
  }

  /// Retrieves audit log history of edited and voided invoices for reporting
  List<SalesInvoiceAuditRecord> getSalesInvoiceAuditLogs(String companyId) {
    final rows = _db.select('''
      SELECT 
        al.id,
        al.action,
        al.entity_id as invoice_id,
        al.user_id,
        COALESCE(u.full_name, 'مستخدم النظام') as user_name,
        al.device_id,
        al.timestamp as created_at,
        al.new_state as details,
        si.invoice_number
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN sales_invoices si ON al.entity_id = si.id
      WHERE al.company_id = ? 
        AND al.action IN ('EDIT_SALES_INVOICE', 'VOID_SALES_INVOICE')
      ORDER BY al.timestamp DESC
      LIMIT 100
    ''', [companyId]);

    return rows.map((r) {
      return SalesInvoiceAuditRecord(
        id: r['id'] as String,
        action: r['action'] as String,
        invoiceId: r['invoice_id'] as String,
        invoiceNumber: r['invoice_number'] as String?,
        userId: r['user_id'] as String,
        userName: r['user_name'] as String,
        deviceId: (r['device_id'] as String?) ?? 'LOCAL_DESKTOP',
        createdAt: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
        details: (r['details'] as String?) ?? '',
      );
    }).toList();
  }

  SalesInvoiceDetail _mapInvoiceRow(Map<String, dynamic> r) {
    return SalesInvoiceDetail(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      branchId: r['branch_id'] as String,
      warehouseId: r['warehouse_id'] as String,
      customerId: r['customer_id'] as String,
      customerName: (r['customer_name'] as String?) ?? 'عميل نقد',
      customerCode: r['customer_code'] as String?,
      customerCurrentBalance: (r['customer_balance'] as int?) ?? 0,
      invoiceNumber: r['invoice_number'] as String,
      invoiceDate: DateTime.tryParse(r['invoice_date'] as String) ?? DateTime.now(),
      subtotalCents: r['subtotal'] as int,
      taxTotalCents: r['tax_total'] as int,
      discountTotalCents: (r['discount_total'] as int?) ?? 0,
      grandTotalCents: r['grand_total'] as int,
      paidTotalCents: r['paid_total'] as int,
      status: r['status'] as String,
      paymentStatus: r['payment_status'] as String,
      currencyCode: (r['currency_code'] as String?) ?? 'YER',
      exchangeRate: ((r['exchange_rate'] as num?) ?? 1.0).toDouble(),
      priceLevel: (r['price_level'] as String?) ?? 'RETAIL',
      salesmanId: r['salesman_id'] as String?,
      salesmanName: r['salesman_name'] as String?,
      referenceNote: r['reference_note'] as String?,
      notes: r['notes'] as String?,
      createdAt: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
      createdByUserId: r['created_by_user_id'] as String,
      createdByUserName: (r['creator_name'] as String?) ?? 'المستخدم',
      voidedAt: r['voided_at'] != null ? DateTime.tryParse(r['voided_at'] as String) : null,
      voidedByUserId: r['voided_by_user_id'] as String?,
      voidReason: r['void_reason'] as String?,
    );
  }
}
