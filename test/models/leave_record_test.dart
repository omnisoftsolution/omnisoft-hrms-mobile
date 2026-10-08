import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/leave_record.dart';

void main() {
  group('LeaveRecord backdate fields', () {
    test('parses allow_backdated and earliest_backdate_date', () {
      final r = LeaveRecord.fromJson({
        'id': 1,
        'leave_type': 'Annual',
        'number_of_days': 1,
        'state': 'confirm',
        'allow_backdated': true,
        'earliest_backdate_date': '2026-04-17',
      });
      expect(r.allowBackdated, isTrue);
      expect(r.earliestBackdateDate, DateTime(2026, 4, 17));
    });
    test('defaults when fields absent', () {
      final r = LeaveRecord.fromJson({
        'id': 2, 'leave_type': 'X', 'number_of_days': 1, 'state': 'confirm',
      });
      expect(r.allowBackdated, isFalse);
      expect(r.earliestBackdateDate, isNull);
    });
  });

  group('dates on the History card', () {
    LeaveRecord rec(Map<String, dynamic> j) => LeaveRecord.fromJson({
      'id': 4,
      'leave_type': 'Annual',
      'state': 'confirm',
      'number_of_days': 1,
      ...j,
    });

    test('a single day and a range', () {
      expect(
        rec({'date_from': '2026-10-26', 'date_to': '2026-10-26'}).summaryLabel,
        'Mon 26 Oct · 1d',
      );
      expect(
        rec({
          'date_from': '2026-10-22',
          'date_to': '2026-10-23',
          'number_of_days': 2,
        }).summaryLabel,
        'Thu 22 Oct – Fri 23 Oct · 2d',
      );
    });

    test('specific hours show the times and the hours', () {
      expect(
        rec({
          'date_from': '2026-11-03',
          'date_to': '2026-11-03',
          'request_unit': 'hour',
          'hour_from': 14.0,
          'hour_to': 17.0,
          'number_of_hours': 3,
        }).summaryLabel,
        'Tue 3 Nov, 14:00 – 17:00 · 3h',
      );
      // Full-day hour leave: hour fields 0 -> plain day, hours duration.
      expect(
        rec({
          'date_from': '2026-11-03',
          'date_to': '2026-11-03',
          'request_unit': 'hour',
          'hour_from': 0,
          'hour_to': 0,
          'number_of_hours': 8,
        }).summaryLabel,
        'Tue 3 Nov · 8h',
      );
    });

    test('half a day names the half; a whole half-day-type day does not', () {
      Map<String, dynamic> half(String a, String b) => {
        'date_from': '2026-11-02',
        'date_to': '2026-11-02',
        'request_unit': 'half_day',
        'date_from_period': a,
        'date_to_period': b,
        'number_of_days': a == b ? 0.5 : 1,
      };
      expect(rec(half('pm', 'pm')).summaryLabel, 'Mon 2 Nov (afternoon) · 0.5d');
      expect(rec(half('am', 'am')).summaryLabel, 'Mon 2 Nov (morning) · 0.5d');
      expect(rec(half('am', 'pm')).summaryLabel, 'Mon 2 Nov · 1d');
      // A day-unit type never shows a half, whatever Odoo stored.
      expect(
        rec({
          'date_from': '2026-11-02',
          'date_to': '2026-11-02',
          'date_from_period': 'am',
          'date_to_period': 'am',
        }).summaryLabel,
        'Mon 2 Nov · 1d',
      );
    });

    test('no dates: just the duration', () {
      expect(rec({}).summaryLabel, '1d');
    });
  });

  group('state labels', () {
    LeaveRecord withState(String s) => LeaveRecord.fromJson({
      'id': 3, 'leave_type': 'X', 'number_of_days': 1, 'state': s,
    });

    test('validate1 waits for HR; it is not approved yet', () {
      expect(withState('validate1').stateLabel, 'Waiting for HR');
      expect(withState('confirm').stateLabel, 'Pending');
      expect(withState('validate').stateLabel, 'Approved');
      expect(withState('refuse').stateLabel, 'Refused');
      expect(withState('cancel').stateLabel, 'Cancelled');
    });
  });
}
