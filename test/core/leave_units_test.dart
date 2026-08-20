import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/leave_units.dart';

void main() {
  group('balanceAmountLabel', () {
    test('hour unit: hours first with day equivalent', () {
      expect(balanceAmountLabel(112.0, 'hour', 8.0, longForm: false),
          '112h (14d)');
      expect(balanceAmountLabel(112.0, 'hour', 8.0, longForm: true),
          '112 hours (14 days)');
    });

    test('hour unit: fractional values get one decimal', () {
      expect(balanceAmountLabel(9.5, 'hour', 8.0, longForm: false),
          '9.5h (1.2d)');
    });

    test('hour unit: missing hours_per_day falls back to 8', () {
      expect(balanceAmountLabel(112.0, 'hour', null, longForm: false),
          '112h (14d)');
    });

    test('day unit: unchanged, no equivalent', () {
      expect(balanceAmountLabel(6.0, 'day', 8.0, longForm: false), '6d');
      expect(balanceAmountLabel(6.0, 'day', 8.0, longForm: true), '6 days');
      expect(balanceAmountLabel(2.5, 'half_day', 8.0, longForm: false),
          '2.5d');
    });
  });

  group('compactDaysWithHours', () {
    test('whole days with hour equivalent', () {
      expect(compactDaysWithHours(2.0, 8.0), '2d (16h)');
      expect(compactDaysWithHours(1.0, 8.0), '1d (8h)');
    });

    test('fractional days', () {
      expect(compactDaysWithHours(1.5, 8.0), '1.5d (12h)');
    });

    test('custom hours per day', () {
      expect(compactDaysWithHours(2.0, 7.5), '2d (15h)');
    });
  });
}
