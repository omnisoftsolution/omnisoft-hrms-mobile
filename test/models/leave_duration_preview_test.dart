import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/leave_duration_preview.dart';

void main() {
  group('LeaveDurationPreview.fromJson', () {
    test('parses the connector payload', () {
      final p = LeaveDurationPreview.fromJson({
        'success': true,
        'number_of_days': 0.375,
        'number_of_hours': 3.0,
        'request_unit': 'hour',
      });
      expect(p.days, 0.375);
      expect(p.hours, 3.0);
      expect(p.requestUnit, 'hour');
    });

    test('accepts integer numbers from JSON', () {
      final p = LeaveDurationPreview.fromJson({
        'number_of_days': 2,
        'number_of_hours': 16,
        'request_unit': 'hour',
      });
      expect(p.days, 2.0);
      expect(p.hours, 16.0);
    });

    test('missing fields default to zero / day', () {
      final p = LeaveDurationPreview.fromJson({});
      expect(p.days, 0.0);
      expect(p.hours, 0.0);
      expect(p.requestUnit, 'day');
    });
  });
}
