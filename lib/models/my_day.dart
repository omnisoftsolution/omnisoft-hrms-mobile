/// Models for the My day home (`POST /home/my_day`, connector 2.51.0+,
/// spec 2026-10-05 §4.2). Datetimes stay as the server's UTC strings
/// ("yyyy-MM-dd HH:mm:ss"); widgets format them with DateTimeUtils.
library;

import 'attendance_ask.dart';

String _str(Object? v) => v is String ? v : '';
int _int(Object? v) => v is num ? v.toInt() : 0;
double _dbl(Object? v) => v is num ? v.toDouble() : 0.0;

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
];

/// A time window with its local "HH:MM – HH:MM" label: a shift block,
/// the whole shift, or the scheduled lunch.
class MyDayWindow {
  final String start;
  final String end;
  final String label;

  const MyDayWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  factory MyDayWindow.fromJson(Map<String, dynamic> json) => MyDayWindow(
    start: _str(json['start']),
    end: _str(json['end']),
    label: _str(json['label']),
  );
}

/// Today's expected shift. [label] is already in the employee's timezone.
/// [blocks] are the schedule's work blocks (lunch excluded); empty on a
/// 2.51.0 connector.
class MyDayShift {
  final String start;
  final String end;
  final String label;
  final List<MyDayWindow> blocks;

  const MyDayShift({
    required this.start,
    required this.end,
    required this.label,
    this.blocks = const [],
  });

  factory MyDayShift.fromJson(Map<String, dynamic> json) => MyDayShift(
    start: _str(json['start']),
    end: _str(json['end']),
    label: _str(json['label']),
    blocks: _maps(json['blocks']).map(MyDayWindow.fromJson).toList(),
  );

  /// "08:00 – 12:00 · 13:00 – 17:00", or [label] without blocks.
  String get blocksLabel =>
      blocks.isEmpty ? label : blocks.map((b) => b.label).join(' · ');
}

/// Why there is no shift today: public_holiday | leave | not_scheduled.
class MyDayOff {
  final String kind;
  final String name;
  final String dateFrom;
  final String dateTo;
  final String backOn;

  const MyDayOff({
    required this.kind,
    this.name = '',
    this.dateFrom = '',
    this.dateTo = '',
    this.backOn = '',
  });

  factory MyDayOff.fromJson(Map<String, dynamic> json) => MyDayOff(
    kind: _str(json['kind']),
    name: _str(json['name']),
    dateFrom: _str(json['date_from']),
    dateTo: _str(json['date_to']),
    backOn: _str(json['back_on']),
  );
}

/// One cell of the week strip: today | worked | absent | public_holiday |
/// leave | scheduled | off. [verdict] only with worked.
class MyDayWeekDay {
  final String date;
  final String kind;
  final String verdict;
  final String name;

  /// 2.52.1 (spec §8.1) — the day sheet's summary; '' / 0 on older connectors.
  final String shift;
  final String firstIn;
  final String lastOut;
  final int workedMinutes;
  final int lateMinutes;
  final int earlyMinutes;
  final String place;
  final String approver;

  const MyDayWeekDay({
    required this.date,
    required this.kind,
    this.verdict = '',
    this.name = '',
    this.shift = '',
    this.firstIn = '',
    this.lastOut = '',
    this.workedMinutes = 0,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.place = '',
    this.approver = '',
  });

  factory MyDayWeekDay.fromJson(Map<String, dynamic> json) => MyDayWeekDay(
    date: _str(json['date']),
    kind: _str(json['kind']),
    verdict: _str(json['verdict']),
    name: _str(json['name']),
    shift: _str(json['shift']),
    firstIn: _str(json['first_in']),
    lastOut: _str(json['last_out']),
    workedMinutes: _int(json['worked_minutes']),
    lateMinutes: _int(json['late_minutes']),
    earlyMinutes: _int(json['early_minutes']),
    place: _str(json['place']),
    approver: _str(json['approver']),
  );
}

class MyDayNextShift {
  final String date;
  final String label;

  const MyDayNextShift({required this.date, required this.label});

  factory MyDayNextShift.fromJson(Map<String, dynamic> json) =>
      MyDayNextShift(date: _str(json['date']), label: _str(json['label']));
}

/// One punch of today: check_in | break_start | break_end | check_out.
class MyDayPunch {
  final String kind;
  final String at;

  /// kiosk | mobile | other.
  final String source;

  /// Kiosk device name, or '' when unknown.
  final String place;

  const MyDayPunch({
    required this.kind,
    required this.at,
    required this.source,
    required this.place,
  });

  factory MyDayPunch.fromJson(Map<String, dynamic> json) => MyDayPunch(
    kind: _str(json['kind']),
    at: _str(json['at']),
    source: _str(json['source']),
    place: _str(json['place']),
  );

  String get label {
    switch (kind) {
      case 'check_in':
        return 'Check in';
      case 'break_start':
        return 'Break start';
      case 'break_end':
        return 'Break end';
      case 'check_out':
        return 'Check out';
      default:
        return kind;
    }
  }

  /// Where the punch was made, for the timeline's second line.
  String get placeLabel {
    if (place.isNotEmpty) return place;
    if (source == 'kiosk') return 'Kiosk';
    if (source == 'mobile') return 'Phone';
    return '';
  }
}

/// One "For you" row. One flat class for the four kinds; a field that a
/// kind does not use keeps its default.
class ForYouItem {
  static const knownKinds = {
    'leave_approvals',
    'my_leave',
    'my_expense',
    'payslip',
  };

  final String kind;
  final int id;

  // leave_approvals
  final int count;
  final String oldestAt;

  // my_leave, my_expense
  final String state;

  // my_leave
  final String type;
  final String dateFrom;
  final String dateTo;
  final String approver;
  final String reason;

  // my_expense
  final String name;
  final double amount;
  final String currency;

  // payslip
  final String period;
  final String issuedOn;

  // yesterday_incomplete (connector 2.54.0, spec 2026-10-07 §3.6)
  final String title;
  final String body;
  final String date;
  final int attendanceId;
  final List<AskOption> options;

  const ForYouItem({
    required this.kind,
    this.id = 0,
    this.count = 0,
    this.oldestAt = '',
    this.state = '',
    this.type = '',
    this.dateFrom = '',
    this.dateTo = '',
    this.approver = '',
    this.reason = '',
    this.name = '',
    this.amount = 0.0,
    this.currency = '',
    this.period = '',
    this.issuedOn = '',
    this.title = '',
    this.body = '',
    this.date = '',
    this.attendanceId = 0,
    this.options = const [],
  });

  /// The connector may add kinds later; 1.26.0 ignores what it does not
  /// know (spec §4.4).
  bool get isKnown => knownKinds.contains(kind);

  factory ForYouItem.fromJson(Map<String, dynamic> json) => ForYouItem(
    kind: _str(json['kind']),
    id: _int(json['id']),
    count: _int(json['count']),
    oldestAt: _str(json['oldest_at']),
    state: _str(json['state']),
    type: _str(json['type']),
    dateFrom: _str(json['date_from']),
    dateTo: _str(json['date_to']),
    approver: _str(json['approver']),
    reason: _str(json['reason']),
    name: _str(json['name']),
    amount: _dbl(json['amount']),
    currency: _str(json['currency']),
    period: _str(json['period']),
    issuedOn: _str(json['issued_on']),
    title: _str(json['title']),
    body: _str(json['body']),
    date: _str(json['date']),
    attendanceId: _int(json['attendance_id']),
    options: AskOption.listFrom(json['options']),
  );
}

class MyDay {
  /// Today in the employee's timezone, "yyyy-MM-dd".
  final String date;
  final String tz;
  final bool kioskOnly;

  /// not_in | checked_in | on_break | checked_out.
  final String state;
  final double hoursToday;

  /// null on a non-working day.
  final MyDayShift? shift;
  final List<MyDayPunch> punches;

  /// Known kinds only, in the server's order.
  final List<ForYouItem> forYou;

  final bool breakExempt;
  final MyDayWindow? lunch;

  /// Whether the connector sent the minute counters at all. A
  /// 2.51.0 connector omits them, so zero there means "unknown", not "on
  /// time".
  final bool hasMinutes;
  final int lateMinutes;
  final int earlyMinutes;
  final int overtimeMinutes;
  final bool missing;
  final MyDayOff? off;
  final List<MyDayWeekDay> week;
  final MyDayNextShift? nextShift;

  const MyDay({
    required this.date,
    required this.tz,
    required this.kioskOnly,
    required this.state,
    required this.hoursToday,
    required this.shift,
    required this.punches,
    required this.forYou,
    this.breakExempt = false,
    this.lunch,
    this.hasMinutes = false,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.overtimeMinutes = 0,
    this.missing = false,
    this.off,
    this.week = const [],
    this.nextShift,
  });

  factory MyDay.fromJson(Map<String, dynamic> json) {
    final today = _map(json['today']) ?? const <String, dynamic>{};
    final shift = _map(today['shift']);
    final state = _str(today['state']);
    final lunch = _map(today['lunch']);
    final off = _map(today['off']);
    final nextShift = _map(json['next_shift']);
    return MyDay(
      date: _str(json['date']),
      tz: _str(json['tz']),
      kioskOnly: today['kiosk_only'] == true,
      state: state.isEmpty ? 'not_in' : state,
      hoursToday: _dbl(today['hours_today']),
      shift: shift == null ? null : MyDayShift.fromJson(shift),
      punches: _maps(today['punches']).map(MyDayPunch.fromJson).toList(),
      forYou: _maps(
        json['for_you'],
      ).map(ForYouItem.fromJson).where((item) => item.isKnown).toList(),
      breakExempt: today['break_exempt'] == true,
      lunch: lunch == null ? null : MyDayWindow.fromJson(lunch),
      hasMinutes: today.containsKey('late_minutes'),
      lateMinutes: _int(today['late_minutes']),
      earlyMinutes: _int(today['early_minutes']),
      overtimeMinutes: _int(today['overtime_minutes']),
      missing: today['missing'] == true,
      off: off == null ? null : MyDayOff.fromJson(off),
      week: _maps(json['week']).map(MyDayWeekDay.fromJson).toList(),
      nextShift: nextShift == null ? null : MyDayNextShift.fromJson(nextShift),
    );
  }
}
