class CostCenter {
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final bool isActive;
  final DateTime createdAt;

  const CostCenter({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    this.nameEn,
    this.isActive = true,
    required this.createdAt,
  });

  factory CostCenter.fromMap(Map<String, dynamic> map) {
    return CostCenter(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      code: map['code'] as String,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String?,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'code': code,
      'name_ar': nameAr,
      'name_en': nameEn,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class Employee {
  final String id;
  final String companyId;
  final String branchId;
  final String employeeCode;
  final String fullName;
  final String nationalId;
  final String jobTitle;
  final String department;
  final DateTime hireDate;
  final int basicSalary; // Cents/halalas
  final int housingAllowance;
  final int transportAllowance;
  final String status; // 'ACTIVE', 'ON_LEAVE', 'TERMINATED'
  final DateTime createdAt;

  const Employee({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.employeeCode,
    required this.fullName,
    required this.nationalId,
    required this.jobTitle,
    required this.department,
    required this.hireDate,
    required this.basicSalary,
    this.housingAllowance = 0,
    this.transportAllowance = 0,
    this.status = 'ACTIVE',
    required this.createdAt,
  });

  int get grossSalary => basicSalary + housingAllowance + transportAllowance;

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      branchId: map['branch_id'] as String,
      employeeCode: map['employee_code'] as String,
      fullName: map['full_name'] as String,
      nationalId: map['national_id'] as String,
      jobTitle: map['job_title'] as String,
      department: map['department'] as String,
      hireDate: DateTime.parse(map['hire_date'] as String),
      basicSalary: map['basic_salary'] as int,
      housingAllowance: map['housing_allowance'] as int? ?? 0,
      transportAllowance: map['transport_allowance'] as int? ?? 0,
      status: map['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'branch_id': branchId,
      'employee_code': employeeCode,
      'full_name': fullName,
      'national_id': nationalId,
      'job_title': jobTitle,
      'department': department,
      'hire_date': hireDate.toIso8601String().substring(0, 10),
      'basic_salary': basicSalary,
      'housing_allowance': housingAllowance,
      'transport_allowance': transportAllowance,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class SalarySlip {
  final String? id;
  final String payrollRunId;
  final String employeeId;
  final String? employeeName;
  final int basicSalary;
  final int allowances;
  final int deductions;
  final int netSalary;
  final String paymentMethod;
  final String? notes;

  const SalarySlip({
    this.id,
    required this.payrollRunId,
    required this.employeeId,
    this.employeeName,
    required this.basicSalary,
    required this.allowances,
    required this.deductions,
    required this.netSalary,
    this.paymentMethod = 'BANK_TRANSFER',
    this.notes,
  });

  factory SalarySlip.fromMap(Map<String, dynamic> map) {
    return SalarySlip(
      id: map['id'] as String?,
      payrollRunId: map['payroll_run_id'] as String,
      employeeId: map['employee_id'] as String,
      employeeName: map['full_name'] as String?,
      basicSalary: map['basic_salary'] as int,
      allowances: map['allowances'] as int? ?? 0,
      deductions: map['deductions'] as int? ?? 0,
      netSalary: map['net_salary'] as int,
      paymentMethod: map['payment_method'] as String? ?? 'BANK_TRANSFER',
      notes: map['notes'] as String?,
    );
  }
}

class PayrollRun {
  final String id;
  final String companyId;
  final String periodMonth;
  final int totalGross;
  final int totalDeductions;
  final int totalNet;
  final String status; // 'DRAFT', 'APPROVED', 'POSTED_TO_JOURNAL'
  final String? approvedByUserId;
  final String? postedJournalEntryId;
  final DateTime createdAt;
  final List<SalarySlip> slips;

  const PayrollRun({
    required this.id,
    required this.companyId,
    required this.periodMonth,
    required this.totalGross,
    required this.totalDeductions,
    required this.totalNet,
    this.status = 'DRAFT',
    this.approvedByUserId,
    this.postedJournalEntryId,
    required this.createdAt,
    this.slips = const [],
  });

  factory PayrollRun.fromMap(Map<String, dynamic> map, [List<SalarySlip> slips = const []]) {
    return PayrollRun(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      periodMonth: map['period_month'] as String,
      totalGross: map['total_gross'] as int,
      totalDeductions: map['total_deductions'] as int,
      totalNet: map['total_net'] as int,
      status: map['status'] as String? ?? 'DRAFT',
      approvedByUserId: map['approved_by_user_id'] as String?,
      postedJournalEntryId: map['posted_journal_entry_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      slips: slips,
    );
  }
}

class ApprovalStep {
  final String id;
  final String approvalRequestId;
  final int stepLevel;
  final String? approverUserId;
  final String roleRequired;
  final String decision; // 'PENDING', 'APPROVED', 'REJECTED'
  final DateTime? decisionDate;
  final String? comments;

  const ApprovalStep({
    required this.id,
    required this.approvalRequestId,
    required this.stepLevel,
    this.approverUserId,
    required this.roleRequired,
    this.decision = 'PENDING',
    this.decisionDate,
    this.comments,
  });

  factory ApprovalStep.fromMap(Map<String, dynamic> map) {
    return ApprovalStep(
      id: map['id'] as String,
      approvalRequestId: map['approval_request_id'] as String,
      stepLevel: map['step_level'] as int,
      approverUserId: map['approver_user_id'] as String?,
      roleRequired: map['role_required'] as String,
      decision: map['decision'] as String,
      decisionDate: map['decision_date'] != null ? DateTime.parse(map['decision_date'] as String) : null,
      comments: map['comments'] as String?,
    );
  }
}

class ApprovalRequest {
  final String id;
  final String companyId;
  final String documentType; // 'PURCHASE_ORDER', 'STOCK_ADJUSTMENT', 'PAYROLL'
  final String documentId;
  final String requestNumber;
  final int amount;
  final String status; // 'PENDING', 'APPROVED', 'REJECTED'
  final int currentStepLevel;
  final int requiredStepLevels;
  final String createdByUserId;
  final DateTime createdAt;
  final List<ApprovalStep> steps;

  const ApprovalRequest({
    required this.id,
    required this.companyId,
    required this.documentType,
    required this.documentId,
    required this.requestNumber,
    required this.amount,
    this.status = 'PENDING',
    this.currentStepLevel = 1,
    this.requiredStepLevels = 1,
    required this.createdByUserId,
    required this.createdAt,
    this.steps = const [],
  });

  factory ApprovalRequest.fromMap(Map<String, dynamic> map, [List<ApprovalStep> steps = const []]) {
    return ApprovalRequest(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      documentType: map['document_type'] as String,
      documentId: map['document_id'] as String,
      requestNumber: map['request_number'] as String,
      amount: map['amount'] as int,
      status: map['status'] as String? ?? 'PENDING',
      currentStepLevel: map['current_step_level'] as int? ?? 1,
      requiredStepLevels: map['required_step_levels'] as int? ?? 1,
      createdByUserId: map['created_by_user_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      steps: steps,
    );
  }
}
