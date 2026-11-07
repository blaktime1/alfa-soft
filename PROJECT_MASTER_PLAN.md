# ALFA SOFT — PROJECT MASTER PLAN (FLUTTER WINDOWS C++ RUNNER)

## 1. Executive Summary & Product Vision

**ALFA SOFT** is a commercial-grade, multi-tenant capable, offline-first Enterprise Resource Planning (ERP) and Business Management System designed exclusively as an **authentic Native Windows Desktop Application** utilizing **Flutter Desktop with native C++ Runner**.

The platform is engineered for intensive daily retail and corporate accounting operations, adhering to strict double-entry accounting standards, real-time inventory tracking (FIFO / Weighted Average Cost), multi-branch/multi-warehouse management, high-performance Point of Sale (POS) checkout, raw thermal printing (ESC/POS), encrypted offline/online synchronization, and cryptographically verified asymmetric licensing (Ed25519).

---

## 2. Core Architectural Principles & Non-Negotiables

1. **Native Desktop Execution**: Pure compiled Ahead-Of-Time (AOT) machine code via Windows C++ Runner (`windows/runner`). Zero Chromium overhead, zero Node.js processes, and sub-60MB baseline RAM consumption.
2. **Zero Decorative Controls**: Every UI action binds to a real domain service, database transaction, and validation pipeline.
3. **Transaction Integrity & Atomicity**: Financial postings and inventory movements execute inside atomic SQLite local transactions. If any step fails, immediate rollback is enforced.
4. **No Floating-Point Math for Currency**: Fixed-scale integer arithmetic in minor units (or exact decimal scaled integers) is strictly enforced for all monetary calculations.
5. **Offline-First Resilience**: Full operational autonomy when disconnected from the network. Local SQLite with WAL mode and strict foreign key constraints ensures zero latency.
6. **Domain-Aware Conflict Resolution**: Synchronization conflicts are resolved via deterministic domain logic, sequence numbers, and vector checkpoints—never arbitrary "last timestamp wins".
7. **Double-Entry Accounting Enforcement**: All financial transactions generate balanced journal entries where `Debit == Credit`. Posted journals are immutable; corrections require reversing entries.
8. **Direct Hardware Control**: Native Win32 printer spooler integration for high-speed thermal receipt printing (ESC/POS) and direct drawer kick pulses.

---

## 3. Technology Stack & Runtime

### 3.1 Desktop Workstation (Client App)
- **Framework**: Flutter Desktop (Channel Stable, Dart 3.9+).
- **Desktop Shell**: Native Windows C++ Runner (`windows/runner/main.cpp`, `flutter_window.cpp`, `win32_window.cpp`).
- **Rendering Engine**: Skia / Impeller directly drawing to DirectX 12 / Windows desktop surface.
- **Window Management**: `window_manager` for framing, custom titlebar, fullscreen POS mode, and minimum resolution constraints.
- **Local Database**: SQLite 3 via Native FFI (`sqlite3` / `drift`) with WAL mode, foreign keys enabled, and migration versioning.
- **State Management**: Riverpod (v2.6+) for reactive, testable, and strictly decoupled domain state.
- **Hardware Integration**: Win32 direct spooler APIs and raw TCP/Serial socket streams for ESC/POS thermal printers and barcode scanners.
- **Typography & Localization**: `google_fonts` (`IBM Plex Sans Arabic` & `Cairo`), full bidirectional RTL/LTR support, and localized number formatting.

### 3.2 Central Synchronization & Backend
- **Transport**: RESTful APIs & WebSockets over TLS 1.3.
- **Central Storage**: PostgreSQL 16+ with structured schema migrations and event-sourcing change logs.
- **Authentication**: JWT with refresh token rotation and device-bound public keys.

### 3.3 Developer Licensing Authority (`apps/developer-portal`)
- **Nature**: Isolated administrative web portal for license issuance, device seat management, customer records, and cryptographic license signing (Ed25519).
- **Security Boundary**: Completely decoupled from customer operational databases; holds developer private signing keys.

---

## 4. Modular Feature-First Directory Layout

```
alfa_soft/
├── windows/                     # Native Windows C++ Runner & CMake Configuration
│   ├── runner/
│   │   ├── main.cpp
│   │   ├── flutter_window.cpp
│   │   ├── win32_window.cpp
│   │   └── Runner.rc
│   └── CMakeLists.txt
├── lib/
│   ├── app/                     # App bootstrap, router, theme, multi-tenancy context
│   ├── core/                    # Banker's rounding, monetary types, cryptography, errors
│   ├── data/
│   │   ├── local/               # SQLite FFI database engine, migrations, DAOs
│   │   └── sync/                # Transactional outbox engine, change tracking
│   ├── domain/                  # Pure enterprise models, value objects, accounting rules
│   └── features/
│       ├── auth/                # Multi-tenant login, sessions, granular RBAC
│       ├── organization/        # Companies, branches, warehouses, fiscal periods
│       ├── pos/                 # High-speed checkout, barcode scanner, shift drawer
│       ├── sales/               # Invoices, quotations, returns, pricing tiers
│       ├── inventory/           # Stock movements, FIFO & MAC costing, transfers
│       ├── purchases/           # PO, GRN, landed costs, vendor bills
│       ├── accounting/          # Chart of accounts, journal engine, trial balance
│       ├── printing/            # ESC/POS raw thermal driver, PDF generator
│       ├── migration/           # Database discovery, field mapping, CSV/Excel import
│       └── licensing/           # Ed25519 asymmetric verification, device fingerprinting
├── assets/                      # Fonts, branding logos, sound cues
├── test/                        # Automated unit, integration, and accounting test suites
└── docs/                        # Complete 22-document engineering blueprints
```

---

## 5. Phased Implementation Roadmap

| Phase | Title | Focus & Core Deliverables | Status |
| :--- | :--- | :--- | :--- |
| **Phase 0** | **Discovery & Technical Spec** | Codebase inspection, full documentation suite adapted to Flutter Desktop, threat models. | **Completed** |
| **Phase 1** | **Foundation & Flutter Native Architecture** | Flutter Windows project setup, `window_manager`, SQLite FFI persistence, WAL mode, migrations, Premium Layered theme. | **In Progress** |
| **Phase 2** | **Core Business Data** | Multi-company setup, branches, warehouses, users, RBAC permissions, product catalog, pricing tiers, customers, suppliers. | Pending |
| **Phase 3** | **Business Operations & POS** | Purchasing, goods receipt, sales orders, POS high-speed checkout, split payments, returns, cash drawers, shifts. | Pending |
| **Phase 4** | **Financial & Accounting Subsystem** | Chart of accounts, double-entry journal engine, auto-posting rules, AR/AP ledgers, trial balance, income statement, balance sheet. | Pending |
| **Phase 5** | **Reporting, Printing & Documents** | Operational dashboard, PDF engine, thermal receipt printing (ESC/POS 80mm/58mm), Excel export, custom report builder. | Pending |
| **Phase 6** | **Offline & Multi-Device Sync** | Transactional outbox/inbox, sequence tracking, LAN & Cloud sync engines, conflict review UI. | Pending |
| **Phase 7** | **Data Import & Migration Center** | External connectors (MySQL, MSSQL, Postgres, Excel, CSV), table inspection, auto field mapping, SQL sandbox. | Pending |
| **Phase 8** | **Licensing & Developer Portal** | Ed25519 asymmetric signatures, machine fingerprinting, offline challenge-response, developer portal web app. | Pending |
| **Phase 9** | **Advanced Enterprise Features** | Basic HR & payroll, approval workflows, cost centers, custom fields, system health dashboard. | Pending |
| **Phase 10**| **Security, QA & Hardening** | Penetration review, concurrency stress testing, crash recovery tests, memory profiling, regression suites. | Pending |
| **Phase 11**| **Production Build & Windows Installer**| Windows NSIS / Inno Setup installer, code signing setup, clean VM verification, user manuals. | Pending |
