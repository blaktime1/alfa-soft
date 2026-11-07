# ALFA SOFT — SECURITY ARCHITECTURE & POLICIES (NATIVE WINDOWS DESKTOP)

## 1. Native AOT Compilation & Process Security

ALFA SOFT executes as a compiled Ahead-Of-Time (AOT) native Windows binary, eliminating the attack surfaces typically associated with web wrappers:
1. **Zero Browser / DOM Attack Surface**:
   - No JavaScript engine, no DOM, no Node.js runtime vulnerabilities.
   - Cross-Site Scripting (XSS) is architecturally impossible because widgets are compiled Dart objects drawn directly to the DirectX surface.
2. **Sound Null Safety**:
   - Guarantees 100% memory type safety at compile time, eliminating null-pointer dereference crashes in mission-critical retail POS loops.
3. **Restricted Process Permissions**:
   - The desktop executable runs strictly under standard Windows user permissions (least-privilege model), requiring elevation only during installer execution.

---

## 2. Authentication & Credential Management

1. **Password Hashing**:
   Passwords are never stored in plaintext. Passwords are hashed using **Argon2id** (memory cost: 64MB, iterations: 3, parallelism: 1) or **bcrypt** (cost factor: 12) via native Dart crypto.
2. **Local Session Protection**:
   Session tokens and encryption keys are stored encrypted on disk using the **Windows Data Protection API (DPAPI)** via `win32` APIs.
3. **Multi-Tenant Data Isolation**:
   Every database query filters strictly by `company_id` and `branch_id`. Tenant isolation is enforced at the repository/DAO layer.

---

## 3. Database & Query Safety

1. **SQL Injection Immunization**:
   All database interactions utilize strictly parameterized SQL statements through Dart FFI bindings. Dynamic string concatenation in SQL queries is forbidden.
2. **Local Database Protection**:
   The SQLite database file is stored in `%APPDATA%/AlfaSoft/data/` with operating system file permissions restricted exclusively to the active Windows user account.
3. **Database Integrity Verification**:
   On application boot, `PRAGMA integrity_check;` is executed. Any corruption triggers the disaster recovery subsystem.

---

## 4. Cryptographic Standards

- **Licensing & Code Verification**: Asymmetric **Ed25519** digital signatures verified natively in Dart.
- **Data at Rest & Backup Encryption**: **AES-256-GCM** with authenticated 128-bit authentication tags.
- **Transport Security**: **TLS 1.3** mandatory for all cloud synchronization communication with certificate pinning.
