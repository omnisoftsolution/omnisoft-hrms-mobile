/// Models for the My day home (`POST /home/my_day`, connector 2.51.0+,
/// spec 2026-10-05 §4.2). Datetimes stay as the server's UTC strings
/// ("yyyy-MM-dd HH:mm:ss"); widgets format them with DateTimeUtils.
library;

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

/// Today's expected shift. [label] is already in the employee's timezone.
class MyDayShift {
  final String start;
  final String end;
  final String label;

  const MyDayShift({
    required this.start,
    required this.end,
    required this.label,
  });

  factory MyDayShift.fromJson(Map<String, dynamic> json) => MyDayShift(
        start: _str(json['start']),
        end: _str(json['end']),
        label: _str(json['label']),
      );
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

  const MyDay({
    required this.date,
    required this.tz,
    required this.kioskOnly,
    required this.state,
    required this.hoursToday,
    required this.shift,
    required this.punches,
    required this.forYou,
  });

  factory MyDay.fromJson(Map<String, dynamic> json) {
    final today = _map(json['today']) ?? const <String, dynamic>{};
    final shift = _map(today['shift']);
    final state = _str(today['state']);
    return MyDay(
      date: _str(json['date']),
      tz: _str(json['tz']),
      kioskOnly: today['kiosk_only'] == true,
      state: state.isEmpty ? 'not_in' : state,
      hoursToday: _dbl(today['hours_today']),
      shift: shift == null ? null : MyDayShift.fromJson(shift),
      punches: _maps(today['punches']).map(MyDayPunch.fromJson).toList(),
      forYou: _maps(json['for_you'])
          .map(ForYouItem.fromJson)
          .where((item) => item.isKnown)
          .toList(),
    );
  }
}
