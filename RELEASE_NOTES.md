# ALFA SOFT — RELEASE NOTES

## Version 1.0.0 — Production Release (Offline Enterprise ERP & POS)
*Release Date: 2026-11-07*

### Executive Overview
**ALFA SOFT Version 1.0.0** is a complete, enterprise-grade, offline-first ERP and Point of Sale (POS) desktop system built natively on Flutter Windows (C++ Runner) with local SQLite WAL persistence and zero web/Chromium dependencies.

### Comprehensive Milestone Delivery
- **Phase 0 & 1 — Architecture & Windows Native Foundation**: Pure Flutter Windows C++ runner, SQLite 3 FFI with WAL mode, bankers rounding, VAT calculator, and First-Run Wizard.
- **Phase 2 — Core Business Hierarchy & RBAC**: Multi-branch, multi-warehouse, product catalog, customer/supplier partner profiles with credit limits, and granular role permissions.
- **Phase 3 — Business Operations & POS**: Purchase Orders, Goods Receipt (GRN) with Moving Average Costing (MAC), Inter-Warehouse stock transfers, stock adjustments, and high-speed POS shifts with blind closing and suspended carts.
- **Phase 4 — Double-Entry Accounting Engine**: 5-tier standard Chart of Accounts hierarchy, balanced journal posting engine, Trial Balance, Real-Time Income Statement (P&L), and Balance Sheet.
- **Phase 5 — Reporting, Printing & Documents**: ZATCA FATOORA Base64 TLV QR Code generation, raw ESC/POS thermal printer byte generation (80mm & 58mm), A4 bilingual tax invoice PDF generator, and UTF-8 BOM CSV/Excel data exporter.
- **Phase 6 — Offline & LAN Multi-Device Synchronization**: Transactional Outbox pattern, peer discovery, SHA-256 encrypted batch transmission, and hybrid conflict resolution (strict ledger immutability + LWW catalog merge).
- **Phase 7 — Universal Data Import & Migration Center**: Delimiter auto-detect CSV/TSV parser, dry-run schema validation with error preview, and transactional atomic bulk ingestion.
- **Phase 8 — Ed25519 Cryptographic Licensing & Hardware Fingerprinting**: Deterministic Windows machine fingerprinting (`ALFA-XXXX-XXXX-XXXX`), offline Ed25519 key verification, and vendor Developer Portal generator tool.
- **Phase 9 — Advanced Enterprise Suite**: Cost Centers & Projects, Employee Directory with salary breakdown, Automated Monthly Payroll runs, automated General Ledger salary expense posting, and Multi-Tier Approval Workflows.
- **Phase 10 — Security, Hardening & QA Resilience**: Concurrency stress tests under 200 rapid balanced writes, catastrophic power-outage transaction rollback validation, and immutable audit logs.
- **Phase 11 — Packaging & Production Installer**: Automated release build pipeline and Inno Setup 6 production installer script (`AlfaSoft-Setup-1.0.0-x64.exe`).

### Verification & Quality Assurance
- **52 / 52 automated tests passing (100% pass rate)**.
- **0 static analysis issues (`flutter analyze` clean)**.

