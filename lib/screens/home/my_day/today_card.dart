import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/my_day.dart';

/// `readOnly` is what 1.26.0 ships (kiosk-only staff). `action` is for the
/// later release in which phone users get their check-in button inside
/// this card: the constructor and the layout slot exist, nothing more.
enum TodayCardMode { readOnly, action }

/// 3.2 hours -> "3h 12m".
String formatHoursToday(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// Chip text for a server `today.state`; an unknown state shows as sent.
String todayStateLabel(String state) {
  switch (state) {
    case 'not_in':
      return 'Not checked in';
    case 'checked_in':
      return 'Checked in';
    case 'on_break':
      return 'On break';
    case 'checked_out':
      return 'Checked out';
    default:
      return state;
  }
}

/// The fixed card at the top of My day: status chip, hours today, shift.
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.day,
    this.mode = TodayCardMode.readOnly,
    this.action,
  });

  final MyDay day;
  final TodayCardMode mode;

  /// Shown in the bottom slot when [mode] is [TodayCardMode.action].
  final Widget? action;

  static const kioskLine = 'Attendance is recorded at the kiosk.';

  Color get _chipColor {
    switch (day.state) {
      case 'checked_in':
      case 'checked_out':
        return AppTheme.primary;
      case 'on_break':
        return AppTheme.secondary;
      default:
        return AppTheme.outline;
    }
  }

  static Future<void> _showWhy(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      // HomeShell has one Navigator per tab; a sheet on the tab navigator
      // would sit under the bottom bar.
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final text = Theme.of(sheetContext).textTheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              24, 0, 24, 24 + MediaQuery.of(sheetContext).viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Phone check-in is off', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Your attendance is recorded at the kiosk by company '
                'policy. If you think this is wrong, ask HR to change it '
                'on your employee record.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shift = day.shift;
    final chipColor = _chipColor;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shift == null ? 'Today' : 'Today · ${shift.label}',
                    style: text.labelLarge
                        ?.copyWith(color: AppTheme.onSurfaceVariant),
                  ),
                ),
                Container(
                  key: const ValueKey('today-chip'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    todayStateLabel(day.state),
                    style: text.labelMedium?.copyWith(
                        color: chipColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              formatHoursToday(day.hoursToday),
              style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800, color: AppTheme.onSurface),
            ),
            Text('Hours today',
                style: text.bodySmall?.copyWith(color: AppTheme.outline)),
            const SizedBox(height: 16),
            if (mode == TodayCardMode.readOnly)
              InkWell(
                key: const ValueKey('today-kiosk-line'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showWhy(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: AppTheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          kioskLine,
                          style: text.bodyMedium
                              ?.copyWith(color: AppTheme.onSurfaceVariant),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppTheme.outline),
                    ],
                  ),
                ),
              )
            else
              ?action,
          ],
        ),
      ),
    );
  }
}
