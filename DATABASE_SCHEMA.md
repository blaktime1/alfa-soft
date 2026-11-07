# ALFA SOFT — DATABASE SCHEMA SPECIFICATION

## 1. Schema Conventions & Data Types

- **Identifier Strategy**: UUID v4 (`TEXT` in SQLite, `UUID` in PostgreSQL) for globally unique distributed synchronization.
- **Monetary Amounts**: Stored as exact integer minor currency units (e.g., Cents/Halalas) or `DECIMAL(18, 4)` / `NUMERIC(18, 4)`. In SQLite, stored as `INTEGER` (minor units) or fixed string representation to prevent IEEE 754 float precision loss.
- **Timestamps**: ISO 8601 UTC strings (`TEXT`) in SQLite and `TIMESTAMPTZ` in PostgreSQL.
- **Auditing**: Every primary record includes `created_at`, `updated_at`, `created_by_user_id`, and `version` (monotonic integer for optimistic concurrency control).

---

## 2. Core Relational Entities & SQLite DDL

### 2.1 Multi-Tenant Organization & Locations

```sql
-- Companies
CREATE TABLE IF NOT EXISTS companies (
    id TEXT PRIMARY KEY,
    legal_name TEXT NOT NULL,
    trade_name TEXT NOT NULL,
    tax_number TEXT,
    commercial_registration TEXT,
    currency_code TEXT NOT NULL DEFAULT 'SAR',
    logo_path TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1
);

-- Branches
CREATE TABLE IF NOT EXISTS branches (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    is_main INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(company_id, code)
);

-- Warehouses
CREATE TABLE IF NOT EXISTS warehouses (
    id TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(branch_id, code)
);
```

### 2.2 Security, Identity & RBAC

```sql
-- Users
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    username TEXT NOT NULL,
    email TEXT,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    is_admin INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(company_id, username)
);

-- Roles & Permissions
CREATE TABLE IF NOT EXISTS roles (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_key TEXT NOT NULL, -- e.g., 'pos:create', 'accounting:post_journal'
    PRIMARY KEY(role_id, permission_key)
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    branch_id TEXT REFERENCES branches(id) ON DELETE CASCADE, -- Optional branch restriction
    PRIMARY KEY(user_id, role_id)
);

-- Immutable Audit Log
CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL,
    branch_id TEXT,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    action TEXT NOT NULL, -- e.g., 'POST_INVOICE', 'VOID_RECEIPT', 'UPDATE_PRICE'
    entity_name TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    previous_state TEXT, -- JSON snapshot
    new_state TEXT,      -- JSON snapshot
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    ip_address TEXT,
    reason TEXT
);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_name, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);
```

### 2.3 Product Catalog & Units

```sql
-- Units of Measurement
CREATE TABLE IF NOT EXISTS units (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    code TEXT NOT NULL, -- e.g., 'PCS', 'BOX', 'KG'
    name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(company_id, code)
);

-- Categories
CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    parent_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    code TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1
);

-- Products
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
    base_unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
    sku TEXT NOT NULL,
    barcode TEXT,
    name_ar TEXT NOT NULL,
    name_en TEXT,
    cost_price INTEGER NOT NULL DEFAULT 0, -- Minor units
    sale_price INTEGER NOT NULL DEFAULT 0,
    min_sale_price INTEGER NOT NULL DEFAULT 0,
    reorder_level INTEGER NOT NULL DEFAULT 0,
    has_variants INTEGER NOT NULL DEFAULT 0,
    track_inventory INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
```

### 2.4 Inventory Movements & Valuation

```sql
-- Inventory Balances (Read Cache)
CREATE TABLE IF NOT EXISTS inventory_balances (
    warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL DEFAULT 0, -- Base unit quantity
    reserved_quantity INTEGER NOT NULL DEFAULT 0,
    average_cost INTEGER NOT NULL DEFAULT 0, -- Moving average cost
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY(warehouse_id, product_id)
);

-- Immutable Inventory Ledger (Ledger-backed)
CREATE TABLE IF NOT EXISTS inventory_movements (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    movement_type TEXT NOT NULL, -- 'PURCHASE_RECEIPT', 'SALE_ISSUE', 'TRANSFER_IN', 'TRANSFER_OUT', 'ADJUSTMENT'
    quantity INTEGER NOT NULL, -- Positive for in, negative for out
    unit_cost INTEGER NOT NULL,
    total_cost INTEGER NOT NULL,
    reference_document_type TEXT NOT NULL, -- 'INVOICE', 'GRN', 'ADJUSTMENT'
    reference_document_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_by_user_id TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_inv_movement_ref ON inventory_movements(reference_document_type, reference_document_id);
CREATE INDEX IF NOT EXISTS idx_inv_movement_prod ON inventory_movements(warehouse_id, product_id);
```

### 2.5 Point of Sale (POS) & Sales Transactions

```sql
-- Cashier Shifts
CREATE TABLE IF NOT EXISTS pos_shifts (
    id TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    opened_at TEXT NOT NULL DEFAULT (datetime('now')),
    closed_at TEXT,
    starting_cash INTEGER NOT NULL DEFAULT 0,
    expected_cash INTEGER NOT NULL DEFAULT 0,
    actual_cash INTEGER,
    difference INTEGER,
    status TEXT NOT NULL DEFAULT 'OPEN', -- 'OPEN', 'CLOSED'
    notes TEXT
);

-- Customers
CREATE TABLE IF NOT EXISTS customers (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    tax_number TEXT,
    credit_limit INTEGER NOT NULL DEFAULT 0,
    current_balance INTEGER NOT NULL DEFAULT 0, -- Positive = customer owes company
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(company_id, code)
);

-- Sales Invoices (Head)
CREATE TABLE IF NOT EXISTS sales_invoices (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    warehouse_id TEXT NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
    pos_shift_id TEXT REFERENCES pos_shifts(id) ON DELETE SET NULL,
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    invoice_number TEXT NOT NULL,
    invoice_date TEXT NOT NULL,
    subtotal INTEGER NOT NULL DEFAULT 0,
    tax_total INTEGER NOT NULL DEFAULT 0,
    discount_total INTEGER NOT NULL DEFAULT 0,
    grand_total INTEGER NOT NULL DEFAULT 0,
    paid_total INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'POSTED', -- 'DRAFT', 'POSTED', 'VOIDED', 'RETURNED'
    payment_status TEXT NOT NULL DEFAULT 'PAID', -- 'PAID', 'PARTIALLY_PAID', 'UNPAID'
    qr_code_payload TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE(company_id, invoice_number)
);

-- Sales Invoice Items (Lines)
CREATE TABLE IF NOT EXISTS sales_invoice_items (
    id TEXT PRIMARY KEY,
    invoice_id TEXT NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL,
    unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
    unit_price INTEGER NOT NULL,
    cost_price INTEGER NOT NULL, -- Historical COGS at sale time
    discount_amount INTEGER NOT NULL DEFAULT 0,
    tax_rate INTEGER NOT NULL DEFAULT 0, -- e.g. 1500 for 15.00%
    tax_amount INTEGER NOT NULL DEFAULT 0,
    line_total INTEGER NOT NULL
);

-- Payments
CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    document_type TEXT NOT NULL, -- 'SALES_INVOICE', 'PURCHASE_INVOICE', 'CUSTOMER_DEPOSIT'
    document_id TEXT NOT NULL,
    payment_method TEXT NOT NULL, -- 'CASH', 'CARD', 'BANK_TRANSFER', 'CREDIT'
    amount INTEGER NOT NULL,
    reference_number TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);
```

### 2.6 Double-Entry Accounting Engine

```sql
-- Chart of Accounts
CREATE TABLE IF NOT EXISTS chart_of_accounts (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    code TEXT NOT NULL, -- e.g. '10101'
    name_ar TEXT NOT NULL,
    name_en TEXT,
    account_type TEXT NOT NULL, -- 'ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE'
    parent_id TEXT REFERENCES chart_of_accounts(id) ON DELETE RESTRICT,
    is_leaf INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1,
    current_balance INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(company_id, code)
);

-- Journal Entries (Header)
CREATE TABLE IF NOT EXISTS journal_entries (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    branch_id TEXT NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
    entry_number TEXT NOT NULL,
    entry_date TEXT NOT NULL,
    source_type TEXT NOT NULL, -- 'SALES_INVOICE', 'PURCHASE_INVOICE', 'PAYMENT', 'MANUAL_VOUCHER'
    source_id TEXT,
    narration TEXT NOT NULL,
    total_debit INTEGER NOT NULL,
    total_credit INTEGER NOT NULL,
    is_balanced INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'POSTED', -- 'POSTED', 'REVERSED'
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_by_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    CHECK(total_debit = total_credit),
    UNIQUE(company_id, entry_number)
);

-- Journal Entry Lines
CREATE TABLE IF NOT EXISTS journal_lines (
    id TEXT PRIMARY KEY,
    journal_entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
    account_id TEXT NOT NULL REFERENCES chart_of_accounts(id) ON DELETE RESTRICT,
    debit INTEGER NOT NULL DEFAULT 0,
    credit INTEGER NOT NULL DEFAULT 0,
    memo TEXT,
    CHECK((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);
```

### 2.7 Synchronization Outbox & Queue

```sql
-- Sync Outbox (Local Station)
CREATE TABLE IF NOT EXISTS sync_outbox (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    payload TEXT NOT NULL,   -- Encrypted or JSON serialized data
    sequence_number INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    sync_status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'IN_FLIGHT', 'SYNCED', 'FAILED'
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
);
CREATE INDEX IF NOT EXISTS idx_outbox_status ON sync_outbox(sync_status);
```
