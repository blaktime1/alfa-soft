import 'package:uuid/uuid.dart';
import '../local/database_service.dart';
import '../../domain/entities/enterprise.dart';
import '../../domain/entities/accounting.dart';
import 'accounting_repository.dart';

class EnterpriseRepository {
  final DatabaseService _db;
  final _uuid = const Uuid();

  EnterpriseRepository(this._db);

  // -------------------------------------------------------------
  // COST CENTERS
  // -------------------------------------------------------------

  CostCenter createCostCenter({
    required String companyId,
    required String code,
    required String nameAr,
    String? nameEn,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now();
    _db.execute(
      '''
      INSERT INTO cost_centers (id, company_id, code, name_ar, name_en, is_active, created_at)
      VALUES (?, ?, ?, ?, ?, 1, ?)
      ''',
      [id, companyId, code.trim(), nameAr.trim(), nameEn?.trim(), now.toIso8601String()],
    );

    return CostCenter(
      id: id,
      companyId: companyId,
      code: code.trim(),
      nameAr: nameAr.trim(),
      nameEn: nameEn?.trim(),
      isActive: true,
      createdAt: now,
    );
  }

  List<CostCenter> getCostCenters(String companyId) {
    final rows = _db.select(
      'SELECT * FROM cost_centers WHERE company_id = ? ORDER BY code ASC',
      [companyId],
    );
    return rows.map((r) => CostCenter.fromMap(r)).toList();
  }

  // -------------------------------------------------------------
  // EMPLOYEES & HR
  // -------------------------------------------------------------

  Employee createEmployee({
    required String companyId,
    required String branchId,
    required String employeeCode,
    required String fullName,
    required String nationalId,
    required String jobTitle,
    required String department,
    required DateTime hireDate,
    required int basicSalary,
    int housingAllowance = 0,
    int transportAllowance = 0,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now();
    _db.execute(
      '''
      INSERT INTO employees (
        id, company_id, branch_id, employee_code, full_name, national_id,
        job_title, department, hire_date, basic_salary, housing_allowance,
        transport_allowance, status, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?)
      ''',
      [
        id,
        companyId,
        branchId,
        employeeCode.trim(),
        fullName.trim(),
        nationalId.trim(),
        jobTitle.trim(),
        department.trim(),
        hireDate.toIso8601String().substring(0, 10),
        basicSalary,
        housingAllowance,
        transportAllowance,
        now.toIso8601String(),
      ],
    );

    return Employee(
      id: id,
      companyId: companyId,
      branchId: branchId,
      employeeCode: employeeCode.trim(),
      fullName: fullName.trim(),
      nationalId: nationalId.trim(),
      jobTitle: jobTitle.trim(),
      department: department.trim(),
      hireDate: hireDate,
      basicSalary: basicSalary,
      housingAllowance: housingAllowance,
      transportAllowance: transportAllowance,
      status: 'ACTIVE',
      createdAt: now,
    );
  }

  List<Employee> getEmployees(String companyId, {String? status}) {
    String sql = 'SELECT * FROM employees WHERE company_id = ?';
    final params = <Object?>[companyId];

    if (status != null) {
      sql += ' AND status = ?';
      params.add(status);
    }
    sql += ' ORDER BY employee_code ASC';

    final rows = _db.select(sql, params);
    return rows.map((r) => Employee.fromMap(r)).toList();
  }

  // -------------------------------------------------------------
  // PAYROLL GENERATION & GENERAL LEDGER INTEGRATION
  // -------------------------------------------------------------

  /// Automatically calculates and generates a monthly payroll run for all active employees
  PayrollRun generatePayrollRun({
    required String companyId,
    required String periodMonth, // 'YYYY-MM'
  }) {
    return _db.transaction((tx) {
      // 1. Fetch active employees
      final empRows = tx.select(
        "SELECT * FROM employees WHERE company_id = ? AND status = 'ACTIVE'",
        [companyId],
      );

      if (empRows.isEmpty) {
        throw Exception('لا يوجد موظفون نشطون مسجلون لتوليد مسير الرواتب لهذا الشهر.');
      }

      final runId = _uuid.v4();
      final now = DateTime.now();

      int totalGross = 0;
      int totalDeductions = 0;
      int totalNet = 0;

      // Calculate totals first
      for (final row in empRows) {
        final basic = row['basic_salary'] as int;
        final housing = row['housing_allowance'] as int? ?? 0;
        final transport = row['transport_allowance'] as int? ?? 0;
        final allowances = housing + transport;
        final deductions = 0;
        final net = basic + allowances - deductions;

        totalGross += (basic + allowances);
        totalDeductions += deductions;
        totalNet += net;
      }

      // Insert Parent Header first (FK constraint)
      tx.execute(
        '''
        INSERT INTO payroll_runs (
          id, company_id, period_month, total_gross, total_deductions, total_net, status, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, 'DRAFT', ?)
        ''',
        [runId, companyId, periodMonth, totalGross, totalDeductions, totalNet, now.toIso8601String()],
      );

      final slips = <SalarySlip>[];

      for (final row in empRows) {
        final basic = row['basic_salary'] as int;
        final housing = row['housing_allowance'] as int? ?? 0;
        final transport = row['transport_allowance'] as int? ?? 0;
        final allowances = housing + transport;
        final deductions = 0;
        final net = basic + allowances - deductions;

        final slipId = _uuid.v4();
        tx.execute(
          '''
          INSERT INTO salary_slips (
            id, payroll_run_id, employee_id, basic_salary, allowances, deductions, net_salary, payment_method
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 'BANK_TRANSFER')
          ''',
          [slipId, runId, row['id'] as String, basic, allowances, deductions, net],
        );

        slips.add(SalarySlip(
          id: slipId,
          payrollRunId: runId,
          employeeId: row['id'] as String,
          employeeName: row['full_name'] as String,
          basicSalary: basic,
          allowances: allowances,
          deductions: deductions,
          netSalary: net,
        ));
      }

      return PayrollRun(
        id: runId,
        companyId: companyId,
        periodMonth: periodMonth,
        totalGross: totalGross,
        totalDeductions: totalDeductions,
        totalNet: totalNet,
        status: 'DRAFT',
        createdAt: now,
        slips: slips,
      );
    });
  }

  /// Approves a payroll run
  void approvePayrollRun({
    required String payrollRunId,
    required String userId,
  }) {
    _db.execute(
      '''
      UPDATE payroll_runs
      SET status = 'APPROVED', approved_by_user_id = ?
      WHERE id = ? AND status = 'DRAFT'
      ''',
      [userId, payrollRunId],
    );
  }

  /// Automatically posts an approved payroll run to the general ledger (Double-entry accounting)
  /// Debit: 5101 Salaries Expense
  /// Credit: 2105 Salaries Payable
  JournalEntry postPayrollToGeneralLedger({
    required String payrollRunId,
    required String companyId,
    required String branchId,
    required String userId,
    required AccountingRepository accountingRepo,
  }) {
    final runRows = _db.select(
      'SELECT * FROM payroll_runs WHERE id = ?',
      [payrollRunId],
    );

    if (runRows.isEmpty) {
      throw Exception('مسير الرواتب غير موجود.');
    }

    final run = runRows.first;
    if (run['status'] != 'APPROVED') {
      throw Exception('لا يمكن ترحيل مسير الرواتب قبل اعتماده والموافقة عليه.');
    }

    final totalNet = run['total_net'] as int;

    // Locate or seed required accounts
    final salaryExpenseAcc = accountingRepo.getAccountByCode(companyId, '5101') ??
        accountingRepo.createAccount(
          companyId: companyId,
          code: '5101',
          nameAr: 'مصروفات الرواتب والأجور',
          accountType: AccountType.expense,
        );

    final salaryPayableAcc = accountingRepo.getAccountByCode(companyId, '2105') ??
        accountingRepo.createAccount(
          companyId: companyId,
          code: '2105',
          nameAr: 'أمانات ومستحقات رواتب الموظفين',
          accountType: AccountType.liability,
        );

    final entry = accountingRepo.postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-PAYROLL-${run['period_month']}',
      entryDate: DateTime.now(),
      sourceType: 'PAYROLL',
      sourceId: payrollRunId,
      narration: 'قيد رواتب شهر ${run['period_month']} — إجمالي صافي: ${(totalNet / 100).toStringAsFixed(2)} ر.س',
      rawLines: [
        {
          'accountId': salaryExpenseAcc.id,
          'debit': totalNet,
          'credit': 0,
          'memo': 'إثبات استحقاق مسير رواتب شهر ${run['period_month']}',
        },
        {
          'accountId': salaryPayableAcc.id,
          'debit': 0,
          'credit': totalNet,
          'memo': 'إثبات التزام رواتب الموظفين لشهر ${run['period_month']}',
        },
      ],
    );

    _db.execute(
      '''
      UPDATE payroll_runs
      SET status = 'POSTED_TO_JOURNAL', posted_journal_entry_id = ?
      WHERE id = ?
      ''',
      [entry.id, payrollRunId],
    );

    return entry;
  }

  // -------------------------------------------------------------
  // MULTI-TIER APPROVAL WORKFLOW ENGINE
  // -------------------------------------------------------------

  /// Submits an operational document (e.g. PO, Stock Adjustment) for approval
  ApprovalRequest submitApprovalRequest({
    required String companyId,
    required String documentType,
    required String documentId,
    required String requestNumber,
    required int amount,
    required String createdByUserId,
  }) {
    return _db.transaction((tx) {
      final reqId = _uuid.v4();
      final now = DateTime.now();

      // Dynamic rule:
      // Amount <= 10,000.00 SAR (1,000,000 cents): 1 level (Manager)
      // Amount > 10,000.00 SAR: 2 levels (Manager + Finance Director)
      final requiredLevels = amount > 1000000 ? 2 : 1;

      tx.execute(
        '''
        INSERT INTO approval_requests (
          id, company_id, document_type, document_id, request_number, amount,
          status, current_step_level, required_step_levels, created_by_user_id, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, 'PENDING', 1, ?, ?, ?)
        ''',
        [reqId, companyId, documentType, documentId, requestNumber, amount, requiredLevels, createdByUserId, now.toIso8601String()],
      );

      // Create Step 1 (Manager)
      final step1Id = _uuid.v4();
      tx.execute(
        '''
        INSERT INTO approval_steps (
          id, approval_request_id, step_level, role_required, decision
        ) VALUES (?, ?, 1, 'BRANCH_MANAGER', 'PENDING')
        ''',
        [step1Id, reqId],
      );

      final steps = [
        ApprovalStep(
          id: step1Id,
          approvalRequestId: reqId,
          stepLevel: 1,
          roleRequired: 'BRANCH_MANAGER',
          decision: 'PENDING',
        ),
      ];

      // If level 2 required, create Step 2 (Finance Director)
      if (requiredLevels > 1) {
        final step2Id = _uuid.v4();
        tx.execute(
          '''
          INSERT INTO approval_steps (
            id, approval_request_id, step_level, role_required, decision
          ) VALUES (?, ?, 2, 'FINANCE_DIRECTOR', 'PENDING')
          ''',
          [step2Id, reqId],
        );
        steps.add(ApprovalStep(
          id: step2Id,
          approvalRequestId: reqId,
          stepLevel: 2,
          roleRequired: 'FINANCE_DIRECTOR',
          decision: 'PENDING',
        ));
      }

      return ApprovalRequest(
        id: reqId,
        companyId: companyId,
        documentType: documentType,
        documentId: documentId,
        requestNumber: requestNumber,
        amount: amount,
        status: 'PENDING',
        currentStepLevel: 1,
        requiredStepLevels: requiredLevels,
        createdByUserId: createdByUserId,
        createdAt: now,
        steps: steps,
      );
    });
  }

  /// Processes an approval step (Approve or Reject)
  ApprovalRequest processApprovalStep({
    required String approvalRequestId,
    required String approverUserId,
    required bool isApproved,
    String? comments,
  }) {
    return _db.transaction((tx) {
      final reqRows = tx.select(
        'SELECT * FROM approval_requests WHERE id = ?',
        [approvalRequestId],
      );

      if (reqRows.isEmpty) throw Exception('طلب الموافقة غير موجود.');
      final req = reqRows.first;

      if (req['status'] != 'PENDING') {
        throw Exception('تم البت في هذا الطلب مسبقاً (الحالة: ${req['status']}).');
      }

      final currentLevel = req['current_step_level'] as int;
      final requiredLevels = req['required_step_levels'] as int;
      final now = DateTime.now();

      // Record step decision
      tx.execute(
        '''
        UPDATE approval_steps
        SET decision = ?, approver_user_id = ?, decision_date = ?, comments = ?
        WHERE approval_request_id = ? AND step_level = ?
        ''',
        [
          isApproved ? 'APPROVED' : 'REJECTED',
          approverUserId,
          now.toIso8601String(),
          comments,
          approvalRequestId,
          currentLevel,
        ],
      );

      String newStatus = 'PENDING';
      int nextLevel = currentLevel;

      if (!isApproved) {
        // Any rejection immediately terminates the workflow as REJECTED
        newStatus = 'REJECTED';
      } else {
        if (currentLevel >= requiredLevels) {
          // Final level reached and approved
          newStatus = 'APPROVED';
        } else {
          // Advance to next approval tier
          nextLevel = currentLevel + 1;
        }
      }

      tx.execute(
        '''
        UPDATE approval_requests
        SET status = ?, current_step_level = ?
        WHERE id = ?
        ''',
        [newStatus, nextLevel, approvalRequestId],
      );

      final updatedSteps = tx.select(
        'SELECT * FROM approval_steps WHERE approval_request_id = ? ORDER BY step_level ASC',
        [approvalRequestId],
      );

      return ApprovalRequest(
        id: req['id'] as String,
        companyId: req['company_id'] as String,
        documentType: req['document_type'] as String,
        documentId: req['document_id'] as String,
        requestNumber: req['request_number'] as String,
        amount: req['amount'] as int,
        status: newStatus,
        currentStepLevel: nextLevel,
        requiredStepLevels: requiredLevels,
        createdByUserId: req['created_by_user_id'] as String,
        createdAt: DateTime.parse(req['created_at'] as String),
        steps: updatedSteps.map((s) => ApprovalStep.fromMap(s)).toList(),
      );
    });
  }

  List<ApprovalRequest> getApprovalRequests(String companyId, {String? status}) {
    String sql = 'SELECT * FROM approval_requests WHERE company_id = ?';
    final params = <Object?>[companyId];
    if (status != null) {
      sql += ' AND status = ?';
      params.add(status);
    }
    sql += ' ORDER BY created_at DESC';

    final rows = _db.select(sql, params);
    return rows.map((r) {
      final steps = _db.select(
        'SELECT * FROM approval_steps WHERE approval_request_id = ? ORDER BY step_level ASC',
        [r['id']],
      );
      return ApprovalRequest.fromMap(r, steps.map((s) => ApprovalStep.fromMap(s)).toList());
    }).toList();
  }
}
