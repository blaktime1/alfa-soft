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
      // 1. Check if payroll run already exists for this month
      final existingRunRows = tx.select(
        'SELECT * FROM payroll_runs WHERE company_id = ? AND period_month = ?',
        [companyId, periodMonth],
      );

      String runId;
      final now = DateTime.now();

      if (existingRunRows.isNotEmpty) {
        final existingRun = existingRunRows.first;
        final status = existingRun['status'] as String;
        if (status == 'POSTED_TO_JOURNAL' || status == 'APPROVED') {
          throw StateError(
            'تم اعتماد وترحيل مسير رواتب شهر $periodMonth مسبقاً في الدفاتر المحاسبية. لا يمكن إعادة توليده لمنع ازدواجية الصرف.',
          );
        }
        // If it was DRAFT, delete old slips so we can recalculate freshly
        runId = existingRun['id'] as String;
        tx.execute('DELETE FROM salary_slips WHERE payroll_run_id = ?', [runId]);
      } else {
        runId = _uuid.v4();
      }

      // 2. Fetch active employees
      final empRows = tx.select(
        "SELECT * FROM employees WHERE company_id = ? AND status = 'ACTIVE'",
        [companyId],
      );

      if (empRows.isEmpty) {
        throw StateError('لا يوجد موظفون نشطون مسجلون لتوليد مسير الرواتب لهذا الشهر.');
      }

      int totalGross = 0;
      int totalDeductions = 0;
      int totalNet = 0;

      final empCalculations = <Map<String, dynamic>>[];

      for (final row in empRows) {
        final empId = row['id'] as String;
        final basic = row['basic_salary'] as int;
        final housing = row['housing_allowance'] as int? ?? 0;
        final transport = row['transport_allowance'] as int? ?? 0;
        final allowances = housing + transport;
        final gross = basic + allowances;

        // Query pending advances for this employee eligible up to this month
        final advRows = tx.select('''
          SELECT COALESCE(SUM(amount_cents), 0) as total_advances
          FROM salary_advances
          WHERE company_id = ? AND employee_id = ? AND status = 'PENDING' AND repayment_month <= ?
        ''', [companyId, empId, periodMonth]);

        int advances = 0;
        if (advRows.isNotEmpty) {
          advances = advRows.first['total_advances'] as int? ?? 0;
        }

        // Deductions capped at gross salary
        final deductions = advances > gross ? gross : advances;
        final net = gross - deductions;

        totalGross += gross;
        totalDeductions += deductions;
        totalNet += net;

        empCalculations.add({
          'empId': empId,
          'name': row['full_name'] as String,
          'basic': basic,
          'allowances': allowances,
          'deductions': deductions,
          'net': net,
        });
      }

      // Upsert Payroll Run Header
      if (existingRunRows.isNotEmpty) {
        tx.execute(
          '''
          UPDATE payroll_runs
          SET total_gross = ?, total_deductions = ?, total_net = ?, status = 'DRAFT'
          WHERE id = ?
          ''',
          [totalGross, totalDeductions, totalNet, runId],
        );
      } else {
        tx.execute(
          '''
          INSERT INTO payroll_runs (
            id, company_id, period_month, total_gross, total_deductions, total_net, status, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, 'DRAFT', ?)
          ''',
          [runId, companyId, periodMonth, totalGross, totalDeductions, totalNet, now.toIso8601String()],
        );
      }

      final slips = <SalarySlip>[];

      for (final calc in empCalculations) {
        final slipId = _uuid.v4();
        tx.execute(
          '''
          INSERT INTO salary_slips (
            id, payroll_run_id, employee_id, basic_salary, allowances, deductions, net_salary, payment_method
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 'BANK_TRANSFER')
          ''',
          [
            slipId,
            runId,
            calc['empId'],
            calc['basic'],
            calc['allowances'],
            calc['deductions'],
            calc['net'],
          ],
        );

        slips.add(SalarySlip(
          id: slipId,
          payrollRunId: runId,
          employeeId: calc['empId'] as String,
          employeeName: calc['name'] as String,
          basicSalary: calc['basic'] as int,
          allowances: calc['allowances'] as int,
          deductions: calc['deductions'] as int,
          netSalary: calc['net'] as int,
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

  /// Retrieves the latest payroll run for a company
  PayrollRun? getLatestPayrollRun(String companyId) {
    final rows = _db.select(
      'SELECT * FROM payroll_runs WHERE company_id = ? ORDER BY period_month DESC, created_at DESC LIMIT 1',
      [companyId],
    );
    if (rows.isEmpty) return null;
    final run = rows.first;
    final runId = run['id'] as String;

    final slipRows = _db.select('''
      SELECT ss.*, emp.full_name
      FROM salary_slips ss
      JOIN employees emp ON ss.employee_id = emp.id
      WHERE ss.payroll_run_id = ?
    ''', [runId]);

    final slips = slipRows.map((r) => SalarySlip.fromMap(Map<String, dynamic>.from(r))).toList();
    return PayrollRun.fromMap(Map<String, dynamic>.from(run), slips);
  }

  /// Automatically posts an approved payroll run to the general ledger (Double-entry accounting)
  /// Debit: 5101 Salaries Expense
  /// Credit: 1150 Employee Advances (if deductions exist)
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
      throw StateError('مسير الرواتب غير موجود.');
    }

    final run = runRows.first;
    if (run['status'] != 'APPROVED') {
      throw StateError('لا يمكن ترحيل مسير الرواتب قبل اعتماده والموافقة عليه.');
    }

    final totalGross = run['total_gross'] as int;
    final totalDeductions = run['total_deductions'] as int;
    final totalNet = run['total_net'] as int;
    final periodMonth = run['period_month'] as String;

    accountingRepo.seedStandardChartOfAccounts(companyId);

    // Locate or seed required accounts
    final salaryExpenseAcc = accountingRepo.ensureAccount(
      companyId: companyId,
      code: '5101',
      nameAr: 'مصروفات الرواتب والأجور',
      nameEn: 'Salaries & Wages Expense',
      accountType: AccountType.expense,
    );

    final salaryPayableAcc = accountingRepo.ensureAccount(
      companyId: companyId,
      code: '2105',
      nameAr: 'أمانات ومستحقات رواتب الموظفين',
      nameEn: 'Salaries Payable',
      accountType: AccountType.liability,
    );

    final List<Map<String, dynamic>> rawLines = [
      // 1. Debit Total Gross Salary Expense
      {
        'accountId': salaryExpenseAcc.id,
        'debit': totalGross,
        'credit': 0,
        'memo': 'إجمالي استحقاق مسير رواتب شهر $periodMonth',
      },
    ];

    // 2. Credit Advances if any were deducted
    if (totalDeductions > 0) {
      final advanceAcc = accountingRepo.ensureAccount(
        companyId: companyId,
        code: '1150',
        nameAr: 'سلف وعهد الموظفين',
        nameEn: 'Employee Advances',
        accountType: AccountType.asset,
      );

      rawLines.add({
        'accountId': advanceAcc.id,
        'debit': 0,
        'credit': totalDeductions,
        'memo': 'استقطاع سلف الموظفين من مسير شهر $periodMonth',
      });
    }

    // 3. Credit Net Salaries Payable
    rawLines.add({
      'accountId': salaryPayableAcc.id,
      'debit': 0,
      'credit': totalNet,
      'memo': 'صافي مستحقات رواتب الموظفين لشهر $periodMonth الواجب سدادها',
    });

    final entry = accountingRepo.postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-PAYROLL-$periodMonth',
      entryDate: DateTime.now(),
      sourceType: 'PAYROLL',
      sourceId: payrollRunId,
      narration: 'قيد رواتب شهر $periodMonth — إجمالي: ${(totalGross / 100).toStringAsFixed(2)} - استقطاعات: ${(totalDeductions / 100).toStringAsFixed(2)} - صافي: ${(totalNet / 100).toStringAsFixed(2)}',
      rawLines: rawLines,
    );

    _db.transaction((tx) {
      tx.execute(
        '''
        UPDATE payroll_runs
        SET status = 'POSTED_TO_JOURNAL', posted_journal_entry_id = ?
        WHERE id = ?
        ''',
        [entry.id, payrollRunId],
      );

      // Mark associated pending advances up to this period as DEDUCTED
      tx.execute(
        '''
        UPDATE salary_advances
        SET status = 'DEDUCTED', payroll_run_id = ?
        WHERE company_id = ? AND status = 'PENDING' AND repayment_month <= ?
        ''',
        [payrollRunId, companyId, periodMonth],
      );
    });

    return entry;
  }

  // -------------------------------------------------------------
  // SALARY ADVANCES (سلف الموظفين وسحب جزء من الراتب)
  // -------------------------------------------------------------

  /// Records a salary advance for an employee and posts double-entry accounting entry
  SalaryAdvance recordSalaryAdvance({
    required String companyId,
    required String branchId,
    required String userId,
    required String employeeId,
    required int amountCents,
    required String paymentMethod, // 'CASH' | 'BANK'
    required String repaymentMonth, // 'YYYY-MM'
    String? notes,
    required AccountingRepository accountingRepo,
  }) {
    if (amountCents <= 0) {
      throw ArgumentError('مبلغ السلفة يجب أن يكون أكبر من الصفر');
    }

    final empRows = _db.select('SELECT full_name FROM employees WHERE id = ?', [employeeId]);
    if (empRows.isEmpty) {
      throw ArgumentError('الموظف المحدد غير موجود في النظام');
    }
    final employeeName = empRows.first['full_name'] as String;

    final id = _uuid.v4();
    final now = DateTime.now();
    final advanceNumber = 'ADV-${now.millisecondsSinceEpoch.toString().substring(5)}';

    accountingRepo.seedStandardChartOfAccounts(companyId);

    // 1150: سلف وعهد الموظفين (Asset)
    final advanceAccount = accountingRepo.ensureAccount(
      companyId: companyId,
      code: '1150',
      nameAr: 'سلف وعهد الموظفين',
      nameEn: 'Employee Advances',
      accountType: AccountType.asset,
    );

    // 1010 or 1020: الخزينة أو البنك
    final paymentCode = paymentMethod.toUpperCase() == 'BANK' ? '1020' : '1010';
    final paymentAccount = accountingRepo.getAccountByCode(companyId, paymentCode) ??
        accountingRepo.ensureAccount(
          companyId: companyId,
          code: paymentCode,
          nameAr: paymentMethod.toUpperCase() == 'BANK' ? 'الحساب البنكي / نقاط البيع' : 'الخزينة النقدية الرئيسية',
          nameEn: paymentMethod.toUpperCase() == 'BANK' ? 'Bank Account' : 'Cash',
          accountType: AccountType.asset,
        );

    // Double entry:
    // Debit: 1150 سلف الموظفين
    // Credit: 1010/1020 وسيلة الدفع
    final je = accountingRepo.postJournalEntry(
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      entryNumber: 'JE-$advanceNumber',
      entryDate: now,
      sourceType: 'SALARY_ADVANCE',
      sourceId: id,
      narration: 'سند صرف سلفة على الراتب للموظف ($employeeName) لشهر $repaymentMonth',
      rawLines: [
        {
          'accountId': advanceAccount.id,
          'debit': amountCents,
          'credit': 0,
          'memo': 'سلفة على راتب شهر $repaymentMonth - $employeeName',
        },
        {
          'accountId': paymentAccount.id,
          'debit': 0,
          'credit': amountCents,
          'memo': 'صرف سلفة للموظف $employeeName من ${paymentAccount.nameAr}',
        },
      ],
    );

    _db.execute('''
      INSERT INTO salary_advances (
        id, company_id, employee_id, advance_number, amount_cents, payment_account_id,
        payment_method, request_date, repayment_month, status, notes, journal_entry_id, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?, ?, ?, ?)
    ''', [
      id,
      companyId,
      employeeId,
      advanceNumber,
      amountCents,
      paymentAccount.id,
      paymentMethod.toUpperCase(),
      now.toIso8601String().substring(0, 10),
      repaymentMonth,
      notes,
      je.id,
      userId,
      now.toIso8601String(),
    ]);

    return SalaryAdvance(
      id: id,
      companyId: companyId,
      employeeId: employeeId,
      employeeName: employeeName,
      advanceNumber: advanceNumber,
      amountCents: amountCents,
      paymentAccountId: paymentAccount.id,
      paymentMethod: paymentMethod.toUpperCase(),
      requestDate: now,
      repaymentMonth: repaymentMonth,
      status: 'PENDING',
      notes: notes,
      journalEntryId: je.id,
      createdBy: userId,
      createdAt: now,
    );
  }

  /// Retrieves list of salary advances
  List<SalaryAdvance> getSalaryAdvances(String companyId, {String? employeeId, String? status}) {
    final where = <String>['sa.company_id = ?'];
    final params = <dynamic>[companyId];

    if (employeeId != null && employeeId.isNotEmpty) {
      where.add('sa.employee_id = ?');
      params.add(employeeId);
    }
    if (status != null && status != 'ALL') {
      where.add('sa.status = ?');
      params.add(status);
    }

    final sql = '''
      SELECT sa.*, emp.full_name as employee_name
      FROM salary_advances sa
      JOIN employees emp ON sa.employee_id = emp.id
      WHERE ${where.join(' AND ')}
      ORDER BY sa.request_date DESC, sa.created_at DESC
    ''';

    final rows = _db.select(sql, params);
    return rows.map((r) => SalaryAdvance.fromMap(Map<String, dynamic>.from(r))).toList();
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
