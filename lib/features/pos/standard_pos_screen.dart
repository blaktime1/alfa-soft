import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/math/bankers_rounding.dart';
import '../../core/printing/pdf_invoice_generator.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/partner.dart';
import '../../domain/entities/organization.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/partner_repository.dart';
import '../../data/repositories/organization_repository.dart';
import '../../data/repositories/sales_invoice_repository.dart';

class StandardPosItemRow {
  String productId;
  String barcode;
  String name;
  String unitId;
  String unitName;
  int quantity;
  int bonusQuantity;
  int unitPriceCents;
  int costPriceCents;
  int discountCents;
  String? batchNumber;
  String? expiryDate;
  int warehouseStock;
  bool isCarton;
  int unitsPerCarton;

  StandardPosItemRow({
    required this.productId,
    required this.barcode,
    required this.name,
    this.unitId = 'unit_pcs',
    this.unitName = 'حبة',
    this.quantity = 1,
    this.bonusQuantity = 0,
    required this.unitPriceCents,
    required this.costPriceCents,
    this.discountCents = 0,
    this.batchNumber,
    this.expiryDate,
    this.warehouseStock = 0,
    this.isCarton = false,
    this.unitsPerCarton = 1,
  });

  int get lineTotalCents => (quantity * unitPriceCents) - discountCents;
  int get lineTaxCents => BankersRounding.toMinorUnits((lineTotalCents / 100.0) * 0.15, scale: 2);
  int get inventoryPieces => (quantity + bonusQuantity) * (isCarton ? unitsPerCarton : 1);
}

class StandardPosScreen extends ConsumerStatefulWidget {
  final VoidCallback onExit;

  const StandardPosScreen({super.key, required this.onExit});

  @override
  ConsumerState<StandardPosScreen> createState() => _StandardPosScreenState();
}

class _StandardPosScreenState extends ConsumerState<StandardPosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Header State
  String? _selectedBranchId;
  String? _selectedWarehouseId;
  String _priceLevel = 'RETAIL'; // 'RETAIL' or 'WHOLESALE'
  String _currencyCode = 'YER';
  double _exchangeRate = 1.0;
  String _paymentMethod = 'CASH'; // 'CASH', 'CREDIT', 'BANK'

  String? _selectedCustomerId;
  String? _selectedSalesmanId;
  String _invoiceNumber = '';
  DateTime _invoiceDate = DateTime.now();
  final TextEditingController _referenceCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _paidCtrl = TextEditingController();

  // Checkboxes
  bool _repeatItem = false;
  bool _autoNewLine = true;
  bool _moveDown = true;
  bool _directPrint = false;
  bool _printAfterSave = true;

  // Invoice Rows
  final List<StandardPosItemRow> _rows = [];

  // Master Data Cache
  List<BranchEntity> _branches = [];
  List<WarehouseEntity> _warehouses = [];
  List<CustomerEntity> _customers = [];
  List<ProductEntity> _products = [];
  List<Map<String, dynamic>> _salesmen = [];
  List<UnitEntity> _availableUnits = [];

  // Navigation State
  List<String> _allInvoiceIds = [];
  int _currentInvoiceIndex = -1;
  String? _loadedInvoiceId;
  bool _isEditingExisting = false;
  bool _isExistingVoided = false;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  void _initializeData() {
    final db = ref.read(databaseServiceProvider);
    final orgRepo = OrganizationRepository(db);
    final partnerRepo = PartnerRepository(db);
    final catalogRepo = CatalogRepository(db);

    try {
      final compResult = db.select('SELECT id FROM companies LIMIT 1');
      if (compResult.isNotEmpty) {
        final companyId = compResult.first['id'] as String;

        _branches = orgRepo.getBranches(companyId);
        if (_branches.isNotEmpty) {
          _selectedBranchId = _branches.first.id;
          _warehouses = orgRepo.getWarehouses(_selectedBranchId!);
          if (_warehouses.isNotEmpty) {
            _selectedWarehouseId = _warehouses.first.id;
          }
        }

        _customers = partnerRepo.getCustomers(companyId);
        if (_customers.isEmpty) {
          partnerRepo.createCustomer(
            companyId: companyId,
            code: 'WALK_IN',
            name: 'عميل نقدي عابر',
          );
          _customers = partnerRepo.getCustomers(companyId);
        }
        _selectedCustomerId = _customers.first.id;

        _products = catalogRepo.getProducts(companyId: companyId);
        _availableUnits = catalogRepo.getUnits(companyId);

        final usersResult = db.select(
          "SELECT id, full_name, username FROM users WHERE company_id = ? AND is_active = 1",
          [companyId],
        );
        _salesmen = usersResult.map((u) => Map<String, dynamic>.from(u)).toList();
        if (_salesmen.isNotEmpty) {
          _selectedSalesmanId = _salesmen.first['id'] as String;
        }

        // Load invoice IDs for navigation
        final invRows = db.select(
          "SELECT id FROM sales_invoices WHERE company_id = ? ORDER BY invoice_date ASC, created_at ASC",
          [companyId],
        );
        _allInvoiceIds = invRows.map((r) => r['id'] as String).toList();
      }

      _resetToNewInvoice();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetToNewInvoice() {
    setState(() {
      _loadedInvoiceId = null;
      _isEditingExisting = false;
      _isExistingVoided = false;
      _currentInvoiceIndex = _allInvoiceIds.length;
      _invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      _invoiceDate = DateTime.now();
      _referenceCtrl.clear();
      _notesCtrl.clear();
      _paidCtrl.clear();
      _paymentMethod = 'CASH';
      _rows.clear();
      // Add first blank row
      _addNewBlankRow();
    });
  }

  void _addNewBlankRow() {
    if (_products.isEmpty) return;
    final firstProd = _products.first;
    final stock = _getWarehouseStock(firstProd.id);

    _rows.add(StandardPosItemRow(
      productId: firstProd.id,
      barcode: firstProd.sku,
      name: firstProd.nameAr,
      unitPriceCents: (_priceLevel == 'WHOLESALE' && firstProd.minSalePriceCents > 0)
          ? firstProd.minSalePriceCents
          : firstProd.salePriceCents,
      costPriceCents: firstProd.costPriceCents,
      warehouseStock: stock,
      isCarton: false,
      unitsPerCarton: firstProd.unitsPerCarton,
    ));
  }

  int _getWarehouseStock(String productId) {
    if (_selectedWarehouseId == null) return 0;
    try {
      final db = ref.read(databaseServiceProvider);
      final res = db.select(
        'SELECT quantity FROM inventory_balances WHERE warehouse_id = ? AND product_id = ? LIMIT 1',
        [_selectedWarehouseId, productId],
      );
      return res.isNotEmpty ? (res.first['quantity'] as int) : 0;
    } catch (_) {
      return 0;
    }
  }

  // Calculation Getters
  int get _subtotalCents => _rows.fold(0, (sum, r) => sum + r.lineTotalCents);
  int get _taxCents => _rows.fold(0, (sum, r) => sum + r.lineTaxCents);
  int get _discountCents => _rows.fold(0, (sum, r) => sum + r.discountCents);
  int get _grandTotalCents => _subtotalCents + _taxCents;

  int get _actualPaidCents {
    if (_paymentMethod == 'CASH' || _paymentMethod == 'BANK') {
      return _grandTotalCents;
    }
    final entered = double.tryParse(_paidCtrl.text.trim()) ?? 0;
    return (entered * 100).round();
  }

  int get _balanceDueCents => _grandTotalCents - _actualPaidCents;

  CustomerEntity? get _currentCustomer {
    if (_selectedCustomerId == null) return null;
    try {
      return _customers.firstWhere((c) => c.id == _selectedCustomerId);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------
  // ACTIONS: SAVE, EDIT, VOID, SEARCH, PRINT, NAVIGATE
  // -------------------------------------------------------------

  /// "حفظ" Button: Saves/Executes payment & invoice creation or update
  Future<void> _handleSaveInvoice() async {
    final validRows = _rows.where((r) => r.quantity > 0 && r.productId.isNotEmpty).toList();
    if (validRows.isEmpty) {
      _showSnack('يرجى إضافة صنف واحد على الأقل بكمية صالحة', isError: true);
      return;
    }

    final db = ref.read(databaseServiceProvider);
    final salesRepo = ref.read(salesInvoiceRepositoryProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    if (compResult.isEmpty) return;
    final companyId = compResult.first['id'] as String;
    final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

    try {
      if (_isEditingExisting && _loadedInvoiceId != null) {
        // Edit existing invoice
        salesRepo.updateSalesInvoice(
          invoiceId: _loadedInvoiceId!,
          userId: userId,
          customerId: _selectedCustomerId!,
          paymentMethod: _paymentMethod,
          subtotalCents: _subtotalCents,
          taxCents: _taxCents,
          discountCents: _discountCents,
          grandTotalCents: _grandTotalCents,
          paidCents: _actualPaidCents,
          notes: _notesCtrl.text,
          referenceNote: _referenceCtrl.text,
          editReason: 'تعديل الفاتورة من شاشة الكاشير الاعتيادية',
          updatedItems: validRows.map((r) {
            return {
              'productId': r.productId,
              'quantity': r.quantity,
              'bonusQuantity': r.bonusQuantity,
              'unitId': r.unitId,
              'unitName': r.unitName,
              'unitPriceCents': r.unitPriceCents,
              'costPriceCents': r.costPriceCents,
              'taxAmountCents': r.lineTaxCents,
              'lineTotalCents': r.lineTotalCents,
              'unitType': r.isCarton ? 'CARTON' : 'PIECE',
              'unitsPerPack': r.isCarton ? r.unitsPerCarton : 1,
              'batchNumber': r.batchNumber,
              'expiryDate': r.expiryDate,
            };
          }).toList(),
        );

        _showSnack('تم تحديث الفاتورة $_invoiceNumber بنجاح');
        _loadInvoiceById(_loadedInvoiceId!);
      } else {
        // Create new invoice
        const uuid = Uuid();
        final newInvoiceId = 'inv_${uuid.v4()}';
        final paymentStatus = _balanceDueCents <= 0 ? 'PAID' : (_actualPaidCents > 0 ? 'PARTIAL' : 'CREDIT');

        db.transaction((tx) {
          // 1. Sales invoice header
          tx.execute('''
            INSERT INTO sales_invoices (
              id, company_id, branch_id, warehouse_id, customer_id,
              invoice_number, invoice_date, subtotal, tax_total, discount_total, grand_total, paid_total,
              status, payment_status, currency_code, exchange_rate, price_level,
              salesman_id, reference_note, notes, created_by_user_id
            ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?, ?, ?, ?, ?, 'POSTED', ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
            newInvoiceId,
            companyId,
            _selectedBranchId,
            _selectedWarehouseId,
            _selectedCustomerId,
            _invoiceNumber,
            _subtotalCents,
            _taxCents,
            _discountCents,
            _grandTotalCents,
            _actualPaidCents,
            paymentStatus,
            _currencyCode,
            _exchangeRate,
            _priceLevel,
            _selectedSalesmanId,
            _referenceCtrl.text.trim(),
            _notesCtrl.text.trim(),
            userId,
          ]);

          // 2. Insert items & update warehouse balances
          for (final r in validRows) {
            final itemId = 'sii_${uuid.v4()}';
            tx.execute('''
              INSERT INTO sales_invoice_items (
                id, invoice_id, product_id, quantity, bonus_quantity, unit_id,
                unit_price, cost_price, discount_amount, tax_rate, tax_amount, line_total,
                unit_type, units_per_pack, batch_number, expiry_date, unit_name
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 15, ?, ?, ?, ?, ?, ?, ?)
            ''', [
              itemId,
              newInvoiceId,
              r.productId,
              r.quantity,
              r.bonusQuantity,
              r.unitId,
              r.unitPriceCents,
              r.costPriceCents,
              r.discountCents,
              r.lineTaxCents,
              r.lineTotalCents,
              r.isCarton ? 'CARTON' : 'PIECE',
              r.isCarton ? r.unitsPerCarton : 1,
              r.batchNumber,
              r.expiryDate,
              r.unitName,
            ]);

            // Deduct stock
            tx.execute('''
              UPDATE inventory_balances 
              SET quantity = quantity - ?, updated_at = datetime('now')
              WHERE warehouse_id = ? AND product_id = ?
            ''', [r.inventoryPieces, _selectedWarehouseId, r.productId]);

            // Stock movement
            tx.execute('''
              INSERT INTO inventory_movements (
                id, company_id, warehouse_id, product_id, movement_type,
                quantity, unit_cost, total_cost, reference_document_type, reference_document_id,
                created_by_user_id
              ) VALUES (?, ?, ?, ?, 'SALE_ISSUE', ?, ?, ?, 'SALES_INVOICE', ?, ?)
            ''', [
              'mov_${uuid.v4()}',
              companyId,
              _selectedWarehouseId,
              r.productId,
              -r.inventoryPieces,
              r.costPriceCents,
              r.costPriceCents * r.inventoryPieces,
              newInvoiceId,
              userId,
            ]);
          }

          // 3. Payment record
          if (_actualPaidCents > 0) {
            tx.execute('''
              INSERT INTO payments (
                id, company_id, branch_id, document_type, document_id,
                payment_method, amount, created_by_user_id
              ) VALUES (?, ?, ?, 'SALES_INVOICE', ?, ?, ?, ?)
            ''', [
              'pay_${uuid.v4()}',
              companyId,
              _selectedBranchId,
              newInvoiceId,
              _paymentMethod,
              _actualPaidCents,
              userId,
            ]);
          }

          // 4. Update Customer Balance if balance due
          if (_balanceDueCents > 0 && _selectedCustomerId != null) {
            tx.execute('''
              UPDATE customers 
              SET current_balance = current_balance + ?, updated_at = datetime('now')
              WHERE id = ?
            ''', [_balanceDueCents, _selectedCustomerId]);
          }

          // 5. Audit Log
          tx.execute('''
            INSERT INTO audit_logs (
              id, company_id, branch_id, user_id, device_id,
              action, entity_name, entity_id, new_state
            ) VALUES (?, ?, ?, ?, 'DESKTOP_ERP', 'POST_SALE', 'SALES_INVOICE', ?, ?)
          ''', [
            'aud_${uuid.v4()}',
            companyId,
            _selectedBranchId,
            userId,
            newInvoiceId,
            'فاتورة: $_invoiceNumber, الإجمالي: ${_grandTotalCents / 100} $_currencyCode, العميل: ${_currentCustomer?.name ?? ''}',
          ]);
        });

        // 6. Post double-entry accounting journal
        try {
          final totalCost = validRows.fold(0, (sum, r) => sum + (r.costPriceCents * r.quantity));
          ref.read(accountingRepositoryProvider).postSalesInvoiceJournal(
            companyId: companyId,
            branchId: _selectedBranchId!,
            userId: userId,
            invoiceId: newInvoiceId,
            invoiceNumber: _invoiceNumber,
            invoiceDate: _invoiceDate,
            subtotalCents: _subtotalCents,
            taxCents: _taxCents,
            grandTotalCents: _grandTotalCents,
            totalCostCents: totalCost,
            isCash: _balanceDueCents == 0,
          );
        } catch (_) {}

        _showSnack('تم حفظ وترحيل الفاتورة $_invoiceNumber بنجاح!');

        // 7. Auto print if enabled
        if (_printAfterSave || _directPrint) {
          _printInvoiceReceipt(newInvoiceId, _invoiceNumber);
        }

        // Add to navigation list & refresh
        _allInvoiceIds.add(newInvoiceId);
        _resetToNewInvoice();
      }
    } catch (e) {
      _showSnack('حدث خطأ أثناء الحفظ: $e', isError: true);
    }
  }

  /// "تعديل" Button: Validates policy and enters edit mode
  Future<void> _handleEditInvoice() async {
    if (_loadedInvoiceId == null) {
      _showSnack('يرجى تحميل أو تحديد فاتورة سابقة أولاً لتعديلها', isError: true);
      return;
    }

    final salesRepo = ref.read(salesInvoiceRepositoryProvider);
    final invoice = salesRepo.getInvoiceById(_loadedInvoiceId!);
    if (invoice == null) return;

    final userRole = 'CASHIER'; // Evaluated dynamically or overridden
    final check = salesRepo.checkEditOrVoidPolicy(invoice: invoice, userRole: userRole);

    if (check.allowed) {
      setState(() {
        _isEditingExisting = true;
      });
      _showSnack('تم تفعيل وضع التعديل للفاتورة ${invoice.invoiceNumber}. قم بالتعديلات ثم اضغط حفظ.');
      return;
    }

    // If requires admin password, show prompt
    if (check.requiresAdminPassword) {
      final overrideGranted = await _showAdminPasswordPrompt(check.reason);
      if (overrideGranted) {
        setState(() {
          _isEditingExisting = true;
        });
        _showSnack('تم اعتماد إذن المشرف وتفعيل التعديل للفاتورة ${invoice.invoiceNumber}.');
      }
    } else {
      _showSnack(check.reason, isError: true);
    }
  }

  /// "تراجع / إلغاء" Button: Voids invoice with inventory and ledger reversal
  Future<void> _handleVoidInvoice() async {
    if (_loadedInvoiceId == null) {
      _showSnack('يرجى تحديد فاتورة سابقة أولاً لإلغائها والتراجع عنها', isError: true);
      return;
    }

    final salesRepo = ref.read(salesInvoiceRepositoryProvider);
    final invoice = salesRepo.getInvoiceById(_loadedInvoiceId!);
    if (invoice == null) return;

    if (invoice.isVoided) {
      _showSnack('هذه الفاتورة ملغاة مسبقاً!', isError: true);
      return;
    }

    final check = salesRepo.checkEditOrVoidPolicy(invoice: invoice, userRole: 'CASHIER');
    if (!check.allowed && check.requiresAdminPassword) {
      final overrideGranted = await _showAdminPasswordPrompt(check.reason);
      if (!overrideGranted) return;
    } else if (!check.allowed) {
      _showSnack(check.reason, isError: true);
      return;
    }

    if (!mounted) return;

    // Ask for cancellation reason
    final reasonCtrl = TextEditingController(text: 'خطأ في الأصناف / إرجاع');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تأكيد إلغاء وتراجع الفاتورة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل أنت متأكد من إلغاء الفاتورة ${invoice.invoiceNumber}؟'),
            const SizedBox(height: 8),
            const Text(
              'سيتم إعادة كميات الأصناف للمخزن وعكس رصيد العميل وإنشاء قيد محاسبي عكسي تلقائياً.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء والتراجع'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonCtrl.text.trim().isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      final userId = db.select('SELECT id FROM users LIMIT 1').first['id'] as String;

      try {
        salesRepo.voidSalesInvoice(
          invoiceId: _loadedInvoiceId!,
          userId: userId,
          reason: reasonCtrl.text.trim(),
        );
        _showSnack('تم إلغاء الفاتورة ${invoice.invoiceNumber} وعكس المخزون والقيود المحاسبية بنجاح.');
        _loadInvoiceById(_loadedInvoiceId!);
      } catch (e) {
        _showSnack('خطأ أثناء إلغاء الفاتورة: $e', isError: true);
      }
    }
  }

  /// Search past invoices dialog
  Future<void> _handleSearchInvoices() async {
    final db = ref.read(databaseServiceProvider);
    final compResult = db.select('SELECT id FROM companies LIMIT 1');
    if (compResult.isEmpty) return;
    final companyId = compResult.first['id'] as String;
    final salesRepo = ref.read(salesInvoiceRepositoryProvider);

    final invoices = salesRepo.getInvoices(companyId, limit: 100);

    final selected = await showDialog<SalesInvoiceDetail>(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setDState) {
            final filtered = invoices.where((i) {
              return i.invoiceNumber.toLowerCase().contains(query.toLowerCase()) ||
                  i.customerName.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('البحث في فواتير المبيعات السابقة'),
              content: SizedBox(
                width: 700,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ابحث برقم الفاتورة أو اسم العميل...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setDState(() => query = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد نتائج مطابقة'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final inv = filtered[idx];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: inv.isVoided
                                        ? AppColors.danger.withValues(alpha: 0.15)
                                        : AppColors.success.withValues(alpha: 0.15),
                                    child: Icon(
                                      inv.isVoided ? Icons.cancel : Icons.receipt,
                                      color: inv.isVoided ? AppColors.danger : AppColors.success,
                                    ),
                                  ),
                                  title: Text(
                                    '${inv.invoiceNumber} — ${inv.customerName}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: inv.isVoided ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${DateFormat('yyyy/MM/dd HH:mm').format(inv.invoiceDate)} | الحالة: ${inv.status}',
                                  ),
                                  trailing: Text(
                                    '${(inv.grandTotalCents / 100).toStringAsFixed(2)} ${inv.currencyCode}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  onTap: () => Navigator.pop(ctx, inv),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      _loadInvoiceById(selected.id);
    }
  }

  void _loadInvoiceById(String invoiceId) {
    final salesRepo = ref.read(salesInvoiceRepositoryProvider);
    final inv = salesRepo.getInvoiceById(invoiceId);
    if (inv == null) return;

    setState(() {
      _loadedInvoiceId = inv.id;
      _invoiceNumber = inv.invoiceNumber;
      _invoiceDate = inv.invoiceDate;
      _selectedBranchId = inv.branchId;
      _selectedWarehouseId = inv.warehouseId;
      _selectedCustomerId = inv.customerId;
      _selectedSalesmanId = inv.salesmanId;
      _currencyCode = inv.currencyCode;
      _exchangeRate = inv.exchangeRate;
      _priceLevel = inv.priceLevel;
      _referenceCtrl.text = inv.referenceNote ?? '';
      _notesCtrl.text = inv.notes ?? '';
      _paidCtrl.text = (inv.paidTotalCents / 100).toStringAsFixed(2);
      _paymentMethod = inv.paymentStatus == 'CREDIT' ? 'CREDIT' : 'CASH';
      _isEditingExisting = false;
      _isExistingVoided = inv.isVoided;

      _rows.clear();
      for (final item in inv.items) {
        _rows.add(StandardPosItemRow(
          productId: item.productId,
          barcode: item.productBarcode,
          name: item.productName,
          unitId: item.unitId,
          unitName: item.unitName,
          quantity: item.quantity,
          bonusQuantity: item.bonusQuantity,
          unitPriceCents: item.unitPriceCents,
          costPriceCents: item.costPriceCents,
          discountCents: item.discountAmountCents,
          batchNumber: item.batchNumber,
          expiryDate: item.expiryDate,
          warehouseStock: item.currentWarehouseStock,
          isCarton: item.unitType == 'CARTON',
          unitsPerCarton: item.unitsPerPack,
        ));
      }

      // Update navigation index
      _currentInvoiceIndex = _allInvoiceIds.indexOf(invoiceId);
    });
  }

  // Navigation handlers
  void _navigateToFirst() {
    if (_allInvoiceIds.isNotEmpty) _loadInvoiceById(_allInvoiceIds.first);
  }

  void _navigateToPrev() {
    if (_currentInvoiceIndex > 0 && _currentInvoiceIndex - 1 < _allInvoiceIds.length) {
      _loadInvoiceById(_allInvoiceIds[_currentInvoiceIndex - 1]);
    }
  }

  void _navigateToNext() {
    if (_currentInvoiceIndex >= 0 && _currentInvoiceIndex + 1 < _allInvoiceIds.length) {
      _loadInvoiceById(_allInvoiceIds[_currentInvoiceIndex + 1]);
    }
  }

  void _navigateToLast() {
    if (_allInvoiceIds.isNotEmpty) _loadInvoiceById(_allInvoiceIds.last);
  }

  Future<void> _printInvoiceReceipt(String invoiceId, String invoiceNumber) async {
    final db = ref.read(databaseServiceProvider);
    final printerService = ref.read(printerServiceProvider);
    final salesRepo = ref.read(salesInvoiceRepositoryProvider);
    final inv = salesRepo.getInvoiceById(invoiceId);
    if (inv == null) return;

    final compResult = db.select('SELECT trade_name, legal_name, tax_number, commercial_registration FROM companies WHERE id = ? LIMIT 1', [inv.companyId]);
    final compRow = compResult.isNotEmpty ? compResult.first : <String, dynamic>{};
    final brResult = db.select('SELECT name FROM branches WHERE id = ? LIMIT 1', [inv.branchId]);
    final brName = brResult.isNotEmpty ? (brResult.first['name'] as String) : 'الفرع الرئيسي';

    final header = InvoiceHeaderDto(
      companyName: (compRow['trade_name'] ?? compRow['legal_name'] ?? 'ALFA SOFT') as String,
      taxNumber: (compRow['tax_number'] ?? '300000000000003') as String,
      crNumber: (compRow['commercial_registration'] ?? '1010000000') as String,
      branchName: brName,
      invoiceNumber: inv.invoiceNumber,
      invoiceDate: inv.invoiceDate,
      customerName: inv.customerName,
      subtotal: inv.subtotalCents / 100.0,
      taxTotal: inv.taxTotalCents / 100.0,
      grandTotal: inv.grandTotalCents / 100.0,
      paymentMethod: inv.paymentStatus == 'CREDIT' ? 'آجل' : 'نقداً',
    );

    final items = inv.items.map((i) {
      final lineTax = BankersRounding.toMinorUnits((i.lineTotalCents / 100.0) * 0.15, scale: 2);
      return InvoiceItemDto(
        productName: i.bonusQuantity > 0 ? '${i.productName} (+${i.bonusQuantity} بونص)' : i.productName,
        sku: i.productBarcode.isNotEmpty ? i.productBarcode : i.productId,
        quantity: i.quantity,
        unitName: i.unitName,
        unitPrice: i.unitPriceCents / 100.0,
        taxAmount: lineTax / 100.0,
        lineTotal: (i.lineTotalCents + lineTax) / 100.0,
      );
    }).toList();

    try {
      await printerService.printInvoice(
        header: header,
        items: items,
      );
    } catch (e) {
      debugPrint('Error printing receipt: $e');
    }
  }

  Future<bool> _showAdminPasswordPrompt(String reason) async {
    final pwdCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.admin_panel_settings, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('موافقة المشرف مطلوبة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة مرور المشرف (Admin Password) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final pwd = pwdCtrl.text.trim();
              if (pwd == 'admin123' || pwd == '123456') {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمة المرور غير صحيحة!'), backgroundColor: AppColors.danger),
                );
              }
            },
            child: const Text('تأكيد الصلاحية'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // -------------------------------------------------------------
  // BUILD UI
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEBEFF2),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Top Ribbon & Actions
            _buildTopActionBar(),

            // Status Banner if voided
            if (_isExistingVoided)
              Container(
                width: double.infinity,
                color: AppColors.danger,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Center(
                  child: Text(
                    '⚠️ هذه الفاتورة ملغاة مسبقاً (VOIDED) — تم عكس المخزون والقيود المحاسبية الخاصة بها',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),

            // Header Form
            _buildHeaderForm(),

            // Tabs Bar & Content
            _buildTabBar(),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildItemsDataGrid(),
                  _buildLiveAccountingTab(),
                  _buildAdditionalInfoTab(),
                ],
              ),
            ),

            // Footer Totals Bar
            _buildFooterTotalsBar(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // WIDGET: TOP ACTION BAR (Exact Ribbon match to photo)
  // -------------------------------------------------------------
  Widget _buildTopActionBar() {
    return Container(
      height: 48,
      color: const Color(0xFF404040),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // "جديد" Red/Orange Button
          ElevatedButton.icon(
            onPressed: _resetToNewInvoice,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE64A19),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(width: 4),

          // "حفظ" (Checkout/Payment Save)
          _buildActionButton(
            label: _isEditingExisting ? 'حفظ التعديل' : 'حفظ (الدفع)',
            icon: Icons.save_rounded,
            onTap: _isExistingVoided ? null : _handleSaveInvoice,
            bgColor: const Color(0xFF4CAF50),
          ),
          const SizedBox(width: 4),

          // "تعديل"
          _buildActionButton(
            label: 'تعديل',
            icon: Icons.edit_note_rounded,
            onTap: (_loadedInvoiceId != null && !_isExistingVoided) ? _handleEditInvoice : null,
          ),
          const SizedBox(width: 4),

          // "تراجع / إلغاء"
          _buildActionButton(
            label: 'إلغاء وتراجع',
            icon: Icons.undo_rounded,
            onTap: (_loadedInvoiceId != null && !_isExistingVoided) ? _handleVoidInvoice : null,
            bgColor: const Color(0xFFD32F2F),
          ),
          const SizedBox(width: 4),

          // "طباعة"
          _buildActionButton(
            label: 'طباعة',
            icon: Icons.print_rounded,
            onTap: () {
              if (_loadedInvoiceId != null) {
                _printInvoiceReceipt(_loadedInvoiceId!, _invoiceNumber);
              } else {
                _showSnack('يرجى حفظ الفاتورة أولاً لطباعتها', isError: true);
              }
            },
          ),
          const SizedBox(width: 4),

          // "بحث" (Blue)
          _buildActionButton(
            label: 'بحث',
            icon: Icons.search_rounded,
            onTap: _handleSearchInvoices,
            bgColor: const Color(0xFF1976D2),
          ),
          const SizedBox(width: 8),

          // Navigation Controls: |< , < , 1 من N , > , >|
          IconButton(
            onPressed: _navigateToFirst,
            icon: const Icon(Icons.first_page, color: Colors.white, size: 20),
            tooltip: 'الأولى',
          ),
          IconButton(
            onPressed: _navigateToPrev,
            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            tooltip: 'السابقة',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            child: Text(
              '${_currentInvoiceIndex >= 0 && _currentInvoiceIndex < _allInvoiceIds.length ? _currentInvoiceIndex + 1 : _allInvoiceIds.length} من ${_allInvoiceIds.length}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: _navigateToNext,
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
            tooltip: 'التالية',
          ),
          IconButton(
            onPressed: _navigateToLast,
            icon: const Icon(Icons.last_page, color: Colors.white, size: 20),
            tooltip: 'الأخيرة',
          ),

          const Spacer(),

          // Interface Switcher Button (Switch to Quick POS)
          OutlinedButton.icon(
            onPressed: () {
              ref.read(posInterfaceStyleProvider.notifier).setStyle('QUICK');
            },
            icon: const Icon(Icons.touch_app_rounded, size: 16, color: Colors.amberAccent),
            label: const Text(
              'التبديل إلى الكاشير السريع (Touch)',
              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.amberAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),

          // "إغلاق" Red Button
          ElevatedButton.icon(
            onPressed: widget.onExit,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    Color? bgColor,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor ?? const Color(0xFF616161),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade700,
        disabledForegroundColor: Colors.white38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  // -------------------------------------------------------------
  // WIDGET: HEADER FORM
  // -------------------------------------------------------------
  Widget _buildHeaderForm() {
    return Container(
      color: const Color(0xFFDCE2E6),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Row 1: Branch, Invoice Type, Warehouse, Price Category, Currency, Exchange Rate
          Row(
            children: [
              // Branch
              _buildFormDropdown<String>(
                label: 'الفرع',
                value: _selectedBranchId,
                items: _branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedBranchId = val;
                      final orgRepo = OrganizationRepository(ref.read(databaseServiceProvider));
                      _warehouses = orgRepo.getWarehouses(val);
                      if (_warehouses.isNotEmpty) _selectedWarehouseId = _warehouses.first.id;
                    });
                  }
                },
                width: 150,
              ),
              const SizedBox(width: 8),

              // Invoice Type Title
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('فاتورة مبيعات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 8),

              // Warehouse
              _buildFormDropdown<String>(
                label: 'المخزن',
                value: _selectedWarehouseId,
                items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedWarehouseId = val);
                },
                width: 150,
              ),
              const SizedBox(width: 8),

              // Price Category
              _buildFormDropdown<String>(
                label: 'التسعيرة',
                value: _priceLevel,
                items: const [
                  DropdownMenuItem(value: 'RETAIL', child: Text('سعر تجزئة')),
                  DropdownMenuItem(value: 'WHOLESALE', child: Text('سعر جملة')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _priceLevel = val;
                      // Refresh item prices according to price level
                      for (final r in _rows) {
                        try {
                          final prod = _products.firstWhere((p) => p.id == r.productId);
                          r.unitPriceCents = (_priceLevel == 'WHOLESALE' && prod.minSalePriceCents > 0)
                              ? prod.minSalePriceCents
                              : prod.salePriceCents;
                        } catch (_) {}
                      }
                    });
                  }
                },
                width: 130,
              ),
              const SizedBox(width: 8),

              // Currency
              _buildFormDropdown<String>(
                label: 'العملة',
                value: _currencyCode,
                items: const [
                  DropdownMenuItem(value: 'YER', child: Text('ريال يمني')),
                  DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _currencyCode = val);
                },
                width: 130,
              ),
              const SizedBox(width: 8),

              // Exchange Rate
              _buildFormInput(
                label: 'سعر الصرف',
                value: _exchangeRate.toStringAsFixed(5),
                onChanged: (val) => _exchangeRate = double.tryParse(val) ?? 1.0,
                width: 90,
              ),

              const Spacer(),

              // Quick Checkboxes
              _buildHeaderCheckbox('تكرار الصنف', _repeatItem, (v) => setState(() => _repeatItem = v!)),
              _buildHeaderCheckbox('سطر جديد', _autoNewLine, (v) => setState(() => _autoNewLine = v!)),
              _buildHeaderCheckbox('تنقل أسفل', _moveDown, (v) => setState(() => _moveDown = v!)),
              _buildHeaderCheckbox('طباعة مباشرة', _directPrint, (v) => setState(() => _directPrint = v!)),
              _buildHeaderCheckbox('طباعة بعد الحفظ', _printAfterSave, (v) => setState(() => _printAfterSave = v!)),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Payment Method, Customer, Balance, Sales Rep, Invoice #, Date, Reference, Statement
          Row(
            children: [
              // Payment Method
              _buildFormDropdown<String>(
                label: 'طريقة الدفع',
                value: _paymentMethod,
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('نقد')),
                  DropdownMenuItem(value: 'CREDIT', child: Text('آجل')),
                  DropdownMenuItem(value: 'BANK', child: Text('بنك / شبكة')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _paymentMethod = val);
                },
                width: 120,
              ),
              const SizedBox(width: 8),

              // Customer Selection
              _buildFormDropdown<String>(
                label: 'اسم العميل',
                value: _selectedCustomerId,
                items: _customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCustomerId = val);
                },
                width: 200,
              ),
              const SizedBox(width: 8),

              // Customer Balance Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('رصيد العميل الحالي', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      '${((_currentCustomer?.currentBalance ?? 0) / 100).toStringAsFixed(2)} $_currencyCode',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: (_currentCustomer?.currentBalance ?? 0) > 0 ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Sales Rep
              _buildFormDropdown<String>(
                label: 'المندوب',
                value: _selectedSalesmanId,
                items: _salesmen.map((u) {
                  return DropdownMenuItem(value: u['id'] as String, child: Text(u['full_name'] as String));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedSalesmanId = val);
                },
                width: 130,
              ),
              const SizedBox(width: 8),

              // Invoice Number
              _buildFormInput(
                label: 'رقم الفاتورة',
                value: _invoiceNumber,
                readOnly: true,
                width: 120,
              ),
              const SizedBox(width: 8),

              // Date
              _buildFormInput(
                label: 'التاريخ',
                value: DateFormat('yyyy/MM/dd').format(_invoiceDate),
                readOnly: true,
                width: 100,
              ),
              const SizedBox(width: 8),

              // Reference
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _referenceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المرجع',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Notes / Statement
              Expanded(
                child: TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'البيان / ملاحظات',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFormInput({
    required String label,
    required String value,
    ValueChanged<String>? onChanged,
    bool readOnly = false,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: value,
        readOnly: readOnly,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: readOnly ? Colors.grey.shade200 : Colors.white,
        ),
      ),
    );
  }

  Widget _buildHeaderCheckbox(String title, bool val, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: val,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
      ],
    );
  }

  // -------------------------------------------------------------
  // WIDGET: TAB BAR
  // -------------------------------------------------------------
  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFFC9D2D9),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.black54,
        indicatorColor: const Color(0xFF1976D2),
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'تفاصيل الأصناف'),
          Tab(text: 'القيود المحاسبية'),
          Tab(text: 'بيانات إضافية'),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: ITEMS DATA GRID (Direct match to Yemen ERP Grid)
  // -------------------------------------------------------------
  Widget _buildItemsDataGrid() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Table Headers
          Container(
            color: const Color(0xFFD6DFE6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: const [
                SizedBox(width: 35, child: Text('م', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 140, child: Text('رقم الباركود', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('اسم الصنف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 70, child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 60, child: Text('المجان', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('سعر البيع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 100, child: Text('إجمالي السعر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('م التشغيلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('تاريخ الانتهاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('كمية مخزن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 40, child: Text('', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final isEven = index % 2 == 0;
                return Container(
                  color: isEven ? Colors.white : const Color(0xFFF7F9FA),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(
                    children: [
                      // #
                      SizedBox(width: 35, child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),

                      // Barcode
                      SizedBox(
                        width: 140,
                        child: TextFormField(
                          key: ValueKey('barcode_${row.productId}_$index'),
                          initialValue: row.barcode,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onFieldSubmitted: (barcodeVal) {
                            _lookupAndAssignBarcode(index, barcodeVal);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Product Autocomplete / Dropdown
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: row.productId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          items: _products.map((p) {
                            return DropdownMenuItem(value: p.id, child: Text(p.nameAr, overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: (newProdId) {
                            if (newProdId != null) {
                              _assignProductToRow(index, newProdId);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Unit Dropdown
                      SizedBox(
                        width: 90,
                        child: DropdownButtonFormField<String>(
                          initialValue: row.unitName,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          items: _availableUnits.map((u) {
                            return DropdownMenuItem(value: u.name, child: Text(u.name, style: const TextStyle(fontSize: 11)));
                          }).toList(),
                          onChanged: (unitVal) {
                            if (unitVal != null) {
                              setState(() {
                                row.unitName = unitVal;
                                row.isCarton = unitVal == 'كرتون';
                                try {
                                  final prod = _products.firstWhere((p) => p.id == row.productId);
                                  if (row.isCarton && prod.cartonPriceCents > 0) {
                                    row.unitPriceCents = prod.cartonPriceCents;
                                  } else {
                                    row.unitPriceCents = (_priceLevel == 'WHOLESALE' && prod.minSalePriceCents > 0)
                                        ? prod.minSalePriceCents
                                        : prod.salePriceCents;
                                  }
                                } catch (_) {}
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Quantity
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          key: ValueKey('qty_${row.productId}_$index'),
                          initialValue: row.quantity.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            setState(() {
                              row.quantity = int.tryParse(val) ?? 1;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Bonus Qty (المجان)
                      SizedBox(
                        width: 60,
                        child: TextFormField(
                          key: ValueKey('bonus_${row.productId}_$index'),
                          initialValue: row.bonusQuantity.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            setState(() {
                              row.bonusQuantity = int.tryParse(val) ?? 0;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Unit Price
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          key: ValueKey('price_${row.productId}_$index'),
                          initialValue: (row.unitPriceCents / 100).toStringAsFixed(2),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val) ?? 0;
                            setState(() {
                              row.unitPriceCents = (parsed * 100).round();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Line Total (Display)
                      Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          (row.lineTotalCents / 100).toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Batch Number (رقم التشغيلة)
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          key: ValueKey('batch_${row.productId}_$index'),
                          initialValue: row.batchNumber ?? '',
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => row.batchNumber = val,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Expiry Date (تاريخ الانتهاء)
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          key: ValueKey('exp_${row.productId}_$index'),
                          initialValue: row.expiryDate ?? '',
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'yyyy/MM/dd',
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => row.expiryDate = val,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Available Stock (كمية المخزن)
                      Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Text(
                          '${row.warehouseStock}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: row.warehouseStock <= 5 ? AppColors.danger : AppColors.success,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Delete Row
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                          onPressed: () {
                            if (_rows.length > 1) {
                              setState(() => _rows.removeAt(index));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Bar for Adding Rows
          Container(
            color: const Color(0xFFECEFF1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => _addNewBlankRow()),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('إضافة سطر صنف جديد (F7)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 12),
                Text('عدد الأصناف في الفاتورة: ${_rows.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _lookupAndAssignBarcode(int rowIndex, String barcode) {
    try {
      final product = _products.firstWhere(
        (p) => p.sku == barcode.trim() || (p.cartonBarcode != null && p.cartonBarcode == barcode.trim()),
      );
      _assignProductToRow(rowIndex, product.id, barcodeScanned: barcode.trim());
    } catch (_) {
      _showSnack('لم يتم العثور على صنف بالباركود: $barcode', isError: true);
    }
  }

  void _assignProductToRow(int rowIndex, String productId, {String? barcodeScanned}) {
    final prod = _products.firstWhere((p) => p.id == productId);
    final stock = _getWarehouseStock(productId);
    final isCartonScan = barcodeScanned != null && prod.cartonBarcode == barcodeScanned;

    setState(() {
      final row = _rows[rowIndex];
      row.productId = prod.id;
      row.name = prod.nameAr;
      row.barcode = barcodeScanned ?? prod.sku;
      row.warehouseStock = stock;
      row.costPriceCents = prod.costPriceCents;
      row.isCarton = isCartonScan;
      row.unitsPerCarton = prod.unitsPerCarton;
      row.unitName = isCartonScan ? 'كرتون' : 'حبة';

      if (isCartonScan && prod.cartonPriceCents > 0) {
        row.unitPriceCents = prod.cartonPriceCents;
      } else {
        row.unitPriceCents = (_priceLevel == 'WHOLESALE' && prod.minSalePriceCents > 0)
            ? prod.minSalePriceCents
            : prod.salePriceCents;
      }

      if (_autoNewLine && rowIndex == _rows.length - 1) {
        _addNewBlankRow();
      }
    });
  }

  // -------------------------------------------------------------
  // TAB 2: LIVE ACCOUNTING PREVIEW (Double-Entry Journal)
  // -------------------------------------------------------------
  Widget _buildLiveAccountingTab() {
    final totalCost = _rows.fold(0, (sum, r) => sum + (r.costPriceCents * r.quantity));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.balance, color: AppColors.brandPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'معاينة القيد المحاسبي المزدوج الآلي للفاتورة ($_invoiceNumber)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Chip(
                    label: Text(_balanceDueCents == 0 ? 'قيد مبيعات نقدية' : 'قيد مبيعات آجلة'),
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(2.5),
                  2: FlexColumnWidth(1.2),
                  3: FlexColumnWidth(1.2),
                  4: FlexColumnWidth(2.0),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    children: const [
                      Padding(padding: EdgeInsets.all(8), child: Text('كود الحساب', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('اسم الحساب المحاسبي', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('مدين (Debit)', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('دائن (Credit)', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('البيان المالي', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  // Debit Cash or AR
                  TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(_balanceDueCents == 0 ? '1010' : '1100')),
                      Padding(padding: const EdgeInsets.all(8), child: Text(_balanceDueCents == 0 ? 'الخزينة النقدية الرئيسية' : 'العملاء والمدينون (${_currentCustomer?.name})')),
                      Padding(padding: const EdgeInsets.all(8), child: Text((_grandTotalCents / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                      const Padding(padding: EdgeInsets.all(8), child: Text('-')),
                      Padding(padding: const EdgeInsets.all(8), child: Text('إجمالي قيمة الفاتورة $_invoiceNumber')),
                    ],
                  ),
                  // Credit Sales Revenue
                  TableRow(
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('4010')),
                      const Padding(padding: EdgeInsets.all(8), child: Text('إيرادات المبيعات')),
                      const Padding(padding: EdgeInsets.all(8), child: Text('-')),
                      Padding(padding: const EdgeInsets.all(8), child: Text((_subtotalCents / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: const EdgeInsets.all(8), child: Text('صافي مبيعات الفاتورة $_invoiceNumber')),
                    ],
                  ),
                  // Credit VAT Output Payable
                  if (_taxCents > 0)
                    TableRow(
                      children: [
                        const Padding(padding: EdgeInsets.all(8), child: Text('2020')),
                        const Padding(padding: EdgeInsets.all(8), child: Text('ضريبة القيمة المضافة المستحقة (15%)')),
                        const Padding(padding: EdgeInsets.all(8), child: Text('-')),
                        Padding(padding: const EdgeInsets.all(8), child: Text((_taxCents / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('ضريبة المبيعات للفاتورة $_invoiceNumber')),
                      ],
                    ),
                  // COGS & Inventory
                  if (totalCost > 0) ...[
                    TableRow(
                      children: [
                        const Padding(padding: EdgeInsets.all(8), child: Text('5010')),
                        const Padding(padding: EdgeInsets.all(8), child: Text('تكلفة البضاعة المباعة (COGS)')),
                        Padding(padding: const EdgeInsets.all(8), child: Text((totalCost / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Padding(padding: EdgeInsets.all(8), child: Text('-')),
                        Padding(padding: const EdgeInsets.all(8), child: Text('تكلفة الأصناف المباعة $_invoiceNumber')),
                      ],
                    ),
                    TableRow(
                      children: [
                        const Padding(padding: EdgeInsets.all(8), child: Text('1200')),
                        const Padding(padding: EdgeInsets.all(8), child: Text('مخزون البضائع')),
                        const Padding(padding: EdgeInsets.all(8), child: Text('-')),
                        Padding(padding: const EdgeInsets.all(8), child: Text((totalCost / 100).toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('صرف بضاعة من المخزن للفاتورة $_invoiceNumber')),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: ADDITIONAL INFO TAB
  // -------------------------------------------------------------
  Widget _buildAdditionalInfoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('شروط وأحكام الفاتورة وبيانات الشحن والمندوب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'اسم السائق / الناقل', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'رقم لوحة المركبة', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'شروط الدفع والضمان',
                  hintText: 'البضاعة المباعة ترد وتستبدل خلال المدة المحددة بموجب أصل الفاتورة...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // WIDGET: FOOTER TOTALS BAR
  // -------------------------------------------------------------
  Widget _buildFooterTotalsBar() {
    return Container(
      color: const Color(0xFF263238),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Subtotal
          _buildTotalCard('الإجمالي قبل الضريبة', '${(_subtotalCents / 100).toStringAsFixed(2)} $_currencyCode'),
          const SizedBox(width: 12),

          // Discount
          _buildTotalCard('الخصم', '${(_discountCents / 100).toStringAsFixed(2)} $_currencyCode'),
          const SizedBox(width: 12),

          // VAT
          _buildTotalCard('ضريبة القيمة المضافة (15%)', '${(_taxCents / 100).toStringAsFixed(2)} $_currencyCode'),
          const SizedBox(width: 12),

          // Net Total
          _buildTotalCard(
            'الإجمالي الصافي',
            '${(_grandTotalCents / 100).toStringAsFixed(2)} $_currencyCode',
            isHighlight: true,
          ),
          const SizedBox(width: 12),

          // Paid Field
          SizedBox(
            width: 140,
            child: TextField(
              controller: _paidCtrl,
              enabled: _paymentMethod == 'CREDIT',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'المدفوع نقداً',
                labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
                hintText: _paymentMethod == 'CREDIT' ? 'مقدم نقدي' : (_grandTotalCents / 100).toStringAsFixed(2),
                hintStyle: const TextStyle(color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: Colors.white10,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),

          // Balance Due
          _buildTotalCard(
            'المتبقي (آجل)',
            '${(_balanceDueCents / 100).toStringAsFixed(2)} $_currencyCode',
            textColor: _balanceDueCents > 0 ? Colors.amberAccent : Colors.lightGreenAccent,
          ),

          const Spacer(),

          // Big Checkout / Save Button
          ElevatedButton.icon(
            onPressed: _isExistingVoided ? null : _handleSaveInvoice,
            icon: const Icon(Icons.check_circle_rounded, size: 22),
            label: Text(
              _isEditingExisting ? 'حفظ التعديل' : 'حفظ الفاتورة (F10)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE64A19),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(String title, String value, {bool isHighlight = false, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFF1B5E20) : Colors.black26,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isHighlight ? Colors.greenAccent : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
              color: textColor ?? (isHighlight ? Colors.white : Colors.white),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
