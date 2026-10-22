/// Models for the team leave outlook (`POST leave/team_outlook`) and the
/// apply sheet's "Also off" line (`POST leave/team_overlap`), connector
/// 2.65.0. Every key is optional: a missing or wrongly typed value reads
/// as its default and nothing throws. Dates are local calendar days,
/// `DateTime(y, m, d)` from the server's `YYYY-MM-DD`. A row that cannot
/// work without a date (a leave, a day) is dropped at parse time.
library;

String _str(Object? v) => v is String ? v : '';
String? _optStr(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _optInt(Object? v) => v is num ? v.toInt() : null;
double _dbl(Object? v) => v is num ? v.toDouble() : 0.0;

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
];

final _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `YYYY-MM-DD` as a local calendar day; null for anything else,
/// including a day that does not exist (2026-02-31).
DateTime? _date(Object? v) {
  if (v is! String) return null;
  final m = _ymd.firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final day = DateTime(y, mo, d);
  if (day.year != y || day.month != mo || day.day != d) return null;
  return day;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Who "the team" is: `team.kind` is department | approver | approvees |
/// company | overview.
class TeamScope {
  final String kind;
  final String label;
  final int size;
  final int? departmentId;

  const TeamScope({
    required this.kind,
    required this.label,
    required this.size,
    this.departmentId,
  });

  factory TeamScope.fromJson(Map<String, dynamic> json) => TeamScope(
    kind: _str(json['kind']),
    label: _str(json['label']),
    size: _int(json['size']),
    departmentId: _optInt(json['department_id']),
  );
}

/// What colleagues see of each other's leave (HR settings): the leave
/// type, and pending (not yet approved) requests. Both are off unless the
/// server sends `true` (pending off by default, D3 r5, A-L25). A row may
/// still carry a type or a pending state: the viewer's own, or one the
/// viewer approves (the server decides, L1).
class TeamDisclosure {
  final bool showType;
  final bool showPending;

  const TeamDisclosure({this.showType = false, this.showPending = false});

  factory TeamDisclosure.fromJson(Map<String, dynamic> json) => TeamDisclosure(
    showType: json['show_type'] == true,
    showPending: json['show_pending'] == true,
  );
}

/// A department chip. [size] is 0 when the server leaves it out (the
/// overview's list).
class TeamDepartment {
  final int id;
  final String name;
  final int size;

  const TeamDepartment({required this.id, required this.name, this.size = 0});

  factory TeamDepartment.fromJson(Map<String, dynamic> json) => TeamDepartment(
    id: _int(json['id']),
    name: _str(json['name']),
    size: _int(json['size']),
  );

  /// Departments with a usable id, in the server's order.
  static List<TeamDepartment> listFrom(Object? v) => _maps(v)
      .map(TeamDepartment.fromJson)
      .where((d) => d.id > 0)
      .toList();
}

class TeamFace {
  final int id;
  final String initials;

  const TeamFace({required this.id, required this.initials});

  factory TeamFace.fromJson(Map<String, dynamic> json) =>
      TeamFace(id: _int(json['id']), initials: _str(json['initials']));
}

/// The LEAVE tab row's line: people off this week and up to two faces.
class TeamSummary {
  final int thisWeekOff;
  final String label;
  final List<TeamFace> faces;

  const TeamSummary({
    required this.thisWeekOff,
    required this.label,
    this.faces = const [],
  });

  static const empty = TeamSummary(thisWeekOff: 0, label: '');

  factory TeamSummary.fromJson(Map<String, dynamic> json) => TeamSummary(
    thisWeekOff: _int(json['this_week_off']),
    label: _str(json['label']),
    faces: _maps(json['faces']).map(TeamFace.fromJson).toList(),
  );
}

class TeamPerson {
  final int id;
  final String name;
  final String initials;
  final String department;
  final bool you;

  const TeamPerson({
    required this.id,
    required this.name,
    this.initials = '',
    this.department = '',
    this.you = false,
  });

  factory TeamPerson.fromJson(Map<String, dynamic> json) => TeamPerson(
    id: _int(json['id']),
    name: _str(json['name']),
    initials: _str(json['initials']),
    department: _str(json['department']),
    you: json['you'] == true,
  );
}

/// One leave request, in the shape shared by `team_outlook.leaves[]`,
/// `team_overlap.people[]` and the person sheet's `leave_week[]`.
/// [name] is set on overlap rows only; in the outlook the name comes from
/// [TeamOutlook.person]. [dateTo] is never before [dateFrom].
class TeamLeaveRow {
  final int id;
  final int employeeId;
  final String name;
  final DateTime dateFrom;
  final DateTime dateTo;

  /// am | pm | null (a full day, or hours).
  final String? fromPeriod;
  final String? toPeriod;
  final double hourFrom;
  final double hourTo;
  final double numberOfDays;

  /// day | half_day | hours.
  final String unit;

  /// approved | pending.
  final String state;

  /// The leave type, only when the server chose to send it (D4).
  final String? type;

  const TeamLeaveRow({
    this.id = 0,
    this.employeeId = 0,
    this.name = '',
    required this.dateFrom,
    required this.dateTo,
    this.fromPeriod,
    this.toPeriod,
    this.hourFrom = 0.0,
    this.hourTo = 0.0,
    this.numberOfDays = 0.0,
    this.unit = 'day',
    this.state = 'approved',
    this.type,
  });

  bool get isPending => state == 'pending';
  bool get isHours => unit == 'hours';

  /// True when [day] (any time of it) is between [dateFrom] and [dateTo].
  bool covers(DateTime day) {
    final d = _dayOnly(day);
    return !d.isBefore(dateFrom) && !d.isAfter(dateTo);
  }

  static String? _period(Object? v) => v == 'am' || v == 'pm' ? v as String : null;

  /// Null when `date_from` is missing or not a real `YYYY-MM-DD`.
  static TeamLeaveRow? tryParse(Map<String, dynamic> json) {
    final from = _date(json['date_from']);
    if (from == null) return null;
    final to = _date(json['date_to']);
    final unit = _str(json['unit']);
    final state = _str(json['state']);
    return TeamLeaveRow(
      id: _int(json['id']),
      employeeId: _int(json['employee_id']),
      name: _str(json['name']),
      dateFrom: from,
      dateTo: to == null || to.isBefore(from) ? from : to,
      fromPeriod: _period(json['from_period']),
      toPeriod: _period(json['to_period']),
      hourFrom: _dbl(json['hour_from']),
      hourTo: _dbl(json['hour_to']),
      numberOfDays: _dbl(json['number_of_days']),
      unit: unit.isEmpty ? 'day' : unit,
      state: state.isEmpty ? 'approved' : state,
      type: _optStr(json['type']),
    );
  }

  static List<TeamLeaveRow> listFrom(Object? v) =>
      _maps(v).map(tryParse).whereType<TeamLeaveRow>().toList();
}

/// A public holiday: in `holidays[]` it has a [date]; inside a day it
/// does not.
class TeamHoliday {
  final DateTime? date;
  final String name;

  /// True when it applies to everyone in the set (shown as "PH").
  final bool everyone;

  const TeamHoliday({this.date, required this.name, this.everyone = false});

  factory TeamHoliday.fromJson(Map<String, dynamic> json) => TeamHoliday(
    date: _date(json['date']),
    name: _str(json['name']),
    everyone: json['everyone'] == true,
  );
}

/// One heat-map cell.
class TeamDay {
  final DateTime date;

  /// Distinct people off that day (on a day their calendar works).
  final int off;

  /// The pending part of [off].
  final int pending;

  /// Someone in the set works this weekday.
  final bool workday;
  final TeamHoliday? holiday;

  const TeamDay({
    required this.date,
    this.off = 0,
    this.pending = 0,
    this.workday = true,
    this.holiday,
  });

  static TeamDay? tryParse(Map<String, dynamic> json) {
    final date = _date(json['date']);
    if (date == null) return null;
    final holiday = _map(json['holiday']);
    return TeamDay(
      date: date,
      off: _int(json['off']),
      pending: _int(json['pending']),
      workday: json['workday'] is bool ? json['workday'] as bool : true,
      holiday: holiday == null ? null : TeamHoliday.fromJson(holiday),
    );
  }
}

class TeamOutlook {
  /// team | overview.
  final String context;

  /// team | approvees | company in the team context (default 'team');
  /// null in the overview context, where the server sends `view: null`.
  final String? view;

  /// The views this viewer may switch between (team context).
  final List<String> views;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final int rangeDays;
  final DateTime? today;
  final TeamScope? team;

  /// null | off | no_department | no_approver | no_people.
  final String? emptyReason;
  final TeamDisclosure disclosure;

  /// Overview context with company access only.
  final List<TeamDepartment> departments;
  final TeamSummary summary;
  final List<TeamPerson> people;
  final List<TeamLeaveRow> leaves;
  final List<TeamDay> days;
  final List<TeamHoliday> holidays;
  final bool truncated;

  /// The decoded body, for TeamCache (read back with [TeamOutlook.fromJson]).
  final Map<String, dynamic> raw;

  const TeamOutlook({
    this.context = 'team',
    this.view = 'team',
    this.views = const [],
    this.rangeFrom,
    this.rangeTo,
    this.rangeDays = 30,
    this.today,
    this.team,
    this.emptyReason,
    this.disclosure = const TeamDisclosure(),
    this.departments = const [],
    this.summary = TeamSummary.empty,
    this.people = const [],
    this.leaves = const [],
    this.days = const [],
    this.holidays = const [],
    this.truncated = false,
    this.raw = const {},
  });

  factory TeamOutlook.fromJson(Map<String, dynamic> json) {
    final range = _map(json['range']) ?? const <String, dynamic>{};
    final team = _map(json['team']);
    final disclosure = _map(json['disclosure']);
    final summary = _map(json['summary']);
    final views = json['views'];
    final context = _str(json['context']);
    final view = _str(json['view']);
    final days = _int(range['days']);
    final overview = context == 'overview';
    return TeamOutlook(
      context: context.isEmpty ? 'team' : context,
      view: overview ? null : (view.isEmpty ? 'team' : view),
      views: [
        if (views is List)
          for (final v in views)
            if (v is String && v.isNotEmpty) v,
      ],
      rangeFrom: _date(range['from']),
      rangeTo: _date(range['to']),
      rangeDays: days > 0 ? days : 30,
      today: _date(json['today']),
      team: team == null ? null : TeamScope.fromJson(team),
      emptyReason: _optStr(json['empty_reason']),
      disclosure: disclosure == null
          ? const TeamDisclosure()
          : TeamDisclosure.fromJson(disclosure),
      departments: TeamDepartment.listFrom(json['departments']),
      summary: summary == null ? TeamSummary.empty : TeamSummary.fromJson(summary),
      people: _maps(json['people']).map(TeamPerson.fromJson).toList(),
      leaves: TeamLeaveRow.listFrom(json['leaves']),
      days: _maps(json['days']).map(TeamDay.tryParse).whereType<TeamDay>().toList(),
      holidays: _maps(json['holidays'])
          .map(TeamHoliday.fromJson)
          .where((h) => h.date != null)
          .toList(),
      truncated: json['truncated'] == true,
      raw: json,
    );
  }

  /// No one is off in the range (the "Everyone's in" state).
  bool get isEmpty => leaves.isEmpty;

  TeamPerson? person(int id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The heat-map cell for [d] (any time of that day), or null.
  TeamDay? dayOf(DateTime d) {
    for (final day in days) {
      if (_sameDay(day.date, d)) return day;
    }
    return null;
  }

  /// The leaves whose dates cover [d], in the server's order. Pure date
  /// coverage: a leave over a weekend also covers the weekend days.
  List<TeamLeaveRow> leavesOn(DateTime d) =>
      leaves.where((r) => r.covers(d)).toList();
}

/// `leave/team_overlap`: up to 5 people off on the dates being applied
/// for, plus [more]. Never carries the leave type.
class TeamOverlap {
  final List<TeamLeaveRow> people;
  final int more;

  /// null | off | no_department | no_approver | no_people.
  final String? emptyReason;

  const TeamOverlap({
    this.people = const [],
    this.more = 0,
    this.emptyReason,
  });

  factory TeamOverlap.fromJson(Map<String, dynamic> json) => TeamOverlap(
    people: TeamLeaveRow.listFrom(json['people']),
    more: _int(json['more']),
    emptyReason: _optStr(json['empty_reason']),
  );

  bool get isEmpty => people.isEmpty;
}
