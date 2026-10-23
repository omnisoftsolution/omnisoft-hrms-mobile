/// Pure text helpers of the team screens. Everything is pinned to `en_US`
/// (no l10n in this app); dates are local calendar days.
library;

import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:intl/intl.dart';

import '../../core/leave_dates.dart' show hourMinute;
import '../../models/team_outlook.dart';

final _dayFormat = DateFormat('EEE d MMM', 'en_US');
final _monthFormat = DateFormat('MMMM y', 'en_US');
final _clockFormat = DateFormat('HH:mm', 'en_US');
final _daysNumber = NumberFormat('0.##', 'en_US');

/// 'Thu 22 Oct'.
String dayTitle(DateTime d) => _dayFormat.format(d);

/// 'January 2027'.
String monthLabel(DateTime m) => _monthFormat.format(m);

/// '09:12' (24 h).
String clockLabel(DateTime t) => _clockFormat.format(t);

/// Fill of an employee's initials avatar (A-L6, as the mockup):
/// `hsl(id * 47 % 360, 55%, 45%)`. A colour computed from the id, not a
/// palette value, so it lives here and [TeamColors.avatar] returns it.
Color initialsHue(int id) =>
    HSLColor.fromAHSL(1, ((id * 47) % 360).toDouble(), 0.55, 0.45).toColor();

/// The calendar day of [d], at local midnight.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 'YYYY-MM-DD' of a local day (the widget keys use it).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// '1 person', '12 people'.
String peopleCount(int n) => n == 1 ? '1 person' : '$n people';

/// The one line shown when the server bounded the rows (K2, A-L17): under
/// the heat map when the outlook says `truncated`, under Who's out when
/// `who_out.truncated` (Task 8).
const teamRowsNotShown = 'Some rows are not shown.';

/// '1 day', '2 days', '1.5 days'.
String daysCount(double n) {
  if (n == n.roundToDouble()) {
    final i = n.round();
    return i == 1 ? '1 day' : '$i days';
  }
  return '${_daysNumber.format(n)} days';
}

String _half(String? period) => switch (period) {
  'am' => 'morning',
  'pm' => 'afternoon',
  _ => '',
};

/// When a leave row happens, as the outlook lists it:
/// * one day: 'Thu 22 Oct';
/// * half a day: 'Thu 22 Oct (morning)' / '(afternoon)';
/// * hours: 'Tue 3 Nov, 14:00 – 17:00';
/// * several days: 'Thu 12 Nov – Fri 13 Nov · 2 days' (`number_of_days`;
///   no count when the server sent none);
/// * several days starting in the afternoon or ending in the morning:
///   'Thu 12 Nov (afternoon) – Fri 13 Nov (morning)'.
String leaveWhenLabel(TeamLeaveRow r) {
  final from = r.dateFrom;
  final to = r.dateTo;
  if (_sameDay(from, to) || to.isBefore(from)) {
    if (r.unit == 'hours' && r.hourTo > r.hourFrom) {
      return '${dayTitle(from)}, ${hourMinute(r.hourFrom)} – '
          '${hourMinute(r.hourTo)}';
    }
    final f = r.fromPeriod;
    final t = r.toPeriod;
    // am → pm on one day is the whole day.
    final period = (f != null && t != null && f != t) ? '' : _half(f ?? t);
    return period.isEmpty ? dayTitle(from) : '${dayTitle(from)} ($period)';
  }
  if (r.fromPeriod == 'pm' || r.toPeriod == 'am') {
    final start = r.fromPeriod == 'pm'
        ? '${dayTitle(from)} (afternoon)'
        : dayTitle(from);
    final end = r.toPeriod == 'am' ? '${dayTitle(to)} (morning)' : dayTitle(to);
    return '$start – $end';
  }
  final span = '${dayTitle(from)} – ${dayTitle(to)}';
  return r.numberOfDays > 0 ? '$span · ${daysCount(r.numberOfDays)}' : span;
}

/// The heat-map cell's screen-reader label: 'Thu 22 Oct, 3 off' plus
/// ', public holiday Deepavali' on a holiday.
String heatDayLabel(DateTime d, int off, {String? holidayName}) {
  final base = '${dayTitle(d)}, $off off';
  if (holidayName == null) return base;
  return holidayName.isEmpty
      ? '$base, public holiday'
      : '$base, public holiday $holidayName';
}

/// The privacy line under the range switch (team context only).
String privacyLine({required bool showType, required bool showPending}) =>
    (showType ? 'Leave type shown' : 'Shown as “On leave” — no type or reason') +
    (showPending ? ' · includes pending requests' : ' · approved leave only');

/// The line under the team name in the outlook header. With a department
/// chip selected (overview context), the mockup shows that department:
/// its name and its size from `departments[]` ("Fabric · 10 people").
String teamScopeSubLabel(TeamOutlook o, {int? departmentId}) {
  final people = peopleCount(o.team?.size ?? 0);
  switch (o.team?.kind) {
    case 'department':
      return 'Your department · $people';
    case 'approver':
      return 'Same leave approver · $people';
    case 'approvees':
      return 'People you approve · $people';
    default:
      final n = o.departments.length;
      if (departmentId != null) {
        for (final d in o.departments) {
          if (d.id == departmentId) return '${d.name} · ${peopleCount(d.size)}';
        }
        return people;
      }
      if (n > 0) return '$people · $n department${n == 1 ? '' : 's'}';
      return people;
  }
}

/// The body copy of the "No team to show yet" card, by `empty_reason`.
String teamEmptyReasonText(String reason) => switch (reason) {
  'no_department' =>
    'Team leave shows the people in your department. Ask HR to add you to one.',
  'no_approver' =>
    'Team leave shows the people who share your leave approver. Ask HR to set yours.',
  'off' => 'Team leave is turned off for your company.',
  _ => 'No one to show here yet.',
};

/// The leave rows covering [day] ([TeamOutlook.leavesOn]), sorted by
/// person name ([TeamOutlook.person]), then row id.
List<TeamLeaveRow> leavesOnByName(TeamOutlook o, DateTime day) {
  String name(TeamLeaveRow r) => o.person(r.employeeId)?.name ?? '';
  final rows = o.leavesOn(day);
  rows.sort((a, b) {
    final byName = name(a).compareTo(name(b));
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return rows;
}

/// The outlook's today: the server's `today`, else the first day of the
/// range, else the phone's today.
DateTime outlookToday(TeamOutlook o) =>
    dayOnly(o.today ?? (o.days.isNotEmpty ? o.days.first.date : DateTime.now()));

/// The day the outlook opens on: today when anyone is off today, else the
/// busiest day (the earliest of equals), else today.
DateTime defaultTeamDay(TeamOutlook o) {
  final today = outlookToday(o);
  TeamDay? best;
  for (final d in o.days) {
    if (_sameDay(d.date, today) && d.off > 0) return today;
    if (d.off > 0 && (best == null || d.off > best.off)) best = d;
  }
  return best == null ? today : dayOnly(best.date);
}
