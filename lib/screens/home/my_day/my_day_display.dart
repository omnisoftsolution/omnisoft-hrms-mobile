import 'dart:math';

import 'package:intl/intl.dart';

import '../../../core/datetime_utils.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';

/// What the status tile shows, derived from `today` in the order of
/// spec 2026-10-06 §4.2 (first match wins).
enum MyDayDisplay {
  holiday,
  leave,
  noShift,
  missing,
  notIn,
  late,
  checkedIn,
  onBreak,
  early,
  overtime,
  done,
}

MyDayDisplay displayOf(MyDay day) {
  final off = day.off;
  // An off day with punches (someone worked a holiday or came in on leave)
  // shows the live state like any other day.
  if (off != null && day.punches.isEmpty) {
    switch (off.kind) {
      case 'public_holiday':
        return MyDayDisplay.holiday;
      case 'leave':
        return MyDayDisplay.leave;
      default:
        return MyDayDisplay.noShift;
    }
  }
  // A 2.51.0 connector sends no `off`: no shift and nothing punched is a
  // day off as far as the tile can tell.
  if (day.shift == null && day.punches.isEmpty) return MyDayDisplay.noShift;
  if (day.missing) return MyDayDisplay.missing;
  switch (day.state) {
    case 'not_in':
      return MyDayDisplay.notIn;
    case 'checked_in':
      return day.lateMinutes > 0 ? MyDayDisplay.late : MyDayDisplay.checkedIn;
    case 'on_break':
      return MyDayDisplay.onBreak;
    default:
      if (day.earlyMinutes > 0) return MyDayDisplay.early;
      if (day.overtimeMinutes > 0) return MyDayDisplay.overtime;
      return MyDayDisplay.done;
  }
}

MyDayTone toneOf(MyDayDisplay display) {
  switch (display) {
    case MyDayDisplay.holiday:
      return MyDayColors.holiday;
    case MyDayDisplay.leave:
      return MyDayColors.leave;
    case MyDayDisplay.noShift:
    case MyDayDisplay.notIn:
      return MyDayColors.waiting;
    case MyDayDisplay.missing:
      return MyDayColors.missing;
    case MyDayDisplay.late:
    case MyDayDisplay.early:
      return MyDayColors.late;
    case MyDayDisplay.onBreak:
      return MyDayColors.brk;
    case MyDayDisplay.overtime:
      return MyDayColors.overtime;
    case MyDayDisplay.checkedIn:
    case MyDayDisplay.done:
      return MyDayColors.work;
  }
}

String displayTitle(MyDayDisplay display) {
  switch (display) {
    case MyDayDisplay.holiday:
      return 'Public holiday';
    case MyDayDisplay.leave:
      return 'On leave';
    case MyDayDisplay.noShift:
      return 'Day off';
    case MyDayDisplay.missing:
      return 'No check-in';
    case MyDayDisplay.notIn:
      return 'Not in yet';
    case MyDayDisplay.late:
      return 'Checked in late';
    case MyDayDisplay.checkedIn:
      return 'Checked in';
    case MyDayDisplay.onBreak:
      return 'On break';
    case MyDayDisplay.early:
      return 'Left early';
    case MyDayDisplay.overtime:
    case MyDayDisplay.done:
      return 'Done for today';
  }
}

/// 3.2 hours -> "3h 12m".
String formatHoursToday(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// 17 -> "17 min"; 65 -> "1h 05m".
String minutesLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// "2026-10-05" -> "5 Oct"; the input back when it does not parse.
String shortDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat('d MMM', 'en_US').format(date);
}

/// "5 Oct – 7 Oct", or just "5 Oct" for a one-day range.
String dateRange(String from, String to) {
  final a = shortDate(from);
  final b = shortDate(to);
  return a == b || b.isEmpty ? a : '$a – $b';
}

MyDayPunch? _firstCheckIn(MyDay day) =>
    day.punches.where((p) => p.kind == 'check_in').firstOrNull;

MyDayPunch? _lastPunch(MyDay day) => day.punches.lastOrNull;

/// Second line of the status tile. [now] is injectable for tests.
String displaySubtitle(MyDay day, MyDayDisplay display, {DateTime? now}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final shiftStart = DateTimeUtils.parseOdooUtc(day.shift?.start);
  switch (display) {
    case MyDayDisplay.holiday:
      final holiday = day.off?.name ?? '';
      return holiday.isEmpty ? 'Public holiday' : holiday;
    case MyDayDisplay.leave:
      final off = day.off!;
      final name = off.name.isEmpty ? 'Leave' : off.name;
      if (off.dateFrom.isEmpty) return name;
      return '$name · ${dateRange(off.dateFrom, off.dateTo)}';
    case MyDayDisplay.noShift:
      return 'No shift today';
    case MyDayDisplay.missing:
      if (shiftStart == null) return 'Nothing recorded';
      final ago = clock.difference(shiftStart).inMinutes;
      return 'Shift started ${minutesLabel(ago)} ago · nothing recorded';
    case MyDayDisplay.notIn:
      if (shiftStart == null) return 'No check-in yet';
      final left = shiftStart.difference(clock).inMinutes;
      if (left <= 0) return 'Shift has started';
      return 'Shift starts in $left minute${left == 1 ? '' : 's'}';
    case MyDayDisplay.late:
      final at = DateTimeUtils.formatLocalTime(_firstCheckIn(day)?.at);
      return '$at · ${day.lateMinutes} minutes after the shift start';
    case MyDayDisplay.checkedIn:
      final first = _firstCheckIn(day);
      final at = DateTimeUtils.formatLocalTime(first?.at);
      final place = first?.placeLabel ?? '';
      return place.isEmpty ? 'Since $at' : 'Since $at · $place';
    case MyDayDisplay.onBreak:
      final last = _lastPunch(day);
      final since = DateTimeUtils.parseOdooUtc(last?.at);
      final at = DateTimeUtils.formatLocalTime(last?.at);
      if (since == null) return 'Since $at';
      final mins = max(0, clock.difference(since).inMinutes);
      return 'Since $at · ${minutesLabel(mins)} so far';
    case MyDayDisplay.early:
      final at = DateTimeUtils.formatLocalTime(_lastPunch(day)?.at);
      return 'Checked out $at · ${day.earlyMinutes} minutes before the shift end';
    case MyDayDisplay.overtime:
      final at = DateTimeUtils.formatLocalTime(_lastPunch(day)?.at);
      return 'Checked out $at · ${day.overtimeMinutes} minutes overtime';
    case MyDayDisplay.done:
      return 'Checked out ${DateTimeUtils.formatLocalTime(_lastPunch(day)?.at)}';
  }
}
