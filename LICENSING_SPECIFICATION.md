# ALFA SOFT — COMMERCIAL LICENSING & CRYPTOGRAPHIC SPECIFICATION

## 1. Cryptographic Design (Ed25519)

ALFA SOFT utilizes asymmetric public-key cryptography to ensure tamper-proof license verification without requiring continuous internet connectivity:
- **Algorithm**: **Ed25519** (Edwards-curve Digital Signature Algorithm).
- **Public Key**: Hardcoded as an immutable constant inside the trusted desktop application main process.
- **Private Key**: Kept exclusively within the isolated Developer Licensing Portal environment. Never embedded or distributed in any client bundle.

---

## 2. License Payload Specification

```typescript
export interface LicensePayload {
  licenseId: string;           // Unique license identifier (UUID v4)
  customerName: string;        // Company / Customer name
  taxNumber?: string;          // Customer tax identification
  edition: 'STANDARD' | 'PROFESSIONAL' | 'ENTERPRISE';
  licenseType: 'TRIAL' | 'MONTHLY' | 'ANNUAL' | 'LIFETIME';
  issuedAt: string;            // ISO 8601 UTC
  expiresAt: string | null;    // Null for lifetime
  gracePeriodDays: number;     // Configurable (e.g., 7 days)
  maxBranches: number;
  maxWarehouses: number;
  maxTerminals: number;
  maxUsers: number;
  enabledModules: string[];    // ['POS', 'INVENTORY', 'ACCOUNTING', 'HR', 'SYNC']
  hardwareBinding: {
    enforceHardwareLock: boolean;
    deviceFingerprintHash: string; // SHA-256 of combined hardware identifiers
  };
}

export interface SignedLicenseFile {
  payload: LicensePayload;
  signature: string;           // Base64-encoded Ed25519 signature of Canonical JSON payload
  developerKeyId: string;      // Key rotation identifier
}
```

---

## 3. Hardware Fingerprinting Algorithm

The client generates a hardware fingerprint by aggregating system-level hardware serial numbers:
$$\text{RawString} = \text{CPUID} + "|" + \text{MotherboardUUID} + "|" + \text{PrimaryDiskSerial} + "|" + \text{MACAddress}$$
$$\text{DeviceFingerprint} = \text{SHA256}(\text{RawString})$$
- A configurable fuzzy matching tolerance accommodates minor peripheral or NIC replacements while preventing image cloning onto entirely distinct physical hardware.

---

## 4. Activation Workflows

### 4.1 Online Activation
1. Workstation sends `(LicenseKey, DeviceFingerprint)` to Developer Activation API via TLS.
2. Developer Portal checks seat availability, registers the device, signs a new `SignedLicenseFile`, and returns it.
3. Desktop client verifies signature with public key and caches the license locally.

### 4.2 Air-Gapped / Offline Activation (Challenge-Response)
1. On an offline PC, client generates an **Activation Request String**:
   $$\text{Challenge} = \text{Base64}(\text{JSON}(\{ \text{LicenseKey}, \text{DeviceFingerprint}, \text{Timestamp} \}))$$
2. Customer exports this code to USB or sends it to the developer via email / WhatsApp.
3. Developer enters the challenge into the **Developer Licensing Portal**.
4. Portal validates the request and generates a cryptographically signed `.alfalic` license file.
5. Customer imports the file into ALFA SOFT. The app verifies the signature and activates immediately.

---

## 5. Expiration Handling & Data Preservation

1. **Pre-Expiry Warning**: 14 days and 7 days prior to expiry, a persistent notification banner informs administrators.
2. **Grace Period**: Post-expiration, a 7-day grace period allows full operation while prompting for renewal.
3. **Restricted Mode**: Once the grace period lapses:
   - System enters read-only inspection and export mode.
   - POS checkout and new invoice posting are locked.
   - **Data Integrity Guarantee**: Customer records and databases are **never** deleted, wiped, or corrupted upon license expiration.
   - Data export (Excel, CSV, Backup Archive) remains accessible to authorized administrators.
