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
}
