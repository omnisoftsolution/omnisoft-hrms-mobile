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
        },
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
        {
          'kind': 'leave_approvals',
          'count': 3,
          'oldest_at': '2026-10-03 02:10:00',
        },
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
    };

/// [sampleMyDayJson] parsed, with the parts a test wants to vary.
MyDay sampleMyDay({
  String state = 'checked_in',
  bool withShift = true,
  bool kioskOnly = true,
  double hoursToday = 3.2,
  List<Map<String, dynamic>>? punches,
  List<Map<String, dynamic>>? forYou,
}) {
  final json = sampleMyDayJson();
  final today = Map<String, dynamic>.from(json['today'] as Map);
  today['state'] = state;
  today['kiosk_only'] = kioskOnly;
  today['hours_today'] = hoursToday;
  if (!withShift) today['shift'] = null;
  if (punches != null) today['punches'] = punches;
  json['today'] = today;
  if (forYou != null) json['for_you'] = forYou;
  return MyDay.fromJson(json);
}
