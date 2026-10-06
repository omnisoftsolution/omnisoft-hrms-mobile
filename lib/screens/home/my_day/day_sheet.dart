import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

/// What the day sheet says about one week-strip day (spec 2026-10-06 §8.2).
class DaySummary {
  const DaySummary({
    required this.title,
    required this.head,
    required this.sub,
    required this.tone,
    required this.icon,
  });

  final String title;
  final String head;
  final String sub;
  final MyDayTone tone;
  final IconData icon;
}

/// "Monday 5 October"; '' when the date does not parse.
String dayTitle(String date) {
  final parsed = DateTime.tryParse(date);
  return parsed == null
      ? ''
      : DateFormat('EEEE d MMMM', 'en_US').format(parsed);
}

String _shiftLine(MyDayWeekDay d) => d.shift.isEmpty ? '' : 'Shift ${d.shift}';

DaySummary _worked(MyDayWeekDay d) {
  var head = d.workedMinutes > 0
      ? 'Worked ${minutesLabel(d.workedMinutes)}'
      : 'Worked';
  var tone = MyDayColors.work;
  var icon = Icons.check_circle_outline;
  if (d.verdict == 'late' && d.lateMinutes > 0) {
    head += ' · ${minutesLabel(d.lateMinutes)} late';
    tone = MyDayColors.late;
    icon = Icons.alarm_outlined;
  } else if (d.verdict == 'early_leave' && d.earlyMinutes > 0) {
    head += ' · left ${minutesLabel(d.earlyMinutes)} early';
    tone = MyDayColors.late;
    icon = Icons.logout_outlined;
  } else if (d.verdict == 'ok') {
    head += ' · on time';
  }
  var sub = '';
  if (d.firstIn.isNotEmpty) {
    sub = d.lastOut.isEmpty
        ? 'From ${d.firstIn}'
        : '${d.firstIn} – ${d.lastOut}';
    if (d.place.isNotEmpty) sub += ' · ${d.place}';
  }
  return DaySummary(
    title: dayTitle(d.date),
    head: head,
    sub: sub,
    tone: tone,
    icon: icon,
  );
}

DaySummary daySummaryOf(MyDayWeekDay d) {
  final title = dayTitle(d.date);
  switch (d.kind) {
    case 'worked':
      return _worked(d);
    case 'absent':
      return DaySummary(
        title: title,
        head: 'No check-in recorded',
        sub: _shiftLine(d),
        tone: MyDayColors.missing,
        icon: Icons.warning_amber_outlined,
      );
    case 'public_holiday':
      return DaySummary(
        title: title,
        head: 'Public holiday',
        sub: d.name,
        tone: MyDayColors.holiday,
        icon: Icons.star_outline,
      );
    case 'leave':
      return DaySummary(
        title: title,
        head: d.name.isEmpty ? 'Leave' : d.name,
        sub: d.approver.isEmpty ? '' : 'Approved by ${d.approver}',
        tone: MyDayColors.leave,
        icon: Icons.event_available_outlined,
      );
    case 'scheduled':
      return DaySummary(
        title: title,
        head: 'Scheduled',
        sub: _shiftLine(d),
        tone: MyDayColors.waiting,
        icon: Icons.schedule_outlined,
      );
    default:
      return DaySummary(
        title: title,
        head: 'No shift',
        sub: '',
        tone: MyDayColors.waiting,
        icon: Icons.wb_sunny_outlined,
      );
  }
}

/// The short sheet behind a tap on a week-strip day (spec §8.2).
///
/// Deliberately pushed on the TAB navigator, not the root one: HomeShell
/// gives every tab its own Navigator inside the Scaffold body, so a sheet
/// on that navigator rises from the bottom bar and stops at it — Home,
/// Leave, History and Expenses stay visible and tappable. (showKioskSheet
/// is the opposite case and uses the root navigator on purpose.)
Future<void> showDaySheet(BuildContext context, MyDayWeekDay day) {
  final summary = daySummaryOf(day);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    showDragHandle: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.title,
              key: const ValueKey('day-sheet-title'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: summary.tone.tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(summary.icon, size: 22, color: summary.tone.dot),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.head,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (summary.sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary.sub,
                          style: text.bodySmall?.copyWith(
                            color: AppTheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
