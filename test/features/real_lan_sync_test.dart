import 'package:flutter_test/flutter_test.dart';
import 'package:alfa_soft/data/local/database_service.dart';
import 'package:alfa_soft/core/sync/outbox_manager.dart';
import 'package:alfa_soft/core/sync/lan_sync_server.dart';
import 'package:alfa_soft/core/sync/lan_sync_client.dart';

void main() {
  late DatabaseService serverDb;
  late DatabaseService clientDb;
  late LanSyncServer syncServer;
  late LanSyncClient syncClient;
  const testPort = 7890;

  setUp(() async {
    // 1. Initialize Server DB and Client DB in memory
    serverDb = DatabaseService.inMemory();
    clientDb = DatabaseService.inMemory();

    // Seed minimal required records on server
    serverDb.execute('''
      INSERT INTO companies (id, legal_name, trade_name) 
      VALUES ('comp_1', 'شركة الفا الرئيسية', 'الفا سوفت');
      INSERT INTO branches (id, company_id, code, name) 
      VALUES ('branch_1', 'comp_1', 'BR1', 'الفرع الرئيسي');
      INSERT INTO warehouses (id, branch_id, code, name) 
      VALUES ('wh_1', 'branch_1', 'WH1', 'المستودع المركزي');
      INSERT INTO users (id, company_id, username, full_name, password_hash, is_admin) 
      VALUES ('usr_admin', 'comp_1', 'admin', 'المدير العام', 'hash', 1);
      INSERT INTO users (id, company_id, username, full_name, password_hash, is_admin) 
      VALUES ('usr_pos', 'comp_1', 'pos1', 'كاشير المحطة 2', 'hash', 0);
      INSERT INTO units (id, company_id, code, name) 
      VALUES ('unit_pc', 'comp_1', 'PC', 'حبة');
      INSERT INTO customers (id, company_id, code, name, current_balance) 
      VALUES ('cust_1', 'comp_1', 'CUST01', 'عميل المعرض', 0);
      INSERT INTO products (id, company_id, sku, name_ar, base_unit_id, sale_price, cost_price, version, updated_at) 
      VALUES ('prod_1', 'comp_1', 'PR001', 'منتج تجريبي 1', 'unit_pc', 1500, 1000, 1, datetime('now'));
      INSERT INTO inventory_balances (warehouse_id, product_id, quantity) 
      VALUES ('wh_1', 'prod_1', 100);
    ''');

    // Seed minimal required records on client
    clientDb.execute('''
      INSERT INTO companies (id, legal_name, trade_name) 
      VALUES ('comp_1', 'شركة الفا الرئيسية', 'الفا سوفت');
      INSERT INTO branches (id, company_id, code, name) 
      VALUES ('branch_1', 'comp_1', 'BR1', 'الفرع الرئيسي');
      INSERT INTO warehouses (id, branch_id, code, name) 
      VALUES ('wh_1', 'branch_1', 'WH1', 'المستودع المركزي');
      INSERT INTO users (id, company_id, username, full_name, password_hash, is_admin) 
      VALUES ('usr_pos', 'comp_1', 'pos1', 'كاشير المحطة 2', 'hash', 0);
      INSERT INTO units (id, company_id, code, name) 
      VALUES ('unit_pc', 'comp_1', 'PC', 'حبة');
      INSERT INTO customers (id, company_id, code, name, current_balance) 
      VALUES ('cust_1', 'comp_1', 'CUST01', 'عميل المعرض', 0);
      INSERT INTO products (id, company_id, sku, name_ar, base_unit_id, sale_price, cost_price, version, updated_at) 
      VALUES ('prod_1', 'comp_1', 'PR001', 'منتج تجريبي 1', 'unit_pc', 1500, 1000, 1, datetime('now'));
      INSERT INTO inventory_balances (warehouse_id, product_id, quantity) 
      VALUES ('wh_1', 'prod_1', 50);
    ''');

    syncServer = LanSyncServer(db: serverDb);
    syncClient = LanSyncClient(db: clientDb);
    syncClient.configure(serverHost: '127.0.0.1', serverPort: testPort, autoSync: true, nodeId: 'TEST-POS-02');
  });

  tearDown(() async {
    syncClient.dispose();
    await syncServer.stop();
  });

  group('نظام المزامنة والربط الشبكي الفعلي عبر الشبكة المحلية (Real LAN Sync Engine)', () {
    test('1. بدء تشغيل السيرفر وفحص الاتصال الحي (Live HTTP Ping & Latency)', () async {
      final started = await syncServer.start(port: testPort, serverName: 'سيرفر الفا المالي المركزي');
      expect(started, isTrue);
      expect(syncServer.isRunning, isTrue);

      final ping = await syncClient.pingServer(host: '127.0.0.1', port: testPort);
      expect(ping.isSuccess, isTrue);
      expect(ping.serverName, equals('سيرفر الفا المالي المركزي'));
      expect(ping.latencyMs, greaterThanOrEqualTo(0));
      expect(syncClient.state, equals(ClientSyncState.online));
    });

    test('2. صلابة العمل دون اتصال (Offline-First Resilience): حفظ فواتير الكاشير أثناء توقف السيرفر دون أي تعطيل', () async {
      // Server is NOT running (simulating master server shut down or network unplugged)
      expect(syncServer.isRunning, isFalse);

      final ping = await syncClient.pingServer(host: '127.0.0.1', port: testPort);
      expect(ping.isSuccess, isFalse);
      expect(syncClient.state, equals(ClientSyncState.offline));

      // POS Cashier performs sales transactions offline
      final clientOutbox = OutboxManager(clientDb);
      clientOutbox.enqueue(
        entityType: 'SALES_INVOICE',
        entityId: 'inv_offline_101',
        operation: SyncOperation.create,
        payload: {
          'id': 'inv_offline_101',
          'company_id': 'comp_1',
          'branch_id': 'branch_1',
          'warehouse_id': 'wh_1',
          'customer_id': 'cust_1',
          'invoice_number': 'INV-OFF-101',
          'invoice_date': DateTime.now().toIso8601String(),
          'subtotal': 3000,
          'tax_total': 450,
          'discount_total': 0,
          'grand_total': 3450,
          'paid_total': 3450,
          'status': 'POSTED',
          'payment_status': 'PAID',
          'created_by_user_id': 'usr_pos',
          'items': [
            {
              'id': 'item_101',
              'invoice_id': 'inv_offline_101',
              'product_id': 'prod_1',
              'quantity': 2,
              'unit_id': 'unit_pc',
              'unit_price': 1500,
              'cost_price': 1000,
              'discount_amount': 0,
              'tax_rate': 15,
              'tax_amount': 450,
              'line_total': 3450,
            }
          ],
        },
      );

      final stats = clientOutbox.getStats();
      expect(stats.pendingCount, equals(1));
    });

    test('3. إعادة الاتصال التلقائي ونقل العمليات المتراكمة فور تشغيل السيرفر (Automatic Catch-Up & Outbox Push)', () async {
      // 1. Prepare offline invoice in client outbox
      final clientOutbox = OutboxManager(clientDb);
      clientOutbox.enqueue(
        entityType: 'SALES_INVOICE',
        entityId: 'inv_offline_102',
        operation: SyncOperation.create,
        payload: {
          'id': 'inv_offline_102',
          'company_id': 'comp_1',
          'branch_id': 'branch_1',
          'warehouse_id': 'wh_1',
          'customer_id': 'cust_1',
          'invoice_number': 'INV-OFF-102',
          'invoice_date': DateTime.now().toIso8601String(),
          'subtotal': 4500,
          'tax_total': 675,
          'discount_total': 0,
          'grand_total': 5175,
          'paid_total': 5175,
          'status': 'POSTED',
          'payment_status': 'PAID',
          'created_by_user_id': 'usr_pos',
          'items': [
            {
              'id': 'item_102',
              'invoice_id': 'inv_offline_102',
              'product_id': 'prod_1',
              'quantity': 3,
              'unit_id': 'unit_pc',
              'unit_price': 1500,
              'cost_price': 1000,
              'discount_amount': 0,
              'tax_rate': 15,
              'tax_amount': 675,
              'line_total': 5175,
            }
          ],
        },
      );

      expect(clientOutbox.getStats().pendingCount, equals(1));

      // 2. Primary Server turns on!
      final started = await syncServer.start(port: testPort);
      expect(started, isTrue);

      // 3. Client executes syncNow (which happens automatically in background sync loop)
      final syncResult = await syncClient.syncNow();
      expect(syncResult.isSuccess, isTrue);
      expect(syncResult.syncedCount, equals(1));

      // 4. Verify client outbox marked as SYNCED
      final clientStats = clientOutbox.getStats();
      expect(clientStats.pendingCount, equals(0));
      expect(clientStats.syncedCount, equals(1));

      // 5. Verify server DB received and committed the invoice and its items!
      final serverInvoices = serverDb.select("SELECT * FROM sales_invoices WHERE id = 'inv_offline_102'");
      expect(serverInvoices, isNotEmpty);
      expect(serverInvoices.first['invoice_number'], equals('INV-OFF-102'));
      expect(serverInvoices.first['grand_total'], equals(5175));

      final serverItems = serverDb.select("SELECT * FROM sales_invoice_items WHERE invoice_id = 'inv_offline_102'");
      expect(serverItems, isNotEmpty);
      expect(serverItems.first['quantity'], equals(3));
      expect(serverItems.first['product_id'], equals('prod_1'));

      // 6. Verify server inventory balance deducted automatically
      final serverStock = serverDb.select("SELECT quantity FROM inventory_balances WHERE product_id = 'prod_1' AND warehouse_id = 'wh_1'");
      expect(serverStock.first['quantity'], equals(100 - 3)); // 97

      // 7. Verify Server logs recorded the incoming sync from client
      expect(syncServer.syncLogs, isNotEmpty);
      expect(syncServer.syncLogs.first.clientNodeId, equals('TEST-POS-02'));
      expect(syncServer.syncLogs.first.isSuccess, isTrue);
    });

    test('4. سحب التعديلات من الخادم المركزي إلى الكاشير (Pull Server Updates)', () async {
      await syncServer.start(port: testPort);

      // Admin updates product price and inserts a new customer on server
      serverDb.execute('''
        UPDATE products 
        SET sale_price = 2200, name_ar = 'منتج محدث بالسيرفر', updated_at = datetime('now') 
        WHERE id = 'prod_1';

        INSERT INTO customers (id, company_id, code, name, current_balance, updated_at) 
        VALUES ('cust_new_srv', 'comp_1', 'CUST99', 'عميل مضاف بالسيرفر', 500, datetime('now'));
      ''');

      // Secondary client pulls updates
      final pulled = await syncClient.pullServerUpdates();
      expect(pulled, isTrue);

      // Verify client DB received updated product price and new customer
      final clientProd = clientDb.select("SELECT sale_price, name_ar FROM products WHERE id = 'prod_1'");
      expect(clientProd.first['sale_price'], equals(2200));
      expect(clientProd.first['name_ar'], equals('منتج محدث بالسيرفر'));

      final clientCust = clientDb.select("SELECT name FROM customers WHERE id = 'cust_new_srv'");
      expect(clientCust, isNotEmpty);
      expect(clientCust.first['name'], equals('عميل مضاف بالسيرفر'));
    });
  });
}
