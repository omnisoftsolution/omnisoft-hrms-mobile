import 'package:flutter/material.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/auto_close_previous.dart';

/// Shown once after a check-in during which the connector auto-closed a
/// forgotten attendance, so the employee knows what HR will see.
class AutoClosedBanner extends StatelessWidget {
  const AutoClosedBanner({
    super.key,
    required this.acp,
    required this.onDismiss,
  });

  final AutoClosePrevious acp;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFB45309); // amber-800
    const bg = Color(0xFFFEF3C7); // amber-100
    final original = DateTimeUtils.formatLocalDateTime(acp.originalCheckIn);
    final inferred = DateTimeUtils.formatLocalDateTime(acp.inferredCheckOut);
    return Container(
      key: const ValueKey('auto-closed-banner'),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: yellow.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Previous check-in auto-closed',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: yellow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We detected a check-in from $original that was never '
                  'closed. We recorded a '
                  '${acp.hoursAssumed.toStringAsFixed(0)}-hour shift '
                  'ending at $inferred. Contact HR if this is incorrect.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: yellow,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
