# ALFA SOFT — USER & OPERATIONAL MANUAL

## 1. Navigating the Workspace

ALFA SOFT features a unified, keyboard-accessible interface optimized for quick navigation:
- **Global Search (`Ctrl + K`)**: Instant lookup across products, invoices, customers, and navigation menus.
- **Side Navigation Drawer**: Collapsible tree navigation categorizing Core Masters, POS, Sales, Purchases, Inventory, Accounting, and Settings.
- **Top Bar**: Active Cashier Shift status, Current Branch/Warehouse selector, Network & Sync status indicator, and Profile/Screen Lock.

---

## 2. Point of Sale (POS) Daily Workflow

### 2.1 Starting the Day: Opening a Shift
1. Log in with your Cashier credentials.
2. Select **Point of Sale** from the main menu.
3. If no shift is open, the **Open Shift Modal** appears.
4. Count and input the starting cash float (e.g., 200.00 SAR).
5. Click **Open Shift**. The cash drawer opens and the POS screen activates.

### 2.2 Processing a Sale
1. **Scan Barcode**: Focus is automatically on the scanner input. Scan items sequentially.
2. **Item Lookup (`F1`)**: For items without barcodes, press `F1` to search by product name or SKU.
3. **Adjust Quantity**: Click on quantity or press `+` / `-` keys.
4. **Customer (`F2`)**: Defaults to "Walk-in Customer". Press `F2` to assign a registered customer account.
5. **Finalize Payment**:
   - **Cash (`F9`)**: Enter cash received. Change due displays prominently. Receipt prints automatically and drawer kicks.
   - **Card / Split (`F10`)**: Apportion amounts across Card, Cash, or Credit balance.

### 2.3 Holding & Resuming Transactions
- Press `F4` to park the current cart if a customer steps away.
- Click **Suspended Sales** to retrieve and resume the parked cart at any time.

### 2.4 End-of-Day Shift Close & Cash Reconciliation
1. Press `Shift + F12` or click **Close Shift**.
2. Perform a blind count of physical cash in the drawer and input the total.
3. Click **Submit Count**.
4. The system prints the **Z-Report (Shift Summary)** showing total sales, tax, card collections, expected cash, actual cash, and variance.

---

## 3. Inventory & Purchasing Routine

1. **Creating a Purchase Order**: Navigate to **Purchases** $\to$ **New Purchase Order**. Select supplier, items, and negotiated purchase prices.
2. **Receiving Goods (GRN)**: When goods arrive at the warehouse, navigate to the PO and click **Receive Goods**. Physical inventory quantities and weighted average costs update automatically upon posting.
3. **Stock Transfers**: To move stock between branches, use **Inventory** $\to$ **Stock Transfers**. Goods transition to `IN_TRANSIT` until acknowledged by the destination warehouse.
