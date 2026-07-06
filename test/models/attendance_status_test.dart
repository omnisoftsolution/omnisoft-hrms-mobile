import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/attendance_status.dart';

void main() {
  group('AttendanceStatus.flexibleLocation', () {
    test('parses true from flexible_location', () {
      final s = AttendanceStatus.fromJson({
        'checked_in': false,
        'hours_today': 0,
        'employee_id': 7,
        'auth_type': 'token',
        'flexible_location': true,
      });
      expect(s.flexibleLocation, isTrue);
    });

    test('defaults to false when absent (old server)', () {
      final s = AttendanceStatus.fromJson({
        'checked_in': false,
        'hours_today': 0,
        'employee_id': 7,
        'auth_type': 'token',
      });
      expect(s.flexibleLocation, isFalse);
    });
  });
}
