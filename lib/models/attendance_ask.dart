/// "Forgot something?" (connector 2.54.0, spec 2026-10-07 §3.2, §4.6):
/// the question in a check-in response, its options and the employee's
/// answer. Times arrive as the API's UTC strings ("yyyy-MM-dd HH:mm:ss",
/// ISO 8601 accepted) and are kept as UTC DateTimes.
library;

import 'package:intl/intl.dart';

import '../core/datetime_utils.dart';

DateTime? _utc(Object? value) =>
    value is String ? DateTimeUtils.parseOdooUtc(value) : null;

String _str(Object? value) => value is String ? value : '';

String _hhmm(DateTime? utc) =>
    utc == null ? '' : DateFormat('HH:mm', 'en_US').format(utc.toLocal());

/// Answers the server records nothing for (spec §3.3).
const nothingToDeclare = {'start_now', 'just_arriving', 'overtime'};

/// "2 h 50 min", "50 min", "2 h".
String awayLabel(Duration away) {
  final minutes = away.inMinutes;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

/// One answer the sheet offers; a [needsTime] answer carries a time chip.
class AskOption {
  const AskOption({
    required this.code,
    required this.label,
    this.needsTime = false,
    this.suggestedTime,
  });

  final String code;
  final String label;
  final bool needsTime;

  /// UTC; null when the server suggests nothing.
  final DateTime? suggestedTime;

  factory AskOption.fromJson(
    Map<String, dynamic> json, {
    DateTime? fallbackTime,
  }) => AskOption(
    code: _str(json['code']),
    label: _str(json['label']),
    needsTime: json['needs_time'] == true,
    suggestedTime: _utc(json['suggested_time']) ?? fallbackTime,
  );

  /// The usable options of a JSON list (code and label present).
  static List<AskOption> listFrom(Object? value, {DateTime? fallbackTime}) => [
    if (value is List)
      for (final e in value)
        if (e is Map)
          AskOption.fromJson(
            Map<String, dynamic>.from(e),
            fallbackTime: fallbackTime,
          ),
  ].where((o) => o.code.isNotEmpty && o.label.isNotEmpty).toList();
}

/// The `ask` of a check-in response (connector 2.54.0+; absent on 2.53.x).
class AttendanceAsk {
  const AttendanceAsk({
    required this.trigger,
    required this.attendanceId,
    required this.tappedAt,
    this.shiftStart,
    this.shiftEnd,
    this.lastOut,
    this.suggestedTime,
    required this.options,
  });

  /// after_end | near_end | break_long | late_first_in.
  final String trigger;
  final int attendanceId;
  final DateTime tappedAt;
  final DateTime? shiftStart;
  final DateTime? shiftEnd;
  final DateTime? lastOut;
  final DateTime? suggestedTime;
  final List<AskOption> options;

  /// null when the body is missing or unusable: nothing is asked.
  static AttendanceAsk? tryParse(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final trigger = _str(map['trigger']);
    final id = map['attendance_id'];
    final tapped = _utc(map['tapped_at']);
    final suggested = _utc(map['suggested_time']);
    final options = AskOption.listFrom(map['options'], fallbackTime: suggested);
    if (trigger.isEmpty || id is! num || tapped == null || options.isEmpty) {
      return null;
    }
    return AttendanceAsk(
      trigger: trigger,
      attendanceId: id.toInt(),
      tappedAt: tapped,
      shiftStart: _utc(map['shift_start']),
      shiftEnd: _utc(map['shift_end']),
      lastOut: _utc(map['last_out']),
      suggestedTime: suggested,
      options: options,
    );
  }

  /// The sheet's question (mockups "Forgot something? — A").
  String get title {
    switch (trigger) {
      case 'break_long':
        final out = lastOut;
        if (out == null) {
          return 'You were away longer than your break. What happened?';
        }
        return 'You checked out at ${_hhmm(out)} — '
            '${awayLabel(tappedAt.difference(out))} ago. What happened?';
      case 'late_first_in':
        return 'Your shift started at ${_hhmm(shiftStart)}. Forgot to check in?';
      case 'near_end':
        return 'Your shift ends at ${_hhmm(shiftEnd)}. '
            'Did you forget to check in earlier?';
      case 'after_end':
        return 'Your shift ended at ${_hhmm(shiftEnd)}. Starting overtime?';
      default:
        return 'Forgot something?';
    }
  }

  /// D6: the tap stays on record; nothing implies a corrected time.
  String get footnote =>
      'Your check-in stays at ${_hhmm(tappedAt)}. HR will review your answer.';
}

/// What the employee picked in the sheet. [time] is UTC; [note] trimmed.
class DeclarationAnswer {
  const DeclarationAnswer({required this.code, this.time, this.note = ''});

  final String code;
  final DateTime? time;
  final String note;
}
