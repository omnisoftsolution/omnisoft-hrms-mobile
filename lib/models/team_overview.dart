/// Models for the Team overview (`POST home/overview`, `home/overview/list`,
/// `home/overview/person`), connector 2.65.0. Same tolerant parsing as
/// team_outlook.dart: every key optional, wrong types read as defaults,
/// dates are local calendar days, times stay the server's local "HH:MM".
library;

import 'dart:math' as math;

import 'my_day.dart';
import 'team_outlook.dart';

String _str(Object? v) => v is String ? v : '';
String? _optStr(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _optInt(Object? v) => v is num ? v.toInt() : null;

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
];

final _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `YYYY-MM-DD` as a local calendar day; null for anything else.
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

/// `note` is `{"kind": …}`; a bare string is accepted too.
String? _noteKind(Object? v) => v is Map ? _optStr(v['kind']) : _optStr(v);

String? _part(Object? v) =>
    v == 'morning' || v == 'afternoon' || v == 'hours' ? v as String : null;

/// Which sections the plan allows. Without the key, a section counts as
/// on when its block was sent.
class OverviewSections {
  final bool attendance;
  final bool leave;

  const OverviewSections({this.attendance = false, this.leave = false});

  factory OverviewSections.fromJson(
    Object? v, {
    required bool attendanceSent,
    required bool leaveSent,
  }) {
    final m = _map(v);
    if (m == null) {
      return OverviewSections(attendance: attendanceSent, leave: leaveSent);
    }
    return OverviewSections(
      attendance: m['attendance'] is bool
          ? m['attendance'] as bool
          : attendanceSent,
      leave: m['leave'] is bool ? m['leave'] as bool : leaveSent,
    );
  }
}

class OverviewScope {
  /// approvees | department | company.
  final String access;
  final String label;
  final int? departmentId;

  /// null | no_department | no_people.
  final String? emptyReason;

  const OverviewScope({
    this.access = '',
    this.label = '',
    this.departmentId,
    this.emptyReason,
  });

  factory OverviewScope.fromJson(Map<String, dynamic> json) => OverviewScope(
    access: _str(json['access']),
    label: _str(json['label']),
    departmentId: _optInt(json['department_id']),
    emptyReason: _optStr(json['empty_reason']),
  );
}

/// Today's live counts. The six buckets are mutually exclusive.
/// [checkedIn], [expected] and [tracked] are kept as sent (null when left
/// out); read them through the total* getters.
class OverviewCounts {
  static const buckets = [
    'on_time',
    'late',
    'not_in_yet',
    'no_check_in',
    'on_leave',
    'off_today',
  ];

  final int onTime;
  final int lateCount;
  final int notInYet;
  final int noCheckIn;
  final int onLeave;
  final int offToday;
  final int? checkedIn;
  final int? expected;
  final int? tracked;

  const OverviewCounts({
    this.onTime = 0,
    this.lateCount = 0,
    this.notInYet = 0,
    this.noCheckIn = 0,
    this.onLeave = 0,
    this.offToday = 0,
    this.checkedIn,
    this.expected,
    this.tracked,
  });

  factory OverviewCounts.fromJson(Map<String, dynamic> json) => OverviewCounts(
    onTime: _int(json['on_time']),
    lateCount: _int(json['late']),
    notInYet: _int(json['not_in_yet']),
    noCheckIn: _int(json['no_check_in']),
    onLeave: _int(json['on_leave']),
    offToday: _int(json['off_today']),
    checkedIn: _optInt(json['checked_in']),
    expected: _optInt(json['expected']),
    tracked: _optInt(json['tracked']),
  );

  int get totalCheckedIn => checkedIn ?? onTime + lateCount;

  int get totalTracked =>
      tracked ?? onTime + lateCount + notInYet + noCheckIn + onLeave + offToday;

  int get totalExpected =>
      expected ?? math.max(0, totalTracked - onLeave - offToday);

  /// The team tile's bar: everyone expected today, in four parts.
  int get totalBar => onTime + lateCount + notInYet + noCheckIn;

  /// The count of one of [buckets]; 0 for anything else.
  int countOf(String bucket) => switch (bucket) {
    'on_time' => onTime,
    'late' => lateCount,
    'not_in_yet' => notInYet,
    'no_check_in' => noCheckIn,
    'on_leave' => onLeave,
    'off_today' => offToday,
    _ => 0,
  };
}

/// Yesterday as the Daily Review scored it (`reviewed`).
class ReviewedDay {
  static const buckets = [
    'on_time',
    'late',
    'left_early',
    'absent',
    'on_leave',
    'off',
  ];

  final DateTime? date;

  /// Still being scored; numbers may change.
  final bool provisional;
  final int onTime;
  final int lateCount;
  final int leftEarly;
  final int absent;
  final int onLeave;
  final int off;

  /// Work was due but the row could not be scored yet (lock busy, cap,
  /// error, night shift still on duty). Part of [expected]; not a tile.
  final int notReviewed;
  final int? worked;
  final int? expected;
  final int? tracked;

  const ReviewedDay({
    this.date,
    this.provisional = false,
    this.onTime = 0,
    this.lateCount = 0,
    this.leftEarly = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.off = 0,
    this.notReviewed = 0,
    this.worked,
    this.expected,
    this.tracked,
  });

  factory ReviewedDay.fromJson(Map<String, dynamic> json) {
    final c = _map(json['counts']) ?? const <String, dynamic>{};
    return ReviewedDay(
      date: _date(json['date']),
      provisional: json['provisional'] == true,
      onTime: _int(c['on_time']),
      lateCount: _int(c['late']),
      leftEarly: _int(c['left_early']),
      absent: _int(c['absent']),
      onLeave: _int(c['on_leave']),
      off: _int(c['off']),
      notReviewed: _int(c['not_reviewed']),
      worked: _optInt(c['worked']),
      expected: _optInt(c['expected']),
      tracked: _optInt(c['tracked']),
    );
  }

  int get totalWorked => worked ?? onTime + lateCount + leftEarly;

  int get totalTracked =>
      tracked ??
      onTime + lateCount + leftEarly + absent + onLeave + off + notReviewed;

  int get totalExpected =>
      expected ?? math.max(0, totalTracked - onLeave - off);

  int countOf(String bucket) => switch (bucket) {
    'on_time' => onTime,
    'late' => lateCount,
    'left_early' => leftEarly,
    'absent' => absent,
    'on_leave' => onLeave,
    'off' => off,
    'not_reviewed' => notReviewed,
    _ => 0,
  };
}

/// A person in Who's out: today's rows use every field; the next-7-days
/// names carry only id, name, department and state.
class WhoOutToday {
  final int id;
  final String name;
  final String initials;
  final String department;

  /// Only when the server sent it (D4); else the row says "On leave".
  final String? type;

  /// approved | pending.
  final String state;

  /// morning | afternoon | hours | null (all day).
  final String? part;
  final DateTime? until;

  /// Local "HH:MM" the person is due back today.
  final String? backAt;

  /// The person is attendance-tracked (`kiosk_enabled`), so the row may
  /// open the person sheet (L2, with `names` only). False when the key is
  /// missing: an older answer never offers a tap that would 404.
  final bool tracked;

  const WhoOutToday({
    this.id = 0,
    this.name = '',
    this.initials = '',
    this.department = '',
    this.type,
    this.state = 'approved',
    this.part,
    this.until,
    this.backAt,
    this.tracked = false,
  });

  factory WhoOutToday.fromJson(Map<String, dynamic> json) {
    final state = _str(json['state']);
    return WhoOutToday(
      id: _int(json['id']),
      name: _str(json['name']),
      initials: _str(json['initials']),
      department: _str(json['department']),
      type: _optStr(json['type']),
      state: state.isEmpty ? 'approved' : state,
      part: _part(json['part']),
      until: _date(json['until']),
      backAt: _optStr(json['back_at']),
      tracked: json['tracked'] == true,
    );
  }

  bool get isPending => state == 'pending';
}

class WhoOutDay {
  final DateTime date;
  final List<WhoOutToday> people;

  const WhoOutDay({required this.date, this.people = const []});

  static WhoOutDay? tryParse(Map<String, dynamic> json) {
    final date = _date(json['date']);
    if (date == null) return null;
    return WhoOutDay(
      date: date,
      people: _maps(json['people']).map(WhoOutToday.fromJson).toList(),
    );
  }
}

class WhoOut {
  final List<WhoOutToday> today;
  final List<WhoOutDay> next7;

  /// `who_out.truncated` (K2): the server bounded the rows, so some people
  /// out are not listed. False when the key is missing (older connector).
  final bool truncated;

  const WhoOut({
    this.today = const [],
    this.next7 = const [],
    this.truncated = false,
  });

  factory WhoOut.fromJson(Map<String, dynamic> json) => WhoOut(
    today: _maps(json['today']).map(WhoOutToday.fromJson).toList(),
    next7: _maps(json['next_7'])
        .map(WhoOutDay.tryParse)
        .whereType<WhoOutDay>()
        .toList(),
    truncated: json['truncated'] == true,
  );
}

class TeamOverview {
  /// today | yesterday.
  final String day;
  final DateTime? date;

  /// Local "HH:MM" the live counts were taken.
  final String asOf;
  final bool live;
  final OverviewScope scope;

  /// Company access only.
  final List<TeamDepartment> departments;
  final OverviewSections sections;

  /// False = counts only (L2): no drill-down, no person sheet.
  final bool names;

  /// Today, with attendance on; null otherwise.
  final OverviewCounts? counts;

  /// Yesterday only.
  final ReviewedDay? reviewed;

  /// Today, with Time Off on; null otherwise.
  final WhoOut? whoOut;

  /// Known kinds only, in the server's order (as My day).
  final List<ForYouItem> forYou;

  /// The decoded body, for TeamCache (read back with [TeamOverview.fromJson]).
  final Map<String, dynamic> raw;

  const TeamOverview({
    this.day = 'today',
    this.date,
    this.asOf = '',
    this.live = false,
    this.scope = const OverviewScope(),
    this.departments = const [],
    this.sections = const OverviewSections(),
    this.names = false,
    this.counts,
    this.reviewed,
    this.whoOut,
    this.forYou = const [],
    this.raw = const {},
  });

  factory TeamOverview.fromJson(Map<String, dynamic> json) {
    final scope = _map(json['scope']);
    final counts = _map(json['counts']);
    final reviewed = _map(json['reviewed']);
    final whoOut = _map(json['who_out']);
    final day = _str(json['day']);
    return TeamOverview(
      day: day.isEmpty ? 'today' : day,
      date: _date(json['date']),
      asOf: _str(json['as_of']),
      live: json['live'] == true,
      scope: scope == null ? const OverviewScope() : OverviewScope.fromJson(scope),
      departments: TeamDepartment.listFrom(json['departments']),
      sections: OverviewSections.fromJson(
        json['sections'],
        attendanceSent: counts != null || reviewed != null,
        leaveSent: whoOut != null,
      ),
      names: json['names'] == true,
      counts: counts == null ? null : OverviewCounts.fromJson(counts),
      reviewed: reviewed == null ? null : ReviewedDay.fromJson(reviewed),
      whoOut: whoOut == null ? null : WhoOut.fromJson(whoOut),
      forYou: _maps(json['for_you'])
          .map(ForYouItem.fromJson)
          .where((item) => item.isKnown)
          .toList(),
      raw: json,
    );
  }
}

/// A shift or one of its blocks, local "HH:MM".
class OverviewShift {
  final String start;
  final String end;
  final List<OverviewShift> blocks;

  const OverviewShift({
    required this.start,
    required this.end,
    this.blocks = const [],
  });

  factory OverviewShift.fromJson(Map<String, dynamic> json) => OverviewShift(
    start: _str(json['start']),
    end: _str(json['end']),
    blocks: _maps(json['blocks']).map(OverviewShift.fromJson).toList(),
  );

  /// "08:30 – 17:30", or the start alone when the end is unknown.
  String get label => end.isEmpty ? start : '$start – $end';
}

/// The leave behind an on-leave or part-day row of the drill-down.
class OverviewRowLeave {
  final String? type;
  final String state;
  final String? part;
  final String? backAt;
  final DateTime? until;

  const OverviewRowLeave({
    this.type,
    this.state = 'approved',
    this.part,
    this.backAt,
    this.until,
  });

  factory OverviewRowLeave.fromJson(Map<String, dynamic> json) {
    final state = _str(json['state']);
    return OverviewRowLeave(
      type: _optStr(json['type']),
      state: state.isEmpty ? 'approved' : state,
      part: _part(json['part']),
      backAt: _optStr(json['back_at']),
      until: _date(json['until']),
    );
  }
}

/// One drill-down row (`home/overview/list`).
class OverviewRow {
  final int id;
  final String name;
  final String initials;
  final String department;
  final bool you;
  final String bucket;
  final String? firstIn;
  final int lateMinutes;
  final OverviewShift? shift;
  final int? minutesSinceStart;
  final int? startsInMin;
  final bool laterToday;
  final bool flexible;

  /// mobile | kiosk | other | '' (no punch).
  final String source;
  final String? kioskName;
  final String? location;

  /// part_day_leave | came_in_on_leave | later_today | flexible | null.
  final String? note;
  final OverviewRowLeave? leave;

  const OverviewRow({
    this.id = 0,
    this.name = '',
    this.initials = '',
    this.department = '',
    this.you = false,
    this.bucket = '',
    this.firstIn,
    this.lateMinutes = 0,
    this.shift,
    this.minutesSinceStart,
    this.startsInMin,
    this.laterToday = false,
    this.flexible = false,
    this.source = '',
    this.kioskName,
    this.location,
    this.note,
    this.leave,
  });

  factory OverviewRow.fromJson(Map<String, dynamic> json) {
    final shift = _map(json['shift']);
    final leave = _map(json['leave']);
    return OverviewRow(
      id: _int(json['id']),
      name: _str(json['name']),
      initials: _str(json['initials']),
      department: _str(json['department']),
      you: json['you'] == true,
      bucket: _str(json['bucket']),
      firstIn: _optStr(json['first_in']),
      lateMinutes: _int(json['late_minutes']),
      shift: shift == null ? null : OverviewShift.fromJson(shift),
      minutesSinceStart: _optInt(json['minutes_since_start']),
      startsInMin: _optInt(json['starts_in_min']),
      laterToday: json['later_today'] == true,
      flexible: json['flexible'] == true,
      source: _str(json['source']),
      kioskName: _optStr(json['kiosk_name']),
      location: _optStr(json['location']),
      note: _noteKind(json['note']),
      leave: leave == null ? null : OverviewRowLeave.fromJson(leave),
    );
  }
}

/// One page of a drill-down bucket.
class OverviewPage {
  final String bucket;

  /// Exact size of the bucket (the chip count).
  final int total;

  /// Offset of the next page; null on the last page.
  final int? nextOffset;
  final List<OverviewRow> rows;

  const OverviewPage({
    this.bucket = '',
    this.total = 0,
    this.nextOffset,
    this.rows = const [],
  });

  factory OverviewPage.fromJson(Map<String, dynamic> json) => OverviewPage(
    bucket: _str(json['bucket']),
    total: _int(json['total']),
    nextOffset: _optInt(json['next_offset']),
    rows: _maps(json['rows']).map(OverviewRow.fromJson).toList(),
  );

  bool get hasMore => nextOffset != null;
}

/// One punch on the person sheet: check_in | check_out | break_start |
/// break_end, at local "HH:MM".
class OverviewPunch {
  final String at;
  final String kind;
  final String source;
  final String? kioskName;
  final String? location;

  const OverviewPunch({
    required this.at,
    required this.kind,
    this.source = '',
    this.kioskName,
    this.location,
  });

  factory OverviewPunch.fromJson(Map<String, dynamic> json) => OverviewPunch(
    at: _str(json['at']),
    kind: _str(json['kind']),
    source: _str(json['source']),
    kioskName: _optStr(json['kiosk_name']),
    location: _optStr(json['location']),
  );
}

/// The person sheet (`home/overview/person`). Never cached (A-L3).
class OverviewPerson {
  final int id;
  final String name;
  final String initials;
  final String department;
  final String calendar;
  final bool you;

  /// Today's bucket (on_time | late | not_in_yet | no_check_in | on_leave
  /// | off_today).
  final String bucket;
  final int lateMinutes;
  final String? note;
  final OverviewShift? shift;
  final List<OverviewPunch> punches;

  /// Today through Sunday; null when Time Off is off (the box is hidden).
  final List<TeamLeaveRow>? leaveWeek;
  final OverviewSections sections;

  const OverviewPerson({
    this.id = 0,
    this.name = '',
    this.initials = '',
    this.department = '',
    this.calendar = '',
    this.you = false,
    this.bucket = '',
    this.lateMinutes = 0,
    this.note,
    this.shift,
    this.punches = const [],
    this.leaveWeek,
    this.sections = const OverviewSections(),
  });

  factory OverviewPerson.fromJson(Map<String, dynamic> json) {
    final person = _map(json['person']) ?? const <String, dynamic>{};
    final today = _map(json['today']) ?? const <String, dynamic>{};
    final shift = _map(json['shift']);
    final leaveWeek = json['leave_week'];
    return OverviewPerson(
      id: _int(person['id']),
      name: _str(person['name']),
      initials: _str(person['initials']),
      department: _str(person['department']),
      calendar: _str(person['calendar']),
      you: person['you'] == true,
      bucket: _str(today['bucket']),
      lateMinutes: _int(today['late_minutes']),
      note: _noteKind(today['note']),
      shift: shift == null ? null : OverviewShift.fromJson(shift),
      punches: _maps(json['punches']).map(OverviewPunch.fromJson).toList(),
      leaveWeek: leaveWeek is List ? TeamLeaveRow.listFrom(leaveWeek) : null,
      sections: OverviewSections.fromJson(
        json['sections'],
        attendanceSent: json['today'] is Map,
        leaveSent: leaveWeek is List,
      ),
    );
  }
}
