/// ALFA SOFT — CORE SYSTEM ENUMS
library;

enum CurrencyCode {
  sar('SAR', 'ريال سعودي', 'Saudi Riyal'),
  yer('YER', 'ريال يمني', 'Yemeni Rial'),
  usd('USD', 'دولار أمريكي', 'US Dollar'),
  aed('AED', 'درهم إماراتي', 'UAE Dirham'),
  kwd('KWD', 'دينار كويتي', 'Kuwaiti Dinar'),
  egp('EGP', 'جنيه مصري', 'Egyptian Pound');

  final String code;
  final String nameAr;
  final String nameEn;

  const CurrencyCode(this.code, this.nameAr, this.nameEn);
}

enum StandardRole {
  superAdmin('SUPER_ADMIN', 'مدير النظام العام'),
  branchManager('BRANCH_MANAGER', 'مدير فرع'),
  accountant('ACCOUNTANT', 'محاسب عام'),
  cashier('CASHIER', 'كاشير نقاط بيع'),
  inventoryManager('INVENTORY_MANAGER', 'أمين مستودع');

  final String code;
  final String titleAr;

  const StandardRole(this.code, this.titleAr);
}

enum InvoiceStatus {
  draft('DRAFT'),
  posted('POSTED'),
  voided('VOIDED'),
  returned('RETURNED');

  final String code;
  const InvoiceStatus(this.code);
}

enum PaymentStatus {
  paid('PAID'),
  partiallyPaid('PARTIALLY_PAID'),
  unpaid('UNPAID');

  final String code;
  const PaymentStatus(this.code);
}

enum PaymentMethod {
  cash('CASH', 'نقداً'),
  card('CARD', 'بطاقة شبكة'),
  bankTransfer('BANK_TRANSFER', 'تحويل بنكي'),
  credit('CREDIT', 'آجل / حساب عميل');

  final String code;
  final String nameAr;
  const PaymentMethod(this.code, this.nameAr);
}

enum MovementType {
  purchaseReceipt('PURCHASE_RECEIPT'),
  saleIssue('SALE_ISSUE'),
  transferIn('TRANSFER_IN'),
  transferOut('TRANSFER_OUT'),
  adjustment('ADJUSTMENT'),
  returnRestock('RETURN_RESTOCK');

  final String code;
  const MovementType(this.code);
}

enum CostingMethod {
  weightedAverage('WEIGHTED_AVERAGE'),
  fifo('FIFO');

  final String code;
  const CostingMethod(this.code);
}

enum AccountType {
  asset('ASSET', 'أصول'),
  liability('LIABILITY', 'خصوم / التزامات'),
  equity('EQUITY', 'حقوق ملكية'),
  revenue('REVENUE', 'إيرادات'),
  expense('EXPENSE', 'مصروفات');

  final String code;
  final String nameAr;
  const AccountType(this.code, this.nameAr);
}

enum ShiftStatus {
  open('OPEN'),
  closed('CLOSED');

  final String code;
  const ShiftStatus(this.code);
}

enum LicenseEdition {
  standard('STANDARD', 'النسخة القياسية'),
  professional('PROFESSIONAL', 'النسخة الاحترافية'),
  enterprise('ENTERPRISE', 'نسخة المؤسسات الكبرى');

  final String code;
  final String titleAr;
  const LicenseEdition(this.code, this.titleAr);
}

enum LicenseType {
  trial('TRIAL'),
  monthly('MONTHLY'),
  annual('ANNUAL'),
  lifetime('LIFETIME');

  final String code;
  const LicenseType(this.code);
}
