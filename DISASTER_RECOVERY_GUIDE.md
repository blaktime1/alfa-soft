# ALFA SOFT — DISASTER RECOVERY & INCIDENT PLAYBOOK

## 1. Severity Levels & Incident Classification

- **Severity 1 (Critical Business Halt)**: Local SQLite corruption, primary server failure, or inability to process POS sales across all terminals.
- **Severity 2 (Degraded Operation)**: Cloud sync failure, single peripheral printer failure, or un-synchronized offline terminal.
- **Severity 3 (Isolated Defect)**: Discrepancy in reporting view, non-critical background task delay.

---

## 2. Emergency Recovery Playbooks

### Playbook 1: Local SQLite Database Corruption
**Symptom**: Application fails on boot with `SQLITE_CORRUPT: database disk image is malformed`.

**Procedure**:
1. Terminate all active ALFA SOFT instances.
2. Open PowerShell in `%APPDATA%\AlfaSoft\data`.
3. Preserve the corrupted file immediately:
   ```powershell
   Copy-Item "app.db" "app.db.corrupt_[timestamp]"
   ```
4. Attempt automated SQLite `.recover`:
   ```powershell
   sqlite3 "app.db" ".recover" | sqlite3 "app_recovered.db"
   ```
5. If recovery succeeds:
   - Validate integrity: `sqlite3 "app_recovered.db" "PRAGMA integrity_check;"`
   - Swap recovered DB to active: `Rename-Item "app_recovered.db" "app.db"`
6. If recovery fails:
   - Locate the most recent automated snapshot in `%APPDATA%\AlfaSoft\backups\daily\`.
   - Restore using the **Safe Restoration Protocol** via the ALFA SOFT Emergency Recovery Utility.

---

### Playbook 2: Total Workstation Hardware Loss
**Symptom**: Complete physical failure of a cashier PC (motherboard/drive destroyed).

**Procedure**:
1. Provision a replacement Windows machine with minimum system specifications.
2. Install `AlfaSoft-Setup-1.0.0.exe`.
3. Launch ALFA SOFT and select **Restore Existing Node**.
4. In the Developer Portal, log in as administrator and issue a **Device Seat Transfer** to reassign the license to the new machine hardware fingerprint.
5. In ALFA SOFT:
   - If Cloud Sync is active: Enter Company Credentials and perform an initial sync pull. All historical product masters, prices, and past records download automatically.
   - If running fully offline: Import the most recent `.alfabackup` file created from the daily USB archive.
6. Perform test barcode scan and test receipt print. Resume sales operations.

---

### Playbook 3: Extended Network Partition / Cloud Outage
**Symptom**: Internet connectivity is severed for multiple days.

**Procedure**:
1. Workstations remain 100% operational in **Autonomous Offline Mode**. All sales, stock changes, and payments continue locally.
2. Ensure cashier shifts are closed normally at the end of each day.
3. Daily local backups to removable USB drives should continue without interruption.
4. When internet connectivity is restored:
   - The sync indicator transitions from yellow (Offline) to green (Connected).
   - The `SyncWorker` automatically uploads accumulated outbox events with exponential backoff.
   - Check the **Sync Conflict Review** screen to ensure no ambiguous updates require manual approval.
