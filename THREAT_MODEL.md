# ALFA SOFT — THREAT MODEL & STRIDE ANALYSIS

## 1. Scope & System Boundaries

The scope of this threat model encompasses:
- Electron Desktop Workstation (Renderer, IPC, Main process).
- Local Data Store (SQLite database and file attachments).
- Network Interfaces (Local LAN P2P sync and Cloud HTTPS synchronization).
- Offline Commercial License Enforcement.

---

## 2. STRIDE Threat Analysis

| Threat Category | Potential Attack Vector | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Spoofing** | Attacker impersonates an authorized cashier or administrator on an open workstation. | Unauthorized transactions, cash theft, altered invoices. | Auto-lock screen after idle timeout, PIN confirmation on critical actions, session audit stamping. |
| **Tampering** | Local user modifies the SQLite database file directly using third-party SQLite tools to alter prices, stock, or ledger. | Falsified accounting, unaccounted stock shrinkage. | SQLite database integrity checksums, tamper-evident hash chaining on audit logs, central sync verification. |
| **Repudiation** | An employee deletes or voids a transaction and denies making the change. | Loss of accountability, undetected internal theft. | Hard deletion is prohibited for financial records. Append-only audit logs capture user ID, timestamp, and device ID. |
| **Information Disclosure** | Unauthorized staff member reads confidential profit margins, supplier purchase costs, or total revenue. | Corporate espionage, unfair bargaining by staff. | Fine-grained RBAC: Cost prices and profit KPIs are suppressed at the service query layer unless the user possesses explicit permissions. |
| **Denial of Service** | Corrupted or malicious sync payload submitted to the local or cloud sync receiver causes crash loops. | Store terminal inability to process checkouts. | Strict schema validation with Zod on all incoming sync payloads, sandboxed deserialization, transactional rollback. |
| **Elevation of Privilege** | Renderer XSS payload attempts to invoke Node.js filesystem or shell APIs via Electron IPC. | Full local machine compromise. | Context isolation enabled, Node integration disabled, IPC channels strictly whitelist validated actions. |

---

## 3. Clock Tampering & Offline License Bypass

### Threat Vector
An operator changes the Windows system date backward to extend an expired trial or subscription license.

### Countermeasures
1. **Monotonic Audit Sequence**: The application records the highest timestamp observed in `audit_logs` and `sync_outbox`.
2. **Backward Drift Detection**: If the current OS system clock is older than the latest recorded transaction timestamp by more than 10 minutes, the application enters `CLOCK_TAMPER_LOCKED` state.
3. **Recovery**: Requires re-synchronizing with the network NTP server or entering an authorized administrator emergency override code issued by the developer portal.
