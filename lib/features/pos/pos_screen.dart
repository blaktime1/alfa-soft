import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/math/bankers_rounding.dart';
import '../../core/math/vat_calculator.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_colors.dart';

class CartItem {
  final String productId;
  final String name;
  final String sku;
  final int unitPriceCents;
  final int costPriceCents;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unitPriceCents,
    required this.costPriceCents,
    this.quantity = 1,
  });

  int get totalCents => unitPriceCents * quantity;
}

class PosScreen extends ConsumerStatefulWidget {
  final VoidCallback onExit;

  const PosScreen({super.key, required this.onExit});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _barcodeFocusNode = FocusNode();
  final _barcodeController = TextEditingController();

  final List<CartItem> _cart = [];
  List<Map<String, dynamic>> _quickProducts = [];
  bool _isProcessing = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _loadSampleProductsIfEmpty();
    _loadCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeFocusNode.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  void _loadSampleProductsIfEmpty() {
    final db = ref.read(databaseServiceProvider);
    final count = db.select('SELECT COUNT(*) as cnt FROM products').first['cnt'] as int;

    if (count == 0) {
      final companyId = db.select('SELECT id FROM companies LIMIT 1').first['id'] as String;
      // Add default unit
      db.execute('''
        INSERT OR IGNORE INTO units (id, company_id, code, name)
        VALUES ('unit_pcs', ?, 'PCS', 'حبة / قطعة')
      ''', [companyId]);

      // Seed core initial products
      final sampleItems = [
        ['prod_1', '1001', 'مياه معدنية 500 مل', 150, 80],
        ['prod_2', '1002', 'حليب طازج 1 لتر', 600, 450],
        ['prod_3', '1003', 'أرز بسمتي 5 كجم', 4500, 3800],
        ['prod_4', '1004', 'زيت نباتي نقي 1.5 لتر', 1800, 1450],
        ['prod_5', '1005', 'سكر أبيض ناعم 2 كجم', 900, 750],
        ['prod_6', '1006', 'شاي أحمر فرط 400 جم', 1400, 1100],
      ];

      for (final item in sampleItems) {
        db.execute('''
          INSERT INTO products (id, company_id, base_unit_id, sku, barcode, name_ar, sale_price, cost_price, is_active)
          VALUES (?, ?, 'unit_pcs', ?, ?, ?, ?, ?, 1)
        ''', [item[0], companyId, item[1], item[1], item[2], item[3], item[4]]);
      }
    }
  }

  void _loadCatalog() {
    final db = ref.read(databaseServiceProvider);
    final result = db.select('''
      SELECT id, sku, barcode, name_ar, sale_price, cost_price 
      FROM products 
      WHERE is_active = 1 
      LIMIT 20
    ''');
    setState(() {
      _quickProducts = result.map((r) => Map<String, dynamic>.from(r)).toList();
    });
  }

  void _handleBarcodeSubmit(String rawBarcode) {
    final query = rawBarcode.trim();
    if (query.isEmpty) return;

    final db = ref.read(databaseServiceProvider);
    final match = db.select('''
      SELECT id, sku, barcode, name_ar, sale_price, cost_price 
      FROM products 
      WHERE barcode = ? OR sku = ? OR name_ar LIKE ? 
      LIMIT 1
    ''', [query, query, '%$query%']);

    if (match.isNotEmpty) {
      _addItemToCart(match.first);
    } else {
      setState(() => _lastMessage = 'لم يتم العثور على الصنف: $query');
    }

    _barcodeController.clear();
    _barcodeFocusNode.requestFocus();
  }

  void _addItemToCart(Map<String, dynamic> product) {
    setState(() {
      final existingIndex = _cart.indexWhere((i) => i.productId == product['id']);
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity += 1;
      } else {
        _cart.add(CartItem(
          productId: product['id'] as String,
          name: product['name_ar'] as String,
          sku: product['sku'] as String,
          unitPriceCents: product['sale_price'] as int,
          costPriceCents: product['cost_price'] as int,
          quantity: 1,
        ));
      }
      _lastMessage = 'تمت إضافة: ${product['name_ar']}';
    });
  }

  int get _subtotalCents => _cart.fold(0, (sum, i) => sum + i.totalCents);
  int get _taxCents {
    final subtotal = _subtotalCents / 100.0;
    final taxResult = VatCalculator.calculateExclusive(netAmount: subtotal, taxRateBps: 1500);
    return taxResult.taxMinorUnits;
  }
  int get _grandTotalCents => _subtotalCents + _taxCents;

  void _processCashCheckout() {
    if (_cart.isEmpty) return;

    setState(() => _isProcessing = true);
    final db = ref.read(databaseServiceProvider);
    const uuid = Uuid();

    try {
      final companyRow = db.select('SELECT id FROM companies LIMIT 1').first;
      final companyId = companyRow['id'] as String;
      final branchId = db.select('SELECT id FROM branches WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;
      final warehouseId = db.select('SELECT id FROM warehouses WHERE branch_id = ? LIMIT 1', [branchId]).first['id'] as String;
      final userId = db.select('SELECT id FROM users WHERE company_id = ? LIMIT 1', [companyId]).first['id'] as String;

      // Ensure a walk-in customer exists
      final custCheck = db.select('SELECT id FROM customers WHERE company_id = ? AND code = "WALK_IN"', [companyId]);
      final String customerId;
      if (custCheck.isEmpty) {
        customerId = 'cust_${uuid.v4()}';
        db.execute('''
          INSERT INTO customers (id, company_id, code, name, is_active)
          VALUES (?, ?, 'WALK_IN', 'عميل نقدي عابر', 1)
        ''', [customerId, companyId]);
      } else {
        customerId = custCheck.first['id'] as String;
      }

      final invoiceId = 'inv_${uuid.v4()}';
      final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

      db.transaction((tx) {
        // 1. Insert Sales Invoice Header
        tx.execute('''
          INSERT INTO sales_invoices (
            id, company_id, branch_id, warehouse_id, customer_id,
            invoice_number, invoice_date, subtotal, tax_total, grand_total, paid_total,
            status, payment_status, created_by_user_id
          ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?, ?, ?, ?, 'POSTED', 'PAID', ?)
        ''', [
          invoiceId,
          companyId,
          branchId,
          warehouseId,
          customerId,
          invoiceNumber,
          _subtotalCents,
          _taxCents,
          _grandTotalCents,
          _grandTotalCents,
          userId,
        ]);

        // 2. Insert Invoice Items & Inventory Movements
        for (final item in _cart) {
          final itemId = 'item_${uuid.v4()}';
          final lineTax = BankersRounding.toMinorUnits(
              (item.totalCents / 100.0) * 0.15, scale: 2);

          tx.execute('''
            INSERT INTO sales_invoice_items (
              id, invoice_id, product_id, quantity, unit_id,
              unit_price, cost_price, tax_amount, line_total
            ) VALUES (?, ?, ?, ?, 'unit_pcs', ?, ?, ?, ?)
          ''', [
            itemId,
            invoiceId,
            item.productId,
            item.quantity,
            item.unitPriceCents,
            item.costPriceCents,
            lineTax,
            item.totalCents + lineTax,
          ]);

          // Record Inventory Movement (Stock Deduction)
          tx.execute('''
            INSERT INTO inventory_movements (
              id, company_id, warehouse_id, product_id, movement_type,
              quantity, unit_cost, total_cost, reference_document_type, reference_document_id,
              created_by_user_id
            ) VALUES (?, ?, ?, ?, 'SALE_ISSUE', ?, ?, ?, 'SALES_INVOICE', ?, ?)
          ''', [
            'mov_${uuid.v4()}',
            companyId,
            warehouseId,
            item.productId,
            -item.quantity, // Negative for outbound sales
            item.costPriceCents,
            item.costPriceCents * item.quantity,
            invoiceId,
            userId,
          ]);
        }

        // 3. Record Payment
        tx.execute('''
          INSERT INTO payments (
            id, company_id, branch_id, document_type, document_id,
            payment_method, amount, created_by_user_id
          ) VALUES (?, ?, ?, 'SALES_INVOICE', ?, 'CASH', ?, ?)
        ''', [
          'pay_${uuid.v4()}',
          companyId,
          branchId,
          invoiceId,
          _grandTotalCents,
          userId,
        ]);

        // 4. Audit Log
        tx.execute('''
          INSERT INTO audit_logs (
            id, company_id, branch_id, user_id, device_id,
            action, entity_name, entity_id, new_state
          ) VALUES (?, ?, ?, ?, 'DEV_POS_1', 'POST_SALE', 'SALES_INVOICE', ?, ?)
        ''', [
          'aud_${uuid.v4()}',
          companyId,
          branchId,
          userId,
          invoiceId,
          'Invoice: $invoiceNumber, Total: ${_grandTotalCents / 100.0} SAR',
        ]);
      });

      setState(() {
        _cart.clear();
        _isProcessing = false;
        _lastMessage = 'تم اعتماد الفاتورة بنجاح: $invoiceNumber بمبلغ ${(_grandTotalCents / 100.0).toStringAsFixed(2)} SAR';
      });

      _barcodeFocusNode.requestFocus();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _lastMessage = 'فشل اعتماد الفاتورة: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => _barcodeFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f9): _processCashCheckout,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_cart.isNotEmpty) {
            setState(() => _cart.clear());
          } else {
            widget.onExit();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: widget.onExit,
              tooltip: 'العودة للوحة التحكم (Esc)',
            ),
            title: const Text('نقطة البيع السريعة — POS Fullscreen Mode'),
            actions: [
              Chip(
                backgroundColor: AppColors.success.withValues(alpha: 0.15),
                side: BorderSide.none,
                label: const Text('الوردية نشطة: مفتوحة',
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Row(
            children: [
              // Left / Center Section: Barcode Scanner & Cart Items Grid
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Barcode Input
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _barcodeController,
                              focusNode: _barcodeFocusNode,
                              decoration: const InputDecoration(
                                hintText: 'امسح الباركود أو اكتب كود الصنف ثم اضغط Enter (F1)',
                                prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                              ),
                              onSubmitted: _handleBarcodeSubmit,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _handleBarcodeSubmit(_barcodeController.text),
                            icon: const Icon(Icons.add_shopping_cart_rounded),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      if (_lastMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.brandAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_lastMessage!,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Cart Items Table
                      Expanded(
                        child: Card(
                          child: _cart.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shopping_cart_outlined,
                                          size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                                      const SizedBox(height: 12),
                                      Text('السلة فارغة. ابدأ بمسح الباركود أو اختيار صنف',
                                          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _cart.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = _cart[index];
                                    return ListTile(
                                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('SKU: ${item.sku} | السعر: ${(item.unitPriceCents / 100.0).toStringAsFixed(2)} SAR'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle_outline_rounded),
                                            onPressed: () {
                                              setState(() {
                                                if (item.quantity > 1) {
                                                  item.quantity -= 1;
                                                } else {
                                                  _cart.removeAt(index);
                                                }
                                              });
                                            },
                                          ),
                                          Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline_rounded),
                                            onPressed: () {
                                              setState(() => item.quantity += 1);
                                            },
                                          ),
                                          const SizedBox(width: 16),
                                          SizedBox(
                                            width: 90,
                                            child: Text(
                                              '${(item.totalCents / 100.0).toStringAsFixed(2)} SAR',
                                              textAlign: TextAlign.end,
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick Product Tiles
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _quickProducts.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final prod = _quickProducts[index];
                            return InkWell(
                              onTap: () => _addItemToCart(prod),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 140,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  border: Border.all(color: AppColors.lightBorderSubtle),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      prod['name_ar'] as String,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${((prod['sale_price'] as int) / 100.0).toStringAsFixed(2)} SAR',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandAccent, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Right Section: Order Summary & Checkout Panel
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(right: BorderSide(color: theme.dividerColor)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ملخص الفاتورة',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _SummaryRow(label: 'المجموع الفرعي', value: '${(_subtotalCents / 100.0).toStringAsFixed(2)} SAR'),
                    const SizedBox(height: 8),
                    _SummaryRow(label: 'ضريبة القيمة المضافة (15%)', value: '${(_taxCents / 100.0).toStringAsFixed(2)} SAR'),
                    const Divider(height: 32),
                    _SummaryRow(
                      label: 'المجموع الكلي المطلوب',
                      value: '${(_grandTotalCents / 100.0).toStringAsFixed(2)} SAR',
                      isBold: true,
                      highlightColor: AppColors.brandAccent,
                    ),
                    const Spacer(),

                    // Cash Checkout Button (F9)
                    ElevatedButton.icon(
                      onPressed: _cart.isEmpty || _isProcessing ? null : _processCashCheckout,
                      icon: _isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.payments_rounded, size: 24),
                      label: const Text('دفع نقدي فوري وتثبيت (F9)', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Clear Cart Button
                    OutlinedButton.icon(
                      onPressed: _cart.isEmpty ? null : () => setState(() => _cart.clear()),
                      icon: const Icon(Icons.delete_sweep_rounded),
                      label: const Text('تفريغ السلة (Esc)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? highlightColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 15 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isBold ? 18 : 13,
            color: highlightColor,
          ),
        ),
      ],
    );
  }
}
