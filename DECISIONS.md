# ALFA SOFT — ARCHITECTURAL DECISION RECORDS (ADR)

## ADR-001: Desktop Technology Stack — Flutter Desktop (Windows C++ Runner)
- **Status**: Accepted (Supersedes prior Electron proposal)
- **Context**: Enterprise ERP and POS systems on Windows require maximum hardware throughput, low memory footprint, zero Chromium web overhead, and instant responsiveness during high-speed barcode scanning.
- **Decision**: Adopt Flutter Desktop with the native Windows C++ Runner (`windows/runner`) and Dart 3.9+ AOT compilation.
- **Consequences**:
  - Pure native Win32 executable (`.exe`) drawing directly via DirectX 12 / Skia.
  - Sub-60MB baseline RAM footprint.
  - Zero IPC serialization latency via direct in-process C-ABI FFI calls to SQLite and Win32 hardware spoolers.
  - Symmetrical 120 FPS Arabic/English RTL/LTR rendering.

---

## ADR-002: Local Persistence Engine — SQLite 3 with WAL Mode via Dart FFI
- **Status**: Accepted
- **Context**: Workstations must operate fully offline without external database server installations on customer PCs.
- **Decision**: Utilize SQLite 3 via `sqlite3` Dart FFI bindings configured with `PRAGMA journal_mode = WAL;`, `foreign_keys = ON;`, and `synchronous = NORMAL`.
- **Consequences**: Concurrent reads alongside background writes, sub-millisecond query responses, and atomic ACID transactions.

---

## ADR-003: Asymmetric Cryptographic Licensing with Ed25519
- **Status**: Accepted
- **Context**: Commercial protection must prevent unauthorized activation without forcing continuous internet phone-home connections.
- **Decision**: Implement Ed25519 digital signatures. The private signing key resides exclusively in the isolated Developer Licensing Portal. The public verification key is embedded inside the client binary.
- **Consequences**: Offline challenge-response verification is mathematically unforgeable even with complete client binary inspection.

---

## ADR-004: Immutable Inventory Movements and Double-Entry Journals
- **Status**: Accepted
- **Context**: Direct overwriting of stock quantities or account balances leads to untraceable accounting drift and audit failures.
- **Decision**: Model all inventory changes as immutable `inventory_movements` and all financial effects as balanced `journal_entries` ($\sum \text{Debit} = \sum \text{Credit}$).
- **Consequences**: Eliminates reconciliation anomalies, enables verifiable point-in-time auditing, and simplifies synchronization conflict resolution.

---

## ADR-005: Transactional Outbox Pattern for Multi-Device Sync
- **Status**: Accepted
- **Context**: Intermittent network failures must never block retail cashiers or drop completed sales.
- **Decision**: Local business transactions append event payloads into a local `sync_outbox` table in the same atomic database transaction as operational data. A background worker pushes batches asynchronously when connectivity is present.
- **Consequences**: Guarantees at-least-once delivery, zero data loss upon abrupt network disconnects, and seamless offline-to-online transitions.
