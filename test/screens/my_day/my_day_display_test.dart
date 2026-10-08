import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';
import 'package:omni_hr/screens/home/my_day/my_day_display.dart';

import '../../fixtures/my_day_fixture.dart';

void main() {
  // The fixture's shift is 01:00–10:00 UTC (08:00–17:00 Jakarta).
  final now = DateTime.utc(2026, 10, 5, 4, 24); // 11:24 local

  test('displayOf follows the spec order', () {
    expect(
      displayOf(
        sampleMyDay(
          off: {'kind': 'public_holiday', 'name': 'X'},
          withShift: false,
          punches: [],
        ),
      ),
      MyDayDisplay.holiday,
    );
    expect(
      displayOf(
        sampleMyDay(
          off: {'kind': 'leave', 'name': 'Annual'},
          withShift: false,
          punches: [],
        ),
      ),
      MyDayDisplay.leave,
    );
    expect(
      displayOf(
        sampleMyDay(
          off: {'kind': 'not_scheduled'},
          withShift: false,
          punches: [],
        ),
      ),
      MyDayDisplay.noShift,
    );
    expect(
      displayOf(sampleMyDay(state: 'not_in', missing: true, punches: [])),
      MyDayDisplay.missing,
    );
    expect(
      displayOf(sampleMyDay(state: 'not_in', punches: [])),
      MyDayDisplay.notIn,
    );
    expect(displayOf(sampleMyDay(lateMinutes: 17)), MyDayDisplay.late);
    expect(displayOf(sampleMyDay()), MyDayDisplay.checkedIn);
    expect(displayOf(sampleMyDay(state: 'on_break')), MyDayDisplay.onBreak);
    expect(
      displayOf(sampleMyDay(state: 'checked_out', earlyMinutes: 50)),
      MyDayDisplay.early,
    );
    expect(
      displayOf(sampleMyDay(state: 'checked_out', overtimeMinutes: 42)),
      MyDayDisplay.overtime,
    );
    expect(displayOf(sampleMyDay(state: 'checked_out')), MyDayDisplay.done);
  });

  test('an off day with punches shows the live state, not Day off', () {
    final at = {
      'kind': 'check_in',
      'at': '2026-10-05 01:02:00',
      'source': 'kiosk',
      'place': 'Front desk',
    };
    expect(
      displayOf(
        sampleMyDay(
          off: {'kind': 'public_holiday', 'name': 'Deepavali'},
          withShift: false,
          punches: [at],
        ),
      ),
      MyDayDisplay.checkedIn,
    );
    expect(
      displayOf(
        sampleMyDay(
          off: {'kind': 'leave', 'name': 'Annual leave'},
          withShift: false,
          state: 'checked_out',
          punches: [
            at,
            {...at, 'kind': 'check_out', 'at': '2026-10-05 09:00:00'},
          ],
        ),
      ),
      MyDayDisplay.done,
    );
  });

  test('a 2.51.0 body with no shift and no off reads as noShift', () {
    expect(
      displayOf(sampleMyDay(withShift: false, state: 'not_in', punches: [])),
      MyDayDisplay.noShift,
    );
  });

  test('tones', () {
    expect(toneOf(MyDayDisplay.checkedIn), MyDayColors.work);
    expect(toneOf(MyDayDisplay.late), MyDayColors.late);
    expect(toneOf(MyDayDisplay.early), MyDayColors.late);
    expect(toneOf(MyDayDisplay.onBreak), MyDayColors.brk);
    expect(toneOf(MyDayDisplay.leave), MyDayColors.leave);
    expect(toneOf(MyDayDisplay.overtime), MyDayColors.overtime);
    expect(toneOf(MyDayDisplay.missing), MyDayColors.missing);
    expect(toneOf(MyDayDisplay.notIn), MyDayColors.waiting);
    expect(toneOf(MyDayDisplay.noShift), MyDayColors.waiting);
    expect(toneOf(MyDayDisplay.holiday), MyDayColors.holiday);
    expect(MyDayColors.work.fill.toARGB32(), 0xFF006971);
    expect(MyDayColors.late.tint.toARGB32(), 0xFFFFE4A8);
  });

  test('titles and subtitles', () {
    expect(displayTitle(MyDayDisplay.late), 'Checked in late');
    expect(displayTitle(MyDayDisplay.early), 'Left early');
    expect(displayTitle(MyDayDisplay.overtime), 'Done for today');
    // The fixture punch is 00:54 UTC and formatLocalTime uses the device
    // timezone, so only the shape is checked.
    final since = displaySubtitle(
      sampleMyDay(),
      MyDayDisplay.checkedIn,
      now: now,
    );
    expect(since, startsWith('Since '));
    expect(since, endsWith(' · Produksi Lt. 1'));
    expect(
      displaySubtitle(
        sampleMyDay(lateMinutes: 17),
        MyDayDisplay.late,
        now: now,
      ),
      endsWith('· 17 minutes after the shift start'),
    );
    expect(
      displaySubtitle(
        sampleMyDay(state: 'not_in', punches: []),
        MyDayDisplay.notIn,
        now: DateTime.utc(2026, 10, 5, 0, 41),
      ),
      'Shift starts in 19 minutes',
    );
    expect(
      displaySubtitle(
        sampleMyDay(state: 'not_in', missing: true, punches: []),
        MyDayDisplay.missing,
        now: DateTime.utc(2026, 10, 5, 3, 15),
      ),
      'Shift started 2h 15m ago · nothing recorded',
    );
    expect(
      displaySubtitle(
        sampleMyDay(
          off: {
            'kind': 'leave',
            'name': 'Annual leave',
            'date_from': '2026-10-06',
            'date_to': '2026-10-07',
          },
          withShift: false,
        ),
        MyDayDisplay.leave,
        now: now,
      ),
      'Annual leave · 6 Oct – 7 Oct',
    );
    expect(
      displaySubtitle(
        sampleMyDay(
          off: {'kind': 'public_holiday', 'name': 'Deepavali'},
          withShift: false,
        ),
        MyDayDisplay.holiday,
        now: now,
      ),
      'Deepavali',
    );
    // A holiday with no name still says what it is.
    expect(
      displaySubtitle(
        sampleMyDay(off: {'kind': 'public_holiday'}, withShift: false),
        MyDayDisplay.holiday,
        now: now,
      ),
      'Public holiday',
    );
  });

  test('on break: how long it has run, in the shared minute format', () {
    // Break from 03:30 UTC; the label's clock part follows the device zone.
    final day = sampleMyDay(
      state: 'on_break',
      punches: [
        {
          'kind': 'break_start',
          'at': '2026-10-05 03:30:00',
          'source': 'kiosk',
          'place': '',
        },
      ],
    );
    expect(
      displaySubtitle(
        day,
        MyDayDisplay.onBreak,
        now: DateTime.utc(2026, 10, 5, 3, 55),
      ),
      endsWith(' · 25 min so far'),
    );
    expect(
      displaySubtitle(
        day,
        MyDayDisplay.onBreak,
        now: DateTime.utc(2026, 10, 5, 4, 35),
      ),
      endsWith(' · 1h 05m so far'),
    );
    // A clock before the punch never goes negative.
    expect(
      displaySubtitle(
        day,
        MyDayDisplay.onBreak,
        now: DateTime.utc(2026, 10, 5, 3, 0),
      ),
      endsWith(' · 0 min so far'),
    );
  });

  test('shortDate and dateRange', () {
    expect(shortDate('2026-10-06'), '6 Oct');
    expect(shortDate('not a date'), 'not a date');
    expect(dateRange('2026-10-06', '2026-10-07'), '6 Oct – 7 Oct');
    expect(dateRange('2026-10-06', '2026-10-06'), '6 Oct');
    expect(dateRange('2026-10-06', ''), '6 Oct');
  });

  test('formatHoursToday and minutesLabel', () {
    expect(formatHoursToday(3.2), '3h 12m');
    expect(minutesLabel(17), '17 min');
    expect(minutesLabel(45), '45 min');
    expect(minutesLabel(65), '1h 05m');
    expect(minutesLabel(60), '1h');
    expect(minutesLabel(120), '2h');
    expect(minutesLabel(389), '6h 29m');
    // The status tile's sentences spell short durations out.
    expect(minutesLabel(45, long: true), '45 minutes');
    expect(minutesLabel(1, long: true), '1 minute');
    expect(minutesLabel(389, long: true), '6h 29m');
    expect(minutesLabel(60, long: true), '1h');
    // A worked total keeps the "Hours today" shape.
    expect(workedLabel(240), '4h 00m');
    expect(workedLabel(483), '8h 03m');
    expect(workedLabel(45), '45 min');
  });

  test('long durations in the subtitle read in hours and minutes', () {
    String early(int m) =>
        displaySubtitle(sampleMyDay(earlyMinutes: m), MyDayDisplay.early);
    String overtime(int m) =>
        displaySubtitle(sampleMyDay(overtimeMinutes: m), MyDayDisplay.overtime);
    String late(int m) =>
        displaySubtitle(sampleMyDay(lateMinutes: m), MyDayDisplay.late);
    expect(early(389), endsWith(' · 6h 29m before the shift end'));
    expect(early(45), endsWith(' · 45 minutes before the shift end'));
    expect(early(60), endsWith(' · 1h before the shift end'));
    expect(overtime(120), endsWith(' · 2h overtime'));
    expect(overtime(42), endsWith(' · 42 minutes overtime'));
    expect(late(75), endsWith(' · 1h 15m after the shift start'));
    expect(late(17), endsWith(' · 17 minutes after the shift start'));
    String startsIn(DateTime now) => displaySubtitle(
      sampleMyDay(state: 'not_in', punches: []),
      MyDayDisplay.notIn,
      now: now,
    );
    // The fixture shift starts 01:00 UTC.
    expect(
      startsIn(DateTime.utc(2026, 10, 4, 23, 30)),
      'Shift starts in 1h 30m',
    );
    expect(
      startsIn(DateTime.utc(2026, 10, 5, 0, 59)),
      'Shift starts in 1 minute',
    );
  });

  test('helloTitle greets by first name, falling back to the login', () {
    expect(helloTitle('Ethan Smith', 'Ethan S', 'ethan@x.co'), 'Hello, Ethan');
    expect(helloTitle('', 'Chai Yeo', 'chai'), 'Hello, Chai');
    expect(helloTitle('  ', '', 'chai@x.co'), 'Hello, chai@x.co');
    expect(helloTitle('', '', ''), 'Hello');
  });
}
