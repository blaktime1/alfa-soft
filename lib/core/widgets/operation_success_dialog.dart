import 'package:flutter/material.dart';

class OperationSuccessDialog extends StatefulWidget {
  final String title;
  final String message;
  final String? referenceCode;
  final String? amountText;
  final String? warehouseName;
  final VoidCallback? onConfirm;

  const OperationSuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.referenceCode,
    this.amountText,
    this.warehouseName,
    this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String? referenceCode,
    String? amountText,
    String? warehouseName,
    VoidCallback? onConfirm,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OperationSuccessDialog(
        title: title,
        message: message,
        referenceCode: referenceCode,
        amountText: amountText,
        warehouseName: warehouseName,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<OperationSuccessDialog> createState() => _OperationSuccessDialogState();
}

class _OperationSuccessDialogState extends State<OperationSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    );

    _checkAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.elasticOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        width: 440,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated Green Checkmark
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: ScaleTransition(
                        scale: _checkAnimation,
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Operation Title
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF1E824C),
              ),
            ),
            const SizedBox(height: 10),

            // Operation Message
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
                fontSize: 13,
                height: 1.5,
              ),
            ),

            // Metadata Chips (Reference, Amount, Warehouse)
            if (widget.referenceCode != null ||
                widget.amountText != null ||
                widget.warehouseName != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    if (widget.referenceCode != null)
                      _metaRow('رقم المعاملة / المستند:', widget.referenceCode!),
                    if (widget.amountText != null) ...[
                      if (widget.referenceCode != null) const Divider(height: 12),
                      _metaRow('إجمالي المبلغ المالي:', widget.amountText!, isHighlight: true),
                    ],
                    if (widget.warehouseName != null) ...[
                      if (widget.referenceCode != null || widget.amountText != null)
                        const Divider(height: 12),
                      _metaRow('مستودع التوريد / المخزن:', widget.warehouseName!),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),

            // Confirmation / Close Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onConfirm?.call();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.done_all_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'حسناً، متابعة العمليات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFF1E824C) : Colors.black87,
          ),
        ),
      ],
    );
  }
}
