import 'package:flutter/material.dart';

import '../../../models/my_day.dart';
import 'my_day_display.dart';

/// The explanation behind the kiosk icon button (same text as 1.26.0).
Future<void> showKioskSheet(BuildContext context) {
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
          24,
          0,
          24,
          24 + MediaQuery.of(sheetContext).viewPadding.bottom,
        ),
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

int _daysBetween(String from, String to) {
  final a = DateTime.tryParse(from);
  final b = DateTime.tryParse(to);
  if (a == null || b == null) return 1;
  return b.difference(a).inDays + 1;
}

IconData _icon(MyDayDisplay display) {
  switch (display) {
    case MyDayDisplay.holiday:
      return Icons.star_outline;
    case MyDayDisplay.leave:
      return Icons.event_available_outlined;
    case MyDayDisplay.noShift:
      return Icons.wb_sunny_outlined;
    case MyDayDisplay.missing:
      return Icons.warning_amber_outlined;
    case MyDayDisplay.notIn:
      return Icons.hourglass_empty;
    case MyDayDisplay.late:
      return Icons.alarm_outlined;
    case MyDayDisplay.onBreak:
      return Icons.coffee_outlined;
    case MyDayDisplay.early:
      return Icons.logout_outlined;
    case MyDayDisplay.overtime:
      return Icons.nightlight_outlined;
    case MyDayDisplay.checkedIn:
    case MyDayDisplay.done:
      return Icons.check_circle_outline;
  }
}

/// The coloured card at the top of My day (spec 2026-10-06 §4.2).
class StatusTile extends StatelessWidget {
  const StatusTile({super.key, required this.day, this.now});

  final MyDay day;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final display = displayOf(day);
    final tone = toneOf(display);
    final text = Theme.of(context).textTheme;
    const white = Colors.white;
    final shift = day.shift;
    final next = day.nextShift;
    final off = day.off;

    String bigLabel;
    String big;
    String rightLabel;
    String right;
    switch (display) {
      case MyDayDisplay.leave:
        bigLabel = 'Away';
        final days = _daysBetween(off?.dateFrom ?? '', off?.dateTo ?? '');
        big = '$days day${days == 1 ? '' : 's'}';
        rightLabel = 'Back on';
        right = off == null || off.backOn.isEmpty ? '—' : shortDate(off.backOn);
      case MyDayDisplay.holiday:
      case MyDayDisplay.noShift:
        bigLabel = 'Next shift';
        big = next == null ? '—' : shortDate(next.date);
        rightLabel = 'Hours';
        right = next?.label ?? '—';
      case MyDayDisplay.early:
        bigLabel = 'Worked';
        big = formatHoursToday(day.hoursToday);
        rightLabel = 'Short';
        right = minutesLabel(day.earlyMinutes);
      case MyDayDisplay.overtime:
        bigLabel = 'Worked';
        big = formatHoursToday(day.hoursToday);
        rightLabel = 'Overtime';
        right = minutesLabel(day.overtimeMinutes);
      default:
        bigLabel = 'Worked';
        big = formatHoursToday(day.hoursToday);
        rightLabel = 'Shift';
        right = shift?.label ?? '—';
    }

    final labelStyle = text.labelSmall?.copyWith(
      color: white.withValues(alpha: 0.9),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );

    return Container(
      key: const ValueKey('status-tile'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E5075AF),
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(_icon(display), color: white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle(display),
                      key: const ValueKey('status-title'),
                      style: text.headlineSmall?.copyWith(
                        color: white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displaySubtitle(day, display, now: now),
                      style: text.bodySmall?.copyWith(
                        color: white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (day.kioskOnly)
                IconButton(
                  key: const ValueKey('status-kiosk-button'),
                  tooltip: 'Attendance is recorded at the kiosk',
                  onPressed: () => showKioskSheet(context),
                  style: IconButton.styleFrom(
                    backgroundColor: white.withValues(alpha: 0.14),
                    side: BorderSide(color: white.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    minimumSize: const Size(42, 42),
                  ),
                  icon: const Icon(
                    Icons.tablet_android_outlined,
                    color: white,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: white.withValues(alpha: 0.22), height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bigLabel, style: labelStyle),
                    const SizedBox(height: 3),
                    Text(
                      big,
                      style: text.headlineMedium?.copyWith(
                        color: white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rightLabel, style: labelStyle),
                  const SizedBox(height: 5),
                  Text(
                    right,
                    style: text.titleMedium?.copyWith(
                      color: white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
