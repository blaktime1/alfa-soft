# ALFA SOFT — BUSINESS LOGIC & CALCULATION RULES

## 1. Mathematical Standards & Financial Precision

1. **Floating Point Prohibition**:
   No floating-point data types (`FLOAT`, `DOUBLE`, `REAL`) may be used in financial calculations or monetary balances.
2. **Fixed-Point Scaling**:
   All monetary amounts are represented as fixed-scale integers in minor units (scale = 4 for sub-unit accuracy, or integer cents/halalas scaled by $10^2$ or $10^4$).
3. **Rounding Convention**:
   Half-Even Rounding (Banker's Rounding, `ROUND_HALF_EVEN`) is strictly applied during division, taxes, or currency exchange:
   $$\text{Round}(x) = \begin{cases} \lfloor x + 0.5 \rfloor & \text{if } x - \lfloor x \rfloor \neq 0.5 \\ 2 \lfloor \frac{x}{2} + 0.5 \rfloor & \text{if } x - \lfloor x \rfloor = 0.5 \end{cases}$$

---

## 2. Tax Computation Formulas

### 2.1 Tax-Exclusive Pricing (Price does NOT include VAT)
Given Unit Price $P$, Quantity $Q$, Discount Rate $D$, and Tax Rate $T$:
$$\text{Line Discount} = \text{Round}\left( P \times Q \times D \right)$$
$$\text{Net Taxable} = (P \times Q) - \text{Line Discount}$$
$$\text{Line Tax} = \text{Round}\left( \text{Net Taxable} \times T \right)$$
$$\text{Line Total} = \text{Net Taxable} + \text{Line Tax}$$

### 2.2 Tax-Inclusive Pricing (Price includes VAT)
Given Inclusive Unit Price $P_{inc}$, Quantity $Q$, and Tax Rate $T$:
$$\text{Gross Total} = P_{inc} \times Q - \text{Line Discount}$$
$$\text{Net Taxable} = \text{Round}\left( \frac{\text{Gross Total}}{1 + T} \right)$$
$$\text{Line Tax} = \text{Gross Total} - \text{Net Taxable}$$
$$\text{Line Total} = \text{Gross Total}$$

---

## 3. Inventory Costing Algorithms

### 3.1 Moving Weighted Average Cost (MAC)
On every incoming goods receipt (GRN) with Receipt Quantity $Q_{in}$ and Unit Cost $C_{in}$:
$$C_{new} = \text{Round}\left( \frac{(Q_{current} \times C_{current}) + (Q_{in} \times C_{in})}{Q_{current} + Q_{in}} \right)$$
$$Q_{new} = Q_{current} + Q_{in}$$

- On outbound sales: Unit cost remains $C_{new}$. The Cost of Goods Sold (COGS) recorded for quantity $Q_{out}$ is:
$$\text{COGS} = Q_{out} \times C_{new}$$

### 3.2 FIFO (First-In, First-Out)
- Every incoming shipment creates an immutable `cost_layer` record $(Q_{layer}, C_{layer})$.
- When items are sold, layers are consumed in ascending chronological order of arrival.
- Total COGS equals the sum of consumed layers:
$$\text{COGS} = \sum_{k} (q_k \times c_k) \quad \text{where } \sum_k q_k = Q_{out}$$

---

## 4. Automated Double-Entry Journal Rules

### 4.1 Cash POS Sale
- **Trigger**: POS Cashier completes cash sale.
- **Journal Entries Generated**:
  1. `DEBIT`: Cashbox Account (Asset) with Grand Total.
  2. `CREDIT`: Sales Revenue Account (Revenue) with Net Taxable Subtotal.
  3. `CREDIT`: VAT Output Payable (Liability) with Total VAT.
  4. `DEBIT`: Cost of Goods Sold Account (Expense) with Calculated COGS.
  5. `CREDIT`: Inventory Asset Account (Asset) with Calculated COGS.
- **Integrity Rule**: $\sum \text{Debit} = \sum \text{Credit}$.

### 4.2 Credit Sale on Customer Account
- **Trigger**: Sales invoice issued with payment status `CREDIT`.
- **Journal Entries Generated**:
  1. `DEBIT`: Accounts Receivable (Customer Subledger) with Grand Total.
  2. `CREDIT`: Sales Revenue with Net Subtotal.
  3. `CREDIT`: VAT Output Payable with Total VAT.
  4. `DEBIT`: Cost of Goods Sold with COGS.
  5. `CREDIT`: Inventory Asset with COGS.

### 4.3 Sales Return & Credit Note
- **Trigger**: Customer returns goods against an existing posted invoice.
- **Journal Entries Generated**:
  1. `DEBIT`: Sales Returns / Revenue Adjustment with Net Subtotal.
  2. `DEBIT`: VAT Output Payable with Returned VAT.
  3. `CREDIT`: Accounts Receivable or Cashbox with Grand Total.
  4. `DEBIT`: Inventory Asset with Original Historical Unit Cost.
  5. `CREDIT`: Cost of Goods Sold with Original Historical Unit Cost.

---

## 5. POS Shift & Drawer Reconciliation Rules

1. **Shift Opening**: Cashier enters starting float amount $F_0$. Shift status transitions from `CLOSED` to `OPEN`.
2. **Intra-Shift Tracking**:
   $$\text{Expected Cash} = F_0 + \sum \text{Cash Sales} + \sum \text{Cash In} - \sum \text{Cash Drops} - \sum \text{Cash Refunds}$$
3. **Shift Closing**: Cashier performs blind count $C_{actual}$.
   $$\text{Variance} = C_{actual} - \text{Expected Cash}$$
   - If $\text{Variance} > 0$: Automatic posting to Cash Surplus (Income).
   - If $\text{Variance} < 0$: Automatic posting to Cash Shortage (Expense).
4. No cashier may open a new shift on a terminal while another shift is actively open on that terminal.
