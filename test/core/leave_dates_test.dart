import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/leave_dates.dart';

void main() {
  final mon26 = DateTime(2026, 10, 26);

  test('one day, a range, specific hours, half a day', () {
    expect(leaveDatesLabel(mon26, mon26), 'Mon 26 Oct');
    expect(leaveDatesLabel(mon26, null), 'Mon 26 Oct');
    expect(
      leaveDatesLabel(DateTime(2026, 10, 22), DateTime(2026, 10, 23)),
      'Thu 22 Oct – Fri 23 Oct',
    );
    expect(
      leaveDatesLabel(
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 3),
        hourFrom: 14,
        hourTo: 17,
      ),
      'Tue 3 Nov, 14:00 – 17:00',
    );
    expect(
      leaveDatesLabel(
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 2),
        halfDayPeriod: 'pm',
      ),
      'Mon 2 Nov (afternoon)',
    );
    expect(
      leaveDatesLabel(mon26, mon26, halfDayPeriod: 'am'),
      'Mon 26 Oct (morning)',
    );
  });

  test('a range ignores hours and half-day periods', () {
    expect(
      leaveDatesLabel(
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 23),
        hourFrom: 9,
        hourTo: 12,
        halfDayPeriod: 'am',
      ),
      'Thu 22 Oct – Fri 23 Oct',
    );
  });

  test('no start date is empty; inverted hours read as a plain day', () {
    expect(leaveDatesLabel(null, mon26), '');
    expect(leaveDatesLabel(mon26, mon26, hourFrom: 17, hourTo: 9), 'Mon 26 Oct');
  });

  test('hourMinute rounds to the minute', () {
    expect(hourMinute(13.5), '13:30');
    expect(hourMinute(9), '09:00');
    expect(hourMinute(16.9999), '17:00');
  });
}
