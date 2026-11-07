# ALFA SOFT — CHANGELOG

All notable changes to the ALFA SOFT ERP ecosystem will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-07

### Added
- **Flutter Windows Architecture**: Pure C++ Runner with SQLite 3 FFI and WAL mode.
- **Core Business Data**: Multi-company, branch, warehouse, product catalog, customer & supplier partners, RBAC and audit logging.
- **Operations & POS**: Purchase Orders, GRN with Moving Average Costing, Inter-warehouse stock transfers, Stock adjustments, POS shifts, blind close, suspended sales carts.
- **Accounting Subsystem**: Standard COA seeding, strict double-entry journal engine (`Debit == Credit`), automated posting hooks, Trial Balance, Income Statement, Balance Sheet, General Ledger.
- **Reporting & Printing**: ZATCA FATOORA TLV Base64 QR code, raw ESC/POS thermal printing bytes (80mm/58mm), A4 bilingual PDF tax invoices, and Excel CSV data exporter.
- **Offline LAN Sync**: Transactional Outbox pattern, sequence tracking, SHA-256 packets, and immutable ledger conflict engine.
- **Data Migration**: Intelligent field mapping, CSV parser with delimiter auto-detection, and dry-run pre-validation.
- **Licensing**: Machine hardware fingerprinting, Ed25519 cryptographic signing, offline license validation, and vendor key generator.
- **Enterprise Features**: Cost centers, HR employee management, automated monthly payroll runs, automated general ledger posting, and multi-tier approval workflows.
- **Security & QA**: Stress tested under 200 concurrent writes, PRAGMA integrity verification, and atomic transaction rollback proof.
- **Packaging**: Inno Setup 6 production installer script (`installer/alfa_soft_setup.iss`).

## [0.1.0-alpha] - 2026-11-07

### Added
- **Phase 0 Specifications**: Produced complete 22-document engineering blueprint and project master plan.
- **Data Architecture**: Defined relational DDL specifications for SQLite and PostgreSQL covering Multi-Tenant Organizations, RBAC, Product Catalogs, POS Shifts, Inventory Movements, and Double-Entry General Ledger.
- **Business Logic Specifications**: Formulated exact Banker's Rounding, VAT calculation formulas, FIFO / Weighted Average inventory costing algorithms, and automatic journal balancing rules.
- **Security & Threat Model**: Formulated zero-trust Electron process isolation rules, context-bridge whitelisting, DPAPI credential protection, and STRIDE risk mitigations.
- **Sync & Licensing Blueprints**: Designed asynchronous outbox synchronization protocol and Ed25519 asymmetric cryptographic license verification with air-gapped challenge-response activation.
