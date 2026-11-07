enum ResolutionOutcome {
  applied,
  rejected,
  localWins,
  manualReviewNeeded,
}

class ConflictResolutionResult {
  final ResolutionOutcome outcome;
  final String reason;
  final Map<String, dynamic>? resolvedPayload;

  const ConflictResolutionResult({
    required this.outcome,
    required this.reason,
    this.resolvedPayload,
  });

  factory ConflictResolutionResult.applied(Map<String, dynamic> payload, [String reason = 'التغيير معتمد']) {
    return ConflictResolutionResult(
      outcome: ResolutionOutcome.applied,
      reason: reason,
      resolvedPayload: payload,
    );
  }

  factory ConflictResolutionResult.rejected(String reason) {
    return ConflictResolutionResult(
      outcome: ResolutionOutcome.rejected,
      reason: reason,
    );
  }

  factory ConflictResolutionResult.localWins([String reason = 'النسخة المحلية أحدث (Local Wins)']) {
    return ConflictResolutionResult(
      outcome: ResolutionOutcome.localWins,
      reason: reason,
    );
  }

  factory ConflictResolutionResult.manualReview(String reason) {
    return ConflictResolutionResult(
      outcome: ResolutionOutcome.manualReviewNeeded,
      reason: reason,
    );
  }
}

/// Conflict Resolution Engine enforcing Financial Immutability & Last-Write-Wins (LWW)
class ConflictResolutionEngine {
  const ConflictResolutionEngine();

  static const immutableEntityTypes = {
    'SALES_INVOICE',
    'JOURNAL_ENTRY',
    'JOURNAL_LINE',
    'PAYMENT',
    'PURCHASE_GRN',
    'INVENTORY_MOVEMENT',
  };

  ConflictResolutionResult resolve({
    required String entityType,
    required String operation,
    Map<String, dynamic>? localState,
    required Map<String, dynamic> remoteState,
  }) {
    final upperType = entityType.toUpperCase();

    // 1. Strict Financial Immutability Rule
    if (immutableEntityTypes.contains(upperType)) {
      if (operation == 'UPDATE' || operation == 'DELETE') {
        return ConflictResolutionResult.rejected(
          'المستندات المالية والقيود المحاسبية ($entityType) غير قابلة للتعديل أو الحذف، بل يجب تسويتها بقيود عكسية فقط.',
        );
      }
      if (operation == 'CREATE') {
        if (localState != null) {
          // Document already exists with this ID - idempotent duplicate
          return ConflictResolutionResult.rejected(
            'المستند المالي برقم الهوية ${remoteState['id']} مسجل مسبقاً في النظام المحلي.',
          );
        }
        return ConflictResolutionResult.applied(remoteState, 'إدراج مستند مالي جديد متوافق');
      }
    }

    // 2. Master Data Entities (Last-Write-Wins Strategy)
    if (localState == null) {
      // Local record does not exist -> Apply remote creation
      return ConflictResolutionResult.applied(remoteState, 'إدراج سجل رئيسي جديد');
    }

    final localVersion = localState['version'] as int? ?? 1;
    final remoteVersion = remoteState['version'] as int? ?? 1;

    if (remoteVersion > localVersion) {
      return ConflictResolutionResult.applied(
        remoteState,
        'تم اعتماد النسخة الشبكية الأحدث (الإصدار $remoteVersion مقابل المحلي $localVersion)',
      );
    } else if (localVersion > remoteVersion) {
      return ConflictResolutionResult.localWins(
        'تم الاحتفاظ بالتعديل المحلي الأحدث (الإصدار $localVersion مقابل الشبكي $remoteVersion)',
      );
    } else {
      // Versions are identical: check timestamps
      final localUpdatedAtStr = localState['updated_at'] as String?;
      final remoteUpdatedAtStr = remoteState['updated_at'] as String?;

      if (localUpdatedAtStr != null && remoteUpdatedAtStr != null) {
        final localDate = DateTime.tryParse(localUpdatedAtStr);
        final remoteDate = DateTime.tryParse(remoteUpdatedAtStr);

        if (localDate != null && remoteDate != null) {
          if (remoteDate.isAfter(localDate)) {
            return ConflictResolutionResult.applied(remoteState, 'اعتماد النسخة الشبكية ذات التوقيت الأحدث');
          } else if (localDate.isAfter(remoteDate)) {
            return ConflictResolutionResult.localWins('النسخة المحلية ذات التوقيت الأحدث');
          }
        }
      }

      // Exact version collision with differing contents
      return ConflictResolutionResult.manualReview(
        'تعارض متزامن: تم تعديل الصنف $upperType محلياً وشبكياً في نفس اللحظة برقم إصدار متطابق.',
      );
    }
  }
}
