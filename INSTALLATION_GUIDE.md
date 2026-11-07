# ALFA SOFT — INSTALLATION & DEPLOYMENT GUIDE (NATIVE WINDOWS DESKTOP)

## 1. System Requirements

### 1.1 Workstation Hardware Specifications
- **Operating System**: Windows 10 (64-bit) Version 1903 or Windows 11 / Windows Server 2019+.
- **Processor**: Intel / AMD x64 Dual-Core 2.0 GHz or higher.
- **Memory (RAM)**: 4 GB RAM minimum (Requires <60MB for baseline operation).
- **Disk Storage**: 500 MB free SSD storage for application binaries and local SQLite database.
- **Display Resolution**: 1366 $\times$ 768 minimum (1920 $\times$ 1080 recommended).

### 1.2 Peripheral Hardware Compatibility
- **Barcode Scanners**: All standard USB, Bluetooth, and wireless wedge scanners (keyboard emulation mode).
- **Receipt Printers**: Standard 80mm and 58mm thermal printers supporting ESC/POS commands (USB, Ethernet/IP, Serial).
- **Cash Drawers**: Standard RJ11 / RJ12 cash drawers connected via receipt printer kick-out port.

---

## 2. Desktop Deployment & Packaging

1. **Packaging**: Produced via `flutter build windows --release` and packaged into a self-contained Inno Setup / NSIS installer: `AlfaSoft-Setup-1.0.0.exe`.
2. **Contents of Release Directory**:
   ```
   Release/
   ├── AlfaSoft.exe              # Pure native Windows C++ / Flutter AOT binary
   ├── flutter_windows.dll       # Flutter native rendering engine
   ├── sqlite3.dll               # Native SQLite 3 engine (WAL mode)
   ├── data/                     # Compiled asset bundles (fonts, locales, icons)
   ```
3. **Execution**: Run `AlfaSoft-Setup-1.0.0.exe` to install to `%LOCALAPPDATA%\Programs\AlfaSoft`.
4. **Data Persistence**: Local database files reside safely in `%APPDATA%\AlfaSoft\data\app.db` with user-level ACL protection.

---

## 3. First-Run Setup Wizard

Upon initial launch:
1. **Language & Regional Settings**: Choose Arabic (RTL) or English (LTR) and primary operating currency.
2. **License Activation**:
   - Option A: Enter Online License Key and click "Activate".
   - Option B: Generate Offline Challenge Code for air-gapped activation.
3. **Company Profile**: Enter Commercial Name, Tax Identification Number, and upload Company Logo.
4. **Primary Branch & Warehouse**: Define the default operating branch and warehouse for this terminal.
5. **Administrator Credentials**: Establish the master local administrator username, email, and secure password.
