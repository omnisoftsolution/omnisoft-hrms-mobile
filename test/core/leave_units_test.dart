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

  group('customHoursLabel', () {
    test('server hours win over end-minus-start (lunch break case)', () {
      // 11:00-15:00 is 4h naive, Odoo stores 3h (12-13 lunch).
      expect(customHoursLabel(naiveHours: 4.0, serverHours: 3.0), '3h');
    });

    test('falls back to end-minus-start without a server value', () {
      expect(customHoursLabel(naiveHours: 4.0, serverHours: null), '4h');
      expect(customHoursLabel(naiveHours: 2.5, serverHours: null), '2.5h');
    });

    test('shows an ellipsis while the preview is loading', () {
      expect(customHoursLabel(naiveHours: 4.0, serverHours: null,
          loading: true), '…');
    });

    test('keeps the last server value while reloading', () {
      expect(customHoursLabel(naiveHours: 4.0, serverHours: 3.0,
          loading: true), '3h');
    });

    test('fractional server hours get one decimal', () {
      expect(customHoursLabel(naiveHours: 3.0, serverHours: 2.5), '2.5h');
    });
  });

  group('customHoursCaption', () {
    test('no caption without a server value or when they agree', () {
      expect(customHoursCaption(naiveHours: 4.0, serverHours: null), isNull);
      expect(customHoursCaption(naiveHours: 4.0, serverHours: 4.0), isNull);
    });

    test('explains a break when Odoo counts fewer hours', () {
      expect(customHoursCaption(naiveHours: 4.0, serverHours: 3.0),
          'Breaks in your work schedule are not counted.');
    });

    test('flags a selection entirely outside the schedule', () {
      expect(customHoursCaption(naiveHours: 2.0, serverHours: 0.0),
          'The selected time is outside your work schedule.');
    });
  });
}
