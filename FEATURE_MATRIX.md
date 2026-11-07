# ALFA SOFT — COMPREHENSIVE FEATURE MATRIX

Statuses:
- `Not Started`: Planned but no technical analysis or code started.
- `Analyzed`: Technical spec, data models, and business logic designed.
- `In Progress`: Currently undergoing implementation.
- `Implemented`: Functional code written, awaiting full test suite.
- `Tested`: Automated unit/integration tests passing.
- `Verified`: End-to-end user workflow validated with data persistence and auditing.
- `Released`: Packaged in production distribution.
- `Blocked`: Awaiting external dependency or architectural prerequisite.

---

## 1. Organization & Multi-Tenancy

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ORG-01** | Multi-Company Profile Setup | High | Phase 2 | **Verified** | Company isolation, tax IDs, commercial registries |
| **ORG-02** | Multi-Branch Architecture | Medium | Phase 2 | **Verified** | Branch-specific settings, sequences, permissions |
| **ORG-03** | Multi-Warehouse Hierarchies | Medium | Phase 2 | **Verified** | Warehouse locations, bins, inter-warehouse links |
| **ORG-04** | Fiscal Year & Accounting Periods | High | Phase 2 | Analyzed | Period locking, opening balances, closing routines |
| **ORG-05** | Company-Specific Numbering Sequences | Medium | Phase 2 | Analyzed | Prefixes, padding, fiscal-year resets |

---

## 2. Point of Sale (POS) & Retail Engine

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **POS-01** | High-Speed Barcode / QR Scanning | High | Phase 3 | Analyzed | Hardware keyboard wedge, fast item resolution |
| **POS-02** | Touch & Keyboard-First Layout | Medium | Phase 3 | Analyzed | Fullscreen mode, shortcut accelerators (F1-F12) |
| **POS-03** | Cashier Shifts & Drawer Management | High | Phase 3 | Analyzed | Opening float, cash in/out, end-of-shift reconciliation |
| **POS-04** | Split & Multi-Method Payments | High | Phase 3 | Analyzed | Cash + Card + Credit + Bank transfer in single sale |
| **POS-05** | Hold & Suspended Cart Management | Medium | Phase 3 | Analyzed | Stash active cart, resume later without loss |
| **POS-06** | Thermal Receipt Printing (ESC/POS) | High | Phase 5 | Analyzed | Direct 80mm & 58mm raw printing, logo embedding |
| **POS-07** | Offline Transaction Processing | Critical | Phase 6 | Analyzed | Full local execution during network outage |

---

## 3. Inventory & Warehouse Management

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **INV-01** | Real-Time Stock Cards & Movements | High | Phase 3 | Analyzed | Every quantity change tied to movement transaction |
| **INV-02** | FIFO & Weighted Average Costing | Critical | Phase 4 | Analyzed | Cost layer tracking for accurate COGS |
| **INV-03** | Inter-Warehouse Stock Transfers | High | Phase 3 | Analyzed | Dispatch -> Transit -> Receipt dual-stage workflow |
| **INV-04** | Stock Adjustments & Physical Count | High | Phase 3 | Analyzed | Surplus/deficit reconciliation, adjustment journals |
| **INV-05** | Batch, Expiry & Serial Number Tracking | High | Phase 3 | Analyzed | Pharma/food expiry alerts, electronics IMEI/serial |
| **INV-06** | Unit Conversion Matrices | High | Phase 2 | Analyzed | Piece <-> Box <-> Carton with fractional prices |
| **INV-07** | Negative Stock Prevention Policies | Medium | Phase 3 | Analyzed | Configurable strict lock vs warning override |

---

## 4. Sales & Commercial Operations

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SAL-01** | Sales Quotations & Pro-Forma | Medium | Phase 3 | Analyzed | One-click conversion to Sales Order / Invoice |
| **SAL-02** | Sales Orders & Delivery Notes | High | Phase 3 | Analyzed | Partial fulfillments, stock reservations |
| **SAL-03** | Tax Invoicing (Inclusive/Exclusive) | High | Phase 3 | Analyzed | Compliant VAT/Sales tax computation & QR code |
| **SAL-04** | Credit Notes & Sales Returns | High | Phase 3 | Analyzed | Restocking, source invoice linkage, account credit |
| **SAL-05** | Customer Pricing Tiers & Price Lists | Medium | Phase 2 | Analyzed | Wholesale, Retail, Distributor, Minimum price lock |
| **SAL-06** | Salesperson Tracking & Commission | Medium | Phase 3 | Analyzed | Commission reporting based on paid collections |

---

## 5. Purchasing & Supply Chain

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PUR-01** | Purchase Requisitions & Orders | Medium | Phase 3 | Analyzed | Multi-level approval thresholds |
| **PUR-02** | Goods Received Notes (GRN) | High | Phase 3 | Analyzed | Inventory increments trigger only on physical receipt |
| **PUR-03** | Landed Cost Allocation | High | Phase 3 | Analyzed | Shipping, customs, freight apportioned to item costs |
| **PUR-04** | Supplier Invoices & Debit Notes | High | Phase 3 | Analyzed | Three-way matching (PO vs GRN vs Supplier Bill) |
| **PUR-05** | Supplier Returns & Refunds | High | Phase 3 | Analyzed | Return to vendor with inventory deduction & AP debit |

---

## 6. Financial & Double-Entry Accounting

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ACC-01** | Hierarchical Chart of Accounts | High | Phase 4 | Analyzed | 5-level asset/liability/equity/revenue/expense tree |
| **ACC-02** | Automated Journal Entry Engine | Critical | Phase 4 | Analyzed | Sales, purchases, payments auto-post balanced journals |
| **ACC-03** | Manual Journal Vouchers | High | Phase 4 | Analyzed | Multi-line balanced entry with debit == credit guard |
| **ACC-04** | General Ledger & Subledgers | High | Phase 4 | Analyzed | Filter by date, account, branch, cost center |
| **ACC-05** | Accounts Receivable & Aging Reports | High | Phase 4 | Analyzed | 30/60/90/120+ days aging, credit limit warnings |
| **ACC-06** | Accounts Payable & Aging Reports | High | Phase 4 | Analyzed | Vendor bills, pending disbursements, payment terms |
| **ACC-07** | Trial Balance & Balance Sheet | Critical | Phase 4 | Analyzed | Real-time generated from general ledger |
| **ACC-08** | Profit & Loss Statement (Income) | Critical | Phase 4 | Analyzed | True Gross & Net Profit taking actual COGS |
| **ACC-09** | Bank & Cashbox Reconciliation | High | Phase 4 | Analyzed | Match cleared transactions with physical statements |
| **ACC-10** | Fiscal Period Closing & Locking | High | Phase 4 | Analyzed | Prevents retro-active modifications to closed periods |

---

## 7. Synchronization & Offline Engine

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SYN-01** | Transactional Outbox Pattern | Critical | Phase 6 | Analyzed | Local changes written to outbox table atomically |
| **SYN-02** | Peer-to-Peer Local Network Sync | High | Phase 6 | Analyzed | Workstations sync across local LAN without cloud |
| **SYN-03** | Central Cloud Synchronization | High | Phase 6 | Analyzed | Sync with central PostgreSQL via RESTful TLS API |
| **SYN-04** | Removable Media Transfer Package | High | Phase 6 | Analyzed | Offline encrypted USB export/import bundle |
| **SYN-05** | Conflict Detection & Resolution UI | Critical | Phase 6 | Analyzed | Visual differential merge with domain audit log |

---

## 8. Data Migration & Import Center

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **MIG-01** | Relational Database Discovery | High | Phase 7 | Analyzed | Read-only inspection of SQLite, MySQL, MSSQL, PG |
| **MIG-02** | Intelligent Field Mapping Engine | High | Phase 7 | Analyzed | Heuristic matching with manual override & profiles |
| **MIG-03** | Staged Validation & Dry-Run Preview | High | Phase 7 | Analyzed | Detect foreign key anomalies, duplicates prior to write |
| **MIG-04** | Excel & CSV Universal Importers | Medium | Phase 7 | Analyzed | Fast chunked import of products, clients, opening stock |
| **MIG-05** | Isolated SQL Sandbox Execution | High | Phase 7 | Analyzed | In-memory SQLite sandbox with query limits |

---

## 9. Security, RBAC & Licensing

| Feature Code | Feature Description | Complexity | Phase | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | Role-Based Access Control (RBAC) | High | Phase 2 | **Verified** | Granular permission flags (Create, Read, Edit, Post) |
| **SEC-02** | Immutable Audit Trail & Change Log | High | Phase 2 | **Verified** | Pre/post change JSON payloads, user & device stamping |
| **SEC-03** | Ed25519 Cryptographic Licensing | Critical | Phase 8 | Analyzed | Asymmetric verification, hardware fingerprint binding |
| **SEC-04** | Offline Challenge-Response Activation| High | Phase 8 | Analyzed | Air-gapped activation code generation and validation |
| **SEC-05** | Developer Licensing Portal Web App | High | Phase 8 | Analyzed | Independent portal to generate, sign, and revoke seats |

---

## 10. Summary Progress Metrics

- **Total Analyzed Features**: 52
- **Implemented Features**: 0
- **Verified Features**: 0
- **Current Completion**: 0% (Phase 0 in progress)
