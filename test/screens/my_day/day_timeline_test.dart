import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/day_timeline.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';

import '../../fixtures/my_day_fixture.dart';

Widget _host(MyDay day) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: DayTimeline(day: day))),
    );

Map<String, dynamic> _p(String kind, String at) =>
    {'kind': kind, 'at': at, 'source': 'kiosk', 'place': 'Front desk'};

// Fixture shift: 01:00–10:00 UTC, lunch 05:00–06:00 UTC.
final _onTime = [
  _p('check_in', '2026-10-05 01:02:00'),
  _p('break_start', '2026-10-05 03:30:00'),
  _p('break_end', '2026-10-05 03:45:00'),
];

void main() {
  test('on time: anchors, punches, planned lunch, rail segments', () {
    final ev = buildTimeline(sampleMyDay(punches: _onTime));
    expect(ev.map((e) => e.title),
        ['Shift starts', 'Check in', 'Break start', 'Break end', 'Lunch', 'Shift ends']);
    expect(ev[0].kind, TimelineKind.anchor);
    expect(ev[0].sub, '08:00 – 12:00 · 13:00 – 17:00');
    expect(ev[1].badge, 'On time');
    expect(ev[1].rail, RailStyle.solid);
    expect(ev[1].railColor, MyDayColors.work.dot);
    expect(ev[2].rail, RailStyle.dashed);
    expect(ev[2].railColor, MyDayColors.brk.dot);
    expect(ev[3].current, isTrue);
    expect(ev[3].rail, RailStyle.dotted); // the open day after the last punch
    expect(ev[4].kind, TimelineKind.lunch);
    expect(ev[4].sub, '12:00 – 13:00 · from your work schedule');
    expect(ev[5].rail, RailStyle.none);
  });

  test('late check-in: amber tone, badge, amber dashed rail under the start', () {
    final ev = buildTimeline(sampleMyDay(
        lateMinutes: 17, punches: [_p('check_in', '2026-10-05 01:17:00')]));
    expect(ev[0].rail, RailStyle.dashed);
    expect(ev[0].railColor, MyDayColors.late.dot);
    expect(ev[1].tone, MyDayColors.late);
    expect(ev[1].badge, '17 min late');
  });

  test('overtime and early badges on the last check-out', () {
    final ot = buildTimeline(sampleMyDay(state: 'checked_out', overtimeMinutes: 42, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:42:00'),
    ]));
    expect(ot.last.title, 'Check out');
    expect(ot.last.badge, '42 min overtime');
    expect(ot[ot.length - 2].title, 'Shift ends');
    expect(ot[ot.length - 2].rail, RailStyle.solid);
    expect(ot[ot.length - 2].railColor, MyDayColors.overtime.dot);

    final early = buildTimeline(sampleMyDay(state: 'checked_out', earlyMinutes: 50, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 09:10:00'),
    ]));
    final out = early.firstWhere((e) => e.title == 'Check out');
    expect(out.badge, '50 min early');
    expect(out.rail, RailStyle.dashed);
    expect(out.railColor, MyDayColors.late.dot);
    expect(early.last.sub, 'Coming back? This counts as a break.');
  });

  test('missing: red start, Now row, lunch, end', () {
    final ev = buildTimeline(sampleMyDay(state: 'not_in', missing: true, punches: []));
    expect(ev.map((e) => e.title), ['Shift starts', 'Now', 'Lunch', 'Shift ends']);
    expect(ev[0].badge, 'Missing');
    expect(ev[0].rail, RailStyle.dashed);
    expect(ev[0].railColor, MyDayColors.missing.dot);
    expect(ev[1].kind, TimelineKind.now);
    expect(ev[1].sub, 'If you are at work, check in at the kiosk');
  });

  test('planned lunch hides when a punched break overlaps it; stays for break-exempt', () {
    final punchedLunch = [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('break_start', '2026-10-05 05:05:00'),
      _p('break_end', '2026-10-05 05:50:00'),
    ];
    expect(buildTimeline(sampleMyDay(punches: punchedLunch)).any((e) => e.kind == TimelineKind.lunch),
        isFalse);
    final done = sampleMyDay(state: 'checked_out', punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]);
    expect(buildTimeline(done).any((e) => e.kind == TimelineKind.lunch), isFalse);
    final exempt = sampleMyDay(state: 'checked_out', breakExempt: true, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]);
    expect(buildTimeline(exempt).any((e) => e.kind == TimelineKind.lunch), isTrue);
  });

  test('no shift and no punches: nothing', () {
    expect(buildTimeline(sampleMyDay(withShift: false, state: 'not_in', punches: [])), isEmpty);
  });

  testWidgets('renders rows with keys and the empty text', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(punches: _onTime)));
    expect(find.byKey(const ValueKey('timeline-0-anchor')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-1-punch')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-4-lunch')), findsOneWidget);
    expect(find.text('On time'), findsOneWidget);
    expect(find.text('Front desk'), findsNWidgets(3));
    await tester.pumpWidget(_host(sampleMyDay(withShift: false, state: 'not_in', punches: [])));
    expect(find.text(DayTimeline.emptyText), findsOneWidget);
  });
}
