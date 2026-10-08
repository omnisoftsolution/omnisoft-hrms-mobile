import 'package:flutter/material.dart';

import '../core/theme.dart';

/// "Start period" / "End period" row of the half-day leave sheets (apply
/// and edit): a fixed label and a Morning / Afternoon segmented button.
///
/// On a narrow phone (a 720 px Samsung, or a big system font) the
/// segments are too small for icon + check mark + label, and "Afternoon"
/// used to wrap mid-word ("Afternoo n"). The labels are one line that
/// scales down when it must, and the icons go when the segments are
/// narrow.
class PeriodSegmentedRow extends StatelessWidget {
  const PeriodSegmentedRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// 'am' or 'pm'.
  final String value;
  final ValueChanged<String> onChanged;

  /// Below this width for the button the icons are dropped.
  static const double iconMinWidth = 240;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final roomy = constraints.maxWidth >= iconMinWidth;
              return SegmentedButton<String>(
                showSelectedIcon: roomy,
                segments: [
                  ButtonSegment(
                    value: 'am',
                    label: const _OneLine('Morning'),
                    icon: roomy
                        ? const Icon(Icons.wb_sunny_outlined, size: 16)
                        : null,
                  ),
                  ButtonSegment(
                    value: 'pm',
                    label: const _OneLine('Afternoon'),
                    icon: roomy
                        ? const Icon(Icons.wb_twilight, size: 16)
                        : null,
                  ),
                ],
                selected: {value},
                onSelectionChanged: (s) => onChanged(s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A segment label that never wraps: one line, scaled down to fit.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}
