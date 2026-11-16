import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../../features/shell/app_exit_backup_dialog.dart';

class MacOsTitleBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const MacOsTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(38.0);

  @override
  ConsumerState<MacOsTitleBar> createState() => _MacOsTitleBarState();
}

class _MacOsTitleBarState extends ConsumerState<MacOsTitleBar> {
  bool _isHoveringControls = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximizedState();
  }

  void _checkMaximizedState() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      final isMax = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = isMax);
    } catch (_) {}
  }

  Future<void> _handleClose() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      try {
        await windowManager.destroy();
        exit(0);
      } catch (_) {
        exit(0);
      }
    } else {
      if (mounted) {
        AppExitBackupDialog.show(context);
      }
    }
  }

  Future<void> _handleMinimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> _handleMaximize() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) {
        await windowManager.unmaximize();
        setState(() => _isMaximized = false);
      } else {
        await windowManager.maximize();
        setState(() => _isMaximized = true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final barBg = isDark ? const Color(0xFF1E2028) : const Color(0xFFF3F4F6);
    final borderColor = isDark ? const Color(0xFF2E323D) : const Color(0xFFE5E7EB);
    final titleColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          // 1. macOS Traffic Light Control Buttons (Left Side)
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringControls = true),
            onExit: (_) => setState(() => _isHoveringControls = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Close (Red)
                  _buildTrafficLight(
                    color: const Color(0xFFFF5F56),
                    borderColor: const Color(0xFFE0443E),
                    icon: Icons.close_rounded,
                    tooltip: 'إغلاق البرنامج',
                    onTap: _handleClose,
                  ),
                  const SizedBox(width: 8),
                  // Minimize (Yellow)
                  _buildTrafficLight(
                    color: const Color(0xFFFFBD2E),
                    borderColor: const Color(0xFFDEA123),
                    icon: Icons.remove_rounded,
                    tooltip: 'تصغير إلى شريط المهام',
                    onTap: _handleMinimize,
                  ),
                  const SizedBox(width: 8),
                  // Maximize / Restore (Green)
                  _buildTrafficLight(
                    color: const Color(0xFF27C93F),
                    borderColor: const Color(0xFF1AAB29),
                    icon: _isMaximized ? Icons.unfold_less_rounded : Icons.add_rounded,
                    tooltip: _isMaximized ? 'استعادة الحجم الطبيعي' : 'تكبير الشاشة بالكامل',
                    onTap: _handleMaximize,
                  ),
                ],
              ),
            ),
          ),

          // 2. Window Title & Draggable Area (Center)
          Expanded(
            child: GestureDetector(
              onDoubleTap: _handleMaximize,
              behavior: HitTestBehavior.translucent,
              child: DragToMoveArea(
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.dashboard_rounded,
                            size: 16,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ALFA SOFT — Enterprise Resource Planning',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Right Status Badges
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'جاهز محلياً',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLight({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _isHoveringControls ? 0.85 : 0.0,
              child: Icon(
                icon,
                size: 8.5,
                color: Colors.black.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
