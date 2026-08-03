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

  group('AttendanceStatus network_gate parsing', () {
    test('parses wifi_required and expected_ssids', () {
      final s = AttendanceStatus.fromJson({
        'checked_in': false,
        'hours_today': 0,
        'employee_id': 1,
        'auth_type': 'session',
        'network_gate': {
          'wifi_required': true,
          'expected_ssids': ['Office-WiFi', 'Office-WiFi-5G'],
        },
      });
      expect(s.wifiRequired, isTrue);
      expect(s.expectedSsids, ['Office-WiFi', 'Office-WiFi-5G']);
    });

    test('defaults when network_gate absent (old connector)', () {
      final s = AttendanceStatus.fromJson({
        'checked_in': false,
        'hours_today': 0,
        'employee_id': 1,
        'auth_type': 'session',
      });
      expect(s.wifiRequired, isFalse);
      expect(s.expectedSsids, isEmpty);
    });
  });
}
