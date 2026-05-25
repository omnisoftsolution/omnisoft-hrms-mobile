import 'package:flutter/material.dart';
import '../core/theme.dart';

enum PrimaryButtonVariant {
  /// Default — primaryContainer teal with the design-system glow.
  primary,

  /// Red — used for destructive actions (Logout, Cancel Leave).
  danger,
}

/// Pill-shaped CTA with the Omni HR glow shadow. Wraps an
/// `ElevatedButton` so it picks up the global text style + ripple,
/// but adds the colored ambient shadow that Material's button shadow
/// API can't produce cleanly.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final PrimaryButtonVariant variant;
  final bool fullWidth;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.variant = PrimaryButtonVariant.primary,
    this.fullWidth = true,
  });

  Color get _bgColor => switch (variant) {
        PrimaryButtonVariant.primary => AppTheme.primaryContainer,
        PrimaryButtonVariant.danger => AppTheme.error,
      };

  List<BoxShadow> get _shadow {
    final color = _bgColor.withValues(alpha: 0.30);
    return [
      BoxShadow(
        color: color,
        blurRadius: 30,
        offset: const Offset(0, 10),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final button = ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _bgColor,
        disabledBackgroundColor: _bgColor.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(label),
              ],
            ),
    );

    final wrapped = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        // Hide the glow when disabled so a greyed-out button doesn't
        // look like it's actively pulsing.
        boxShadow: disabled ? null : _shadow,
      ),
      child: button,
    );

    return fullWidth
        ? SizedBox(width: double.infinity, child: wrapped)
        : wrapped;
  }
}
