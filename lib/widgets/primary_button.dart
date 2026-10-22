import 'package:flutter/material.dart';
import '../core/omni_colors.dart';

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

  /// The glow in the button's own colour; none where the theme has no
  /// button glow (dark).
  List<BoxShadow>? _shadow(OmniColors c, Color bg) {
    if (c.buttonGlow.isEmpty) return null;
    return [
      BoxShadow(
        color: bg.withValues(alpha: 0.30),
        blurRadius: 30,
        offset: const Offset(0, 10),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final (bg, fg) = switch (variant) {
      PrimaryButtonVariant.primary => (c.button, c.onButton),
      PrimaryButtonVariant.danger => (c.errorFill, c.onBrandFill),
    };
    final disabled = onPressed == null || loading;
    final button = ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        disabledBackgroundColor: bg.withValues(alpha: 0.6),
        foregroundColor: fg,
        disabledForegroundColor: fg.withValues(alpha: 0.85),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: loading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
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
        boxShadow: disabled ? null : _shadow(c, bg),
      ),
      child: button,
    );

    return fullWidth
        ? SizedBox(width: double.infinity, child: wrapped)
        : wrapped;
  }
}
