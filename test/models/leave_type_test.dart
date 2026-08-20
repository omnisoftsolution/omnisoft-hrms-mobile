import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/leave_type.dart';

void main() {
  group('LeaveType backdate fields', () {
    test('parses an explicit floor date', () {
      final t = LeaveType.fromJson({
        'id': 1,
        'name': 'Annual',
        'requires_allocation': true,
        'allow_backdated': true,
        'backdate_limit_days': 30,
        'earliest_backdate_date': '2026-04-17',
      });
      expect(t.allowBackdated, isTrue);
      expect(t.backdateLimitDays, 30);
      expect(t.earliestBackdateDate, DateTime(2026, 4, 17));
    });

    test('null floor means unlimited', () {
      final t = LeaveType.fromJson({
        'id': 2,
        'name': 'Unpaid',
        'requires_allocation': false,
        'allow_backdated': true,
        'backdate_limit_days': 0,
        'earliest_backdate_date': null,
      });
      expect(t.allowBackdated, isTrue);
      expect(t.earliestBackdateDate, isNull);
    });

    test('missing fields default to backdating off', () {
      final t = LeaveType.fromJson({
        'id': 3,
        'name': 'Legacy',
        'requires_allocation': false,
      });
      expect(t.allowBackdated, isFalse);
      expect(t.backdateLimitDays, 0);
      expect(t.earliestBackdateDate, isNull);
    });

    test('parses hours_per_day; null on older connectors', () {
      final t = LeaveType.fromJson({
        'id': 4,
        'name': 'Hourly',
        'requires_allocation': true,
        'request_unit': 'hour',
        'virtual_remaining_leaves': 112.0,
        'hours_per_day': 8.0,
      });
      expect(t.hoursPerDay, 8.0);
      final legacy = LeaveType.fromJson({
        'id': 5,
        'name': 'Legacy',
        'requires_allocation': true,
      });
      expect(legacy.hoursPerDay, isNull);
    });
  });
}
