# ALFA SOFT — API CONTRACTS & INTERFACE SPECIFICATION

## 1. Electron Typed IPC Bridge (`window.alfaApi`)

The renderer interacts with trusted backend services strictly via typed IPC invokes exposed through `preload.ts`.

### 1.1 Authentication & Session
- `alfaApi.auth.login(credentials: LoginRequest): Promise<AuthResponse>`
- `alfaApi.auth.logout(): Promise<void>`
- `alfaApi.auth.getCurrentSession(): Promise<UserSession | null>`
- `alfaApi.auth.lockScreen(): Promise<void>`

### 1.2 Point of Sale & Invoicing
- `alfaApi.pos.openShift(initialFloat: number): Promise<PosShift>`
- `alfaApi.pos.closeShift(shiftId: string, actualCash: number): Promise<PosShiftSummary>`
- `alfaApi.pos.lookupProductByBarcode(barcode: string): Promise<ProductLookupResult | null>`
- `alfaApi.pos.postSale(saleDto: CreateSaleInvoiceDto): Promise<PostedInvoiceResult>`
- `alfaApi.pos.holdCart(cart: CartState): Promise<string>`
- `alfaApi.pos.resumeCart(holdId: string): Promise<CartState>`

### 1.3 Inventory & Warehouse
- `alfaApi.inventory.getBalance(warehouseId: string, productId: string): Promise<InventoryBalance>`
- `alfaApi.inventory.transferStock(dto: StockTransferDto): Promise<TransferResult>`
- `alfaApi.inventory.adjustStock(dto: StockAdjustmentDto): Promise<AdjustmentResult>`

### 1.4 Accounting & Ledgers
- `alfaApi.accounting.getChartOfAccounts(): Promise<AccountTreeNode[]>`
- `alfaApi.accounting.postJournalEntry(dto: CreateJournalEntryDto): Promise<JournalEntry>`
- `alfaApi.accounting.getTrialBalance(dateRange: DateRangeDto): Promise<TrialBalanceReport>`
- `alfaApi.accounting.getBalanceSheet(asOfDate: string): Promise<BalanceSheetReport>`

### 1.5 Printing & Hardware
- `alfaApi.hardware.printReceipt(invoiceId: string, printerName?: string): Promise<PrintResult>`
- `alfaApi.hardware.openCashDrawer(): Promise<void>`
- `alfaApi.hardware.listPrinters(): Promise<PrinterDevice[]>`

---

## 2. Central Synchronization REST API (`apps/sync-server`)

All requests require Bearer JWT authentication and TLS 1.3.

### 2.1 Handshake & Sequence Check
- **Endpoint**: `POST /api/v1/sync/handshake`
- **Request**:
  ```json
  {
    "deviceId": "dev_01J...",
    "companyId": "comp_01J...",
    "lastKnownServerSequence": 4512
  }
  ```
- **Response** (`200 OK`):
  ```json
  {
    "serverSequence": 4530,
    "pendingInboundEvents": 18,
    "serverTime": "2026-11-07T13:00:00Z"
  }
  ```

### 2.2 Push Events Batch
- **Endpoint**: `POST /api/v1/sync/push`
- **Request**: `SyncPacket` containing array of `SyncEvent` items.
- **Response** (`200 OK`):
  ```json
  {
    "acknowledgedEventIds": ["evt_01...", "evt_02..."],
    "rejectedEvents": [],
    "committedSequence": 4531
  }
  ```

### 2.3 Pull Inbound Events
- **Endpoint**: `GET /api/v1/sync/pull?since=4512&limit=500`
- **Response** (`200 OK`):
  ```json
  {
    "events": [ /* Array of SyncEvent */ ],
    "hasMore": false,
    "latestSequence": 4531
  }
  ```

---

## 3. Developer Licensing REST API (`apps/developer-portal`)

### 3.1 Online Seat Activation
- **Endpoint**: `POST /api/v1/licensing/activate`
- **Request**:
  ```json
  {
    "licenseKey": "ALFA-PRO-2026-XXXX-YYYY",
    "deviceFingerprint": "9f83c12c4e1f...",
    "deviceName": "BRANCH-1-CASHIER-1",
    "osVersion": "Windows 11 Pro 64-bit"
  }
  ```
- **Response** (`200 OK`):
  ```json
  {
    "signedLicense": {
      "payload": { /* LicensePayload */ },
      "signature": "MEQCID...",
      "developerKeyId": "key_ed25519_2026"
    }
  }
  ```
