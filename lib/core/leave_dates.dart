import 'package:intl/intl.dart';

/// The dates of a leave request, as the approvals cards and the History
/// card show them:
///
/// * one day: 'Mon 26 Oct'
/// * a range: 'Thu 22 Oct – Fri 23 Oct'
/// * specific hours ([hourFrom] / [hourTo] given, end after start, same
///   day): 'Tue 3 Nov, 14:00 – 17:00'
/// * half a day ([halfDayPeriod] 'am' / 'pm', same day):
///   'Mon 2 Nov (morning)' / 'Mon 2 Nov (afternoon)'
///
/// '' when [from] is null. Pinned to `en_US` (no l10n in this app).
String leaveDatesLabel(
  DateTime? from,
  DateTime? to, {
  double? hourFrom,
  double? hourTo,
  String? halfDayPeriod,
}) {
  if (from == null) return '';
  final f = DateFormat('EEE d MMM', 'en_US');
  if (to != null && !_sameDay(from, to)) {
    return '${f.format(from)} – ${f.format(to)}';
  }
  if (hourFrom != null && hourTo != null && hourTo > hourFrom) {
    return '${f.format(from)}, ${hourMinute(hourFrom)} – ${hourMinute(hourTo)}';
  }
  final day = f.format(from);
  switch (halfDayPeriod) {
    case 'am':
      return '$day (morning)';
    case 'pm':
      return '$day (afternoon)';
    default:
      return day;
  }
}

/// Odoo float hours as 24 h text: 13.5 -> '13:30'.
String hourMinute(double h) {
  var hh = h.floor();
  var mm = ((h - hh) * 60).round();
  if (mm == 60) {
    hh += 1;
    mm = 0;
  }
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
