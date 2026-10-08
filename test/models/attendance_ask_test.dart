import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:omni_hr/models/attendance_ask.dart';
import 'package:omni_hr/models/my_day.dart';

Map<String, dynamic> askJson({
  String trigger = 'break_long',
  Object? options,
}) => {
  'trigger': trigger,
  'attendance_id': 812,
  'tapped_at': '2026-10-07 06:55:00',
  'shift_start': '2026-10-07 00:00:00',
  'shift_end': '2026-10-07 10:00:00',
  'last_out': '2026-10-07 04:05:00',
  'suggested_time': '2026-10-07 05:00:00',
  'options':
      options ??
      [
        {
          'code': 'back_at',
          'label': 'Back from break since',
          'needs_time': true,
        },
        {
          'code': 'long_break',
          'label': 'It was a long break',
          'needs_time': false,
        },
        {'code': 'start_now', 'label': 'Starting now', 'needs_time': false},
      ],
};

String _hm(DateTime utc) => DateFormat('HH:mm', 'en_US').format(utc.toLocal());

void main() {
  test('parses a full ask', () {
    final ask = AttendanceAsk.tryParse(askJson())!;
    expect(ask.trigger, 'break_long');
    expect(ask.attendanceId, 812);
    expect(ask.tappedAt, DateTime.utc(2026, 10, 7, 6, 55));
    expect(ask.shiftStart, DateTime.utc(2026, 10, 7));
    expect(ask.shiftEnd, DateTime.utc(2026, 10, 7, 10));
    expect(ask.lastOut, DateTime.utc(2026, 10, 7, 4, 5));
    expect(ask.suggestedTime, DateTime.utc(2026, 10, 7, 5));
    expect(ask.options.map((o) => o.code), [
      'back_at',
      'long_break',
      'start_now',
    ]);
    expect(ask.options.first.label, 'Back from break since');
    expect(ask.options.first.needsTime, isTrue);
    expect(ask.options.last.needsTime, isFalse);
  });

  test('ISO 8601 times with T and Z parse too', () {
    final ask = AttendanceAsk.tryParse({
      ...askJson(),
      'tapped_at': '2026-10-07T06:55:00Z',
    })!;
    expect(ask.tappedAt, DateTime.utc(2026, 10, 7, 6, 55));
  });

  test('tryParse: null for a missing or unusable ask (2.53.x sends none)', () {
    expect(AttendanceAsk.tryParse(null), isNull);
    expect(AttendanceAsk.tryParse('break_long'), isNull);
    expect(AttendanceAsk.tryParse(askJson(options: [])), isNull);
    expect(
      AttendanceAsk.tryParse({...askJson(), 'attendance_id': null}),
      isNull,
    );
    expect(AttendanceAsk.tryParse({...askJson(), 'tapped_at': ''}), isNull);
    expect(AttendanceAsk.tryParse({...askJson(), 'trigger': ''}), isNull);
  });

  test('an option without its own time takes the ask suggestion', () {
    final ask = AttendanceAsk.tryParse(askJson())!;
    expect(ask.options.first.suggestedTime, DateTime.utc(2026, 10, 7, 5));
    final own = AskOption.fromJson({
      'code': 'left_at',
      'label': 'I left at',
      'needs_time': true,
      'suggested_time': '2026-10-06 10:00:00',
    });
    expect(own.suggestedTime, DateTime.utc(2026, 10, 6, 10));
    expect(
      AskOption.listFrom([
        {'code': 'x'},
        'junk',
        null,
      ]),
      isEmpty,
    );
  });

  test('titles per trigger, in local time', () {
    String title(String trigger) =>
        AttendanceAsk.tryParse(askJson(trigger: trigger))!.title;
    expect(
      title('break_long'),
      'You checked out at ${_hm(DateTime.utc(2026, 10, 7, 4, 5))} — 2 h 50 min ago. '
      'What happened?',
    );
    expect(
      title('late_first_in'),
      'Your shift started at ${_hm(DateTime.utc(2026, 10, 7))}. Forgot to check in?',
    );
    expect(
      title('near_end'),
      'Your shift ends at ${_hm(DateTime.utc(2026, 10, 7, 10))}. '
      'Did you forget to check in earlier?',
    );
    expect(
      title('after_end'),
      'Your shift ended at ${_hm(DateTime.utc(2026, 10, 7, 10))}. Starting overtime?',
    );
    expect(title('something_new'), 'Forgot something?');
  });

  test('awayLabel', () {
    expect(awayLabel(const Duration(minutes: 50)), '50 min');
    expect(awayLabel(const Duration(minutes: 120)), '2 h');
    expect(awayLabel(const Duration(minutes: 170)), '2 h 50 min');
  });

  test('footnote names the tap in local time', () {
    expect(
      AttendanceAsk.tryParse(askJson())!.footnote,
      'Your check-in stays at ${_hm(DateTime.utc(2026, 10, 7, 6, 55))}. '
      'HR will review your answer.',
    );
  });

  test('ForYouItem parses the yesterday fields', () {
    final item = ForYouItem.fromJson({
      'kind': 'yesterday_incomplete',
      'date': '2026-10-06',
      'verdict': 'no_checkout',
      'attendance_id': 798,
      'title': 'Yesterday looks incomplete',
      'body': 'No check-out was recorded for Tue 6 Oct. Tell HR when you left.',
      'options': [
        {
          'code': 'left_at',
          'label': 'I left at',
          'needs_time': true,
          'suggested_time': '2026-10-06 10:00:00',
        },
      ],
    });
    expect(item.date, '2026-10-06');
    expect(item.attendanceId, 798);
    expect(item.title, 'Yesterday looks incomplete');
    expect(
      item.body,
      'No check-out was recorded for Tue 6 Oct. Tell HR when you left.',
    );
    expect(item.options.single.code, 'left_at');
    expect(item.options.single.suggestedTime, DateTime.utc(2026, 10, 6, 10));
    expect(const ForYouItem(kind: 'payslip').options, isEmpty);
  });
}
