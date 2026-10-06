import 'package:omni_hr/models/my_day.dart';

/// The example body of spec 2026-10-05 §4.2.
Map<String, dynamic> sampleMyDayJson() => {
  'success': true,
  'date': '2026-10-05',
  'tz': 'Asia/Jakarta',
  'today': {
    'kiosk_only': true,
    'state': 'checked_in',
    'hours_today': 3.2,
    'shift': {
      'start': '2026-10-05 01:00:00',
      'end': '2026-10-05 10:00:00',
      'label': '08:00 – 17:00',
      'blocks': [
        {
          'start': '2026-10-05 01:00:00',
          'end': '2026-10-05 05:00:00',
          'label': '08:00 – 12:00',
        },
        {
          'start': '2026-10-05 06:00:00',
          'end': '2026-10-05 10:00:00',
          'label': '13:00 – 17:00',
        },
      ],
    },
    'lunch': {
      'start': '2026-10-05 05:00:00',
      'end': '2026-10-05 06:00:00',
      'label': '12:00 – 13:00',
    },
    'break_exempt': false,
    'late_minutes': 0,
    'early_minutes': 0,
    'overtime_minutes': 0,
    'missing': false,
    'off': null,
    'punches': [
      {
        'kind': 'check_in',
        'at': '2026-10-05 00:54:00',
        'source': 'kiosk',
        'place': 'Produksi Lt. 1',
      },
    ],
  },
  'for_you': [
    {'kind': 'leave_approvals', 'count': 3, 'oldest_at': '2026-10-03 02:10:00'},
    {
      'kind': 'my_leave',
      'id': 412,
      'state': 'confirm',
      'type': 'Annual leave',
      'date_from': '2026-10-12',
      'date_to': '2026-10-13',
      'approver': 'Hendra Wijaya',
      'reason': '',
    },
    {
      'kind': 'my_expense',
      'id': 88,
      'state': 'submitted',
      'name': 'Transport',
      'amount': 350000.0,
      'currency': 'IDR',
    },
    {
      'kind': 'payslip',
      'id': 51,
      'period': 'September 2026',
      'issued_on': '2026-09-30',
    },
  ],
  'week': [
    {'date': '2026-10-05', 'kind': 'today'},
    {'date': '2026-10-06', 'kind': 'scheduled'},
    {'date': '2026-10-07', 'kind': 'scheduled'},
    {'date': '2026-10-08', 'kind': 'public_holiday', 'name': 'Deepavali'},
    {'date': '2026-10-09', 'kind': 'leave', 'name': 'Annual leave'},
    {'date': '2026-10-10', 'kind': 'off'},
    {'date': '2026-10-11', 'kind': 'off'},
  ],
  'next_shift': {'date': '2026-10-06', 'label': '08:00 – 17:00'},
};

/// [sampleMyDayJson] parsed, with the parts a test wants to vary.
MyDay sampleMyDay({
  String state = 'checked_in',
  bool withShift = true,
  bool kioskOnly = true,
  double hoursToday = 3.2,
  List<Map<String, dynamic>>? punches,
  List<Map<String, dynamic>>? forYou,
  int lateMinutes = 0,
  int earlyMinutes = 0,
  int overtimeMinutes = 0,
  bool missing = false,
  bool breakExempt = false,
  Map<String, dynamic>? off,
  bool withLunch = true,
  List<Map<String, dynamic>>? week,
  bool withNextShift = true,
  // false = a 2.51.0 body: the connector sends no minute counters.
  bool withMinutes = true,
}) {
  final json = sampleMyDayJson();
  final today = Map<String, dynamic>.from(json['today'] as Map);
  today['state'] = state;
  today['kiosk_only'] = kioskOnly;
  today['hours_today'] = hoursToday;
  today['late_minutes'] = lateMinutes;
  today['early_minutes'] = earlyMinutes;
  today['overtime_minutes'] = overtimeMinutes;
  today['missing'] = missing;
  today['break_exempt'] = breakExempt;
  today['off'] = off;
  if (!withShift) today['shift'] = null;
  if (!withLunch) today['lunch'] = null;
  if (!withMinutes) {
    today
      ..remove('late_minutes')
      ..remove('early_minutes')
      ..remove('overtime_minutes');
  }
  if (punches != null) today['punches'] = punches;
  json['today'] = today;
  if (forYou != null) json['for_you'] = forYou;
  if (week != null) json['week'] = week;
  if (!withNextShift) json['next_shift'] = null;
  return MyDay.fromJson(json);
}
