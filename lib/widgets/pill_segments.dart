import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A pill switch of two or more equal-width options (Pending / Recent,
/// 30 / 60 / 90 days, Today / Yesterday, Team overview / My day).
///
/// Moved from the approvals screen's private `_Segments` with the same
/// look. Each option is one semantics button that reports whether it is
/// selected; [semanticsLabel] names the whole group for screen readers.
/// Option `i` carries the key `ValueKey('pill-<i>')`.
class PillSegments extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.semanticsLabel,
  });

  final List<String> labels;

  /// Index of the selected option.
  final int value;

  /// Called with the tapped option's index (also when it is already
  /// selected, as the approvals switch always did).
  final ValueChanged<int> onChanged;

  /// Screen-reader name of the group, e.g. 'How far ahead'.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  key: ValueKey('pill-$i'),
                  container: true,
                  button: true,
                  selected: i == value,
                  label: labels[i],
                  onTap: () => onChanged(i),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: i == value
                            ? AppTheme.surfaceContainerLowest
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: i == value
                              ? AppTheme.primary
                              : AppTheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
