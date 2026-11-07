# ALFA SOFT — QUALITY ASSURANCE & AUTOMATED TEST PLAN

## 1. Testing Pyramid & QA Objectives

Quality assurance in ALFA SOFT is governed by the principle that financial correctness, transaction integrity, and crash resilience take precedence over visual speed.

```
       / \
      / E2E \       15% — End-to-End Real Workflows (Playwright / Electron)
     /-------\
    /  Integ  \     35% — Service Boundaries, SQLite Transactions, Sync Engines
   /-----------\
  /    Unit     \   50% — Calculations, Costing, Rounding, RBAC, Validation
 /---------------\
```

---

## 2. Test Suites & Verification Criteria

### 2.1 Suite A: Financial & Accounting Calculations (Unit Tests)
- **Rounding Accuracy**: Verify Banker's Rounding across 10,000 randomized fractional transactions. No accumulated drift permitted.
- **Tax Calculation**: Validate inclusive and exclusive VAT amounts against national tax authority sample vectors.
- **Journal Balancing**: Every generated journal voucher must satisfy $\sum \text{Debit} - \sum \text{Credit} = 0$.

### 2.2 Suite B: Inventory Costing & Stock Integrity (Integration Tests)
- **Moving Average Costing**: Simulate 50 sequential purchases at varying unit prices interleaved with 200 sales; verify inventory valuation precisely matches ending stock $\times$ MAC.
- **FIFO Layer Depletion**: Confirm that earliest cost layers are depleted first, and returns correctly restore original layer unit costs.
- **Negative Stock Guard**: Attempt to sell items with stock = 0; verify policy enforcement rejects the write when strict locking is active.

### 2.3 Suite C: Concurrency & SQLite Stress (Reliability Tests)
- Simulate 10 concurrent worker threads submitting POS checkout requests to the same local SQLite database under WAL mode.
- Verify zero `SQLITE_BUSY` failures, zero deadlocks, and total sales recorded equals exactly 10 $\times$ batch count.

### 2.4 Suite D: Offline Partition & Sync Recovery (E2E Tests)
1. Initialize two isolated client databases (Station A & Station B).
2. Sever network connectivity.
3. Process 20 sales on Station A and 25 sales on Station B.
4. Re-establish network connectivity and trigger bi-directional sync.
5. Verify both stations receive complete transaction logs without duplication, and central PostgreSQL reflects exactly 45 unique sales.

### 2.5 Suite E: Security & Licensing Tampering (Security Tests)
- Manually edit the SQLite license table or system clock date backward by 30 days.
- Verify client boots directly into `TAMPER_DETECTED` lock screen.
- Attempt to tamper with signature bytes in `.alfalic` file; confirm signature verification fails and prevents normal startup.
