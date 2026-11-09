import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/backup/backup_service.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';

class AppExitBackupDialog extends ConsumerStatefulWidget {
  const AppExitBackupDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppExitBackupDialog(),
    );
  }

  @override
  ConsumerState<AppExitBackupDialog> createState() => _AppExitBackupDialogState();
}

class _AppExitBackupDialogState extends ConsumerState<AppExitBackupDialog> {
  final _pathController = TextEditingController();
  bool _rememberPath = true;
  bool _isBackingUp = false;
  String? _statusMessage;
  bool _isSuccess = false;
  List<String> _availableDrives = [];

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialSettings() async {
    final db = ref.read(databaseServiceProvider);
    final backupService = BackupService(db);
    final currentPath = await backupService.getEffectiveBackupDirectory();
    final drives = backupService.getAvailableDrives();

    if (mounted) {
      setState(() {
        _pathController.text = currentPath;
        _availableDrives = drives;
      });
    }
  }

  Future<void> _executeBackupAndExit() async {
    setState(() {
      _isBackingUp = true;
      _statusMessage = 'جاري ضغط قاعدة البيانات وكتابة تقرير النسخة الاحتياطية...';
      _isSuccess = false;
    });

    final db = ref.read(databaseServiceProvider);
    final backupService = BackupService(db);
    final currentUser = ref.read(currentUserProvider);
    final targetPath = _pathController.text.trim();

    // 1. Save persistent preference if checked
    if (_rememberPath && targetPath.isNotEmpty) {
      backupService.setBackupDirectory(targetPath);
      backupService.setAutoBackupOnClose(true);
    }

    // 2. Perform zero-downtime hot backup with companion metadata file
    final result = await backupService.createBackup(
      customTargetDir: targetPath,
      executedBy: '${currentUser?.fullName ?? "admin"} (${currentUser?.username ?? "admin"})',
    );

    if (mounted) {
      if (result.isSuccess) {
        setState(() {
          _isSuccess = true;
          _statusMessage = 'تم إنشاء النسخة الاحتياطية بنجاح!\nالمسار: ${result.dbFilePath}\nملف التقرير: ${result.manifestFilePath}';
        });

        // Small delay to let user see the green confirmation, then close
        await Future.delayed(const Duration(milliseconds: 1200));
        _closeApp();
      } else {
        setState(() {
          _isBackingUp = false;
          _statusMessage = 'حدث خطأ أثناء النسخ: ${result.errorMessage}';
        });
      }
    }
  }

  void _closeApp() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.destroy();
      } else {
        exit(0);
      }
    } catch (_) {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.lightBgSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.lightBorderSubtle, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(28),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Icon & Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.shield_rounded, color: AppColors.brandGoldDark, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إغلاق المنظومة والنسخ الاحتياطي التلقائي',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.lightTextPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'حماية بيانات المبيعات والمخزون بإنشاء نسخة احتياطية آمنة قبل المغادرة',
                        style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // Drive & Path Selection Section
            const Text(
              'حدد القرص أو المجلد لحفظ النسخة الاحتياطية:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.lightTextPrimary),
            ),
            const SizedBox(height: 10),

            // Quick Drive Selectors
            if (_availableDrives.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableDrives.map((drive) {
                  final isSelected = _pathController.text.startsWith(drive);
                  return ActionChip(
                    avatar: Icon(Icons.storage_rounded, size: 16, color: isSelected ? Colors.white : AppColors.brandPrimary),
                    label: Text(
                      'قرص ($drive)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppColors.brandPrimary,
                      ),
                    ),
                    backgroundColor: isSelected ? AppColors.brandPrimary : AppColors.lightBgSubtle,
                    side: BorderSide(color: isSelected ? AppColors.brandPrimary : AppColors.lightBorderSubtle),
                    onPressed: () {
                      setState(() {
                        _pathController.text = '${drive}AlfaSoft_Backups';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Path TextField
            TextFormField(
              controller: _pathController,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.folder_special_rounded, color: AppColors.brandAccent),
                hintText: r'D:\AlfaSoft_Backups',
                labelText: 'المسار المستهدف للنسخة',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'إعادة ضبط للمسار المقترح',
                  onPressed: () {
                    if (_availableDrives.isNotEmpty) {
                      _pathController.text = '${_availableDrives.first}AlfaSoft_Backups';
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Remember Path Checkbox
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightBgSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.lightBorderSubtle),
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'حفظ هذا القرص والمسار كوجهة دائمة للنسخ التلقائي عند كل إغلاق',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.lightTextPrimary),
                ),
                value: _rememberPath,
                onChanged: (v) => setState(() => _rememberPath = v ?? true),
              ),
            ),
            const SizedBox(height: 16),

            // Status / Error Banner
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess ? AppColors.successBg : AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isSuccess ? AppColors.success.withValues(alpha: 0.3) : AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _isSuccess ? AppColors.successText : AppColors.dangerText,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isSuccess ? AppColors.successText : AppColors.dangerText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons Row
            Row(
              children: [
                // Cancel
                TextButton(
                  onPressed: _isBackingUp ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء والعودة', style: TextStyle(color: AppColors.lightTextSecondary)),
                ),
                const Spacer(),

                // Exit directly without backup
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: _isBackingUp ? null : _closeApp,
                  child: const Text('إغلاق مباشر بدون نسخ'),
                ),
                const SizedBox(width: 12),

                // Primary: Backup & Exit
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _isBackingUp ? null : _executeBackupAndExit,
                  icon: _isBackingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.backup_rounded, size: 18),
                  label: Text(
                    _isBackingUp ? 'جاري النسخ والإغلاق...' : 'نسخ احتياطي وإغلاق المنظومة',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
