import 'package:omni_hr/models/team_outlook.dart';

/// Today in every team fixture: Thursday 22 October 2026.
final fixtureToday = DateTime(2026, 10, 22);

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The default people: the viewer (Alexa Tan) and two colleagues.
const fixturePeople = [
  {'id': 3, 'name': 'Alexa Tan', 'initials': 'AT', 'department': 'Marketing', 'you': true},
  {'id': 12, 'name': 'Mei Lin Ong', 'initials': 'MO', 'department': 'Marketing', 'you': false},
  {'id': 14, 'name': 'Priya Nair', 'initials': 'PN', 'department': 'Marketing', 'you': false},
];

/// The default leaves: Mei Lin's morning today, Priya's pending day
/// today, Alexa's two days 12–13 Nov with a type.
const fixtureLeaves = [
  {
    'id': 901, 'employee_id': 12, 'date_from': '2026-10-22', 'date_to': '2026-10-22',
    'from_period': 'am', 'to_period': 'am', 'hour_from': 0.0, 'hour_to': 0.0,
    'number_of_days': 0.5, 'unit': 'half_day', 'state': 'approved', 'type': null,
  },
  {
    'id': 902, 'employee_id': 14, 'date_from': '2026-10-22', 'date_to': '2026-10-22',
    'from_period': null, 'to_period': null, 'hour_from': 0.0, 'hour_to': 0.0,
    'number_of_days': 1.0, 'unit': 'day', 'state': 'pending', 'type': null,
  },
  {
    'id': 903, 'employee_id': 3, 'date_from': '2026-11-12', 'date_to': '2026-11-13',
    'from_period': null, 'to_period': null, 'hour_from': 0.0, 'hour_to': 0.0,
    'number_of_days': 2.0, 'unit': 'day', 'state': 'approved', 'type': 'Annual Leave',
  },
];

/// A `leave/team_outlook` body in the contract shape, [days] days from
/// [fixtureToday]. Weekends are not workdays. [off] / [pending] set
/// `days[].off` / `.pending` by ISO date; [holidays] sets `days[].holiday`
/// (`{'name', 'everyone'}`) by ISO date. [showType] / [showPending] are the
/// HR settings, both off by default as on the server (D3, A-L25).
Map<String, dynamic> outlookJson({
  int days = 30,
  String context = 'team',
  String view = 'team',
  List<String> views = const ['team'],
  String? emptyReason,
  bool showType = false,
  bool showPending = false,
  Map<String, dynamic> team = const {
    'kind': 'department', 'label': 'Marketing', 'size': 12, 'department_id': 5,
  },
  List<Map<String, dynamic>>? departments,
  Map<String, int> off = const {'2026-10-22': 2, '2026-11-12': 1, '2026-11-13': 1},
  Map<String, int> pending = const {'2026-10-22': 1},
  Map<String, Map<String, Object>> holidays = const {},
  List<Map<String, dynamic>> people = fixturePeople,
  List<Map<String, dynamic>> leaves = fixtureLeaves,
  bool truncated = false,
}) {
  final last = DateTime(fixtureToday.year, fixtureToday.month, fixtureToday.day + days - 1);
  return {
    'success': true,
    'context': context,
    'view': view,
    'views': views,
    'range': {'from': _iso(fixtureToday), 'to': _iso(last), 'days': days},
    'today': _iso(fixtureToday),
    'team': team,
    'empty_reason': emptyReason,
    'disclosure': {'show_type': showType, 'show_pending': showPending},
    'departments': ?departments,
    'summary': {'this_week_off': 2, 'label': team['label'], 'faces': []},
    'people': emptyReason == null ? people : const [],
    'leaves': emptyReason == null ? leaves : const [],
    'days': [
      for (var i = 0; i < days; i++)
        () {
          final d = DateTime(fixtureToday.year, fixtureToday.month, fixtureToday.day + i);
          final iso = _iso(d);
          return {
            'date': iso,
            'off': emptyReason == null ? (off[iso] ?? 0) : 0,
            'pending': emptyReason == null ? (pending[iso] ?? 0) : 0,
            'workday': d.weekday <= DateTime.friday,
            'holiday': holidays[iso],
          };
        }(),
    ],
    'holidays': [
      for (final e in holidays.entries) {'date': e.key, ...e.value},
    ],
    'truncated': truncated,
    'auth_type': 'session',
  };
}

TeamOutlook outlook({
  int days = 30,
  String context = 'team',
  String view = 'team',
  List<String> views = const ['team'],
  String? emptyReason,
  bool showType = false,
  bool showPending = false,
  Map<String, dynamic>? team,
  List<Map<String, dynamic>>? departments,
  Map<String, int>? off,
  Map<String, Map<String, Object>> holidays = const {},
  List<Map<String, dynamic>>? leaves,
  bool truncated = false,
}) => TeamOutlook.fromJson(
  outlookJson(
    days: days,
    context: context,
    view: view,
    views: views,
    emptyReason: emptyReason,
    showType: showType,
    showPending: showPending,
    team: team ?? const {
      'kind': 'department', 'label': 'Marketing', 'size': 12, 'department_id': 5,
    },
    departments: departments,
    off: off ?? const {'2026-10-22': 2, '2026-11-12': 1, '2026-11-13': 1},
    holidays: holidays,
    leaves: leaves ?? fixtureLeaves,
    truncated: truncated,
  ),
);

/// One leave row parsed the way the outlook parses it.
TeamLeaveRow leaveRow(Map<String, dynamic> json) =>
    TeamOutlook.fromJson({'leaves': [json]}).leaves.single;
