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

// Fixed clocks so nothing depends on the wall clock: mid-morning of an
// open day, and after the shift end for a finished one.
final _open = DateTime.utc(2026, 10, 5, 4, 24);
final _done = DateTime.utc(2026, 10, 5, 11, 0);

void main() {
  test('on time: anchors, punches, planned lunch, rail segments', () {
    final ev = buildTimeline(sampleMyDay(punches: _onTime), now: _open);
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
        lateMinutes: 17, punches: [_p('check_in', '2026-10-05 01:17:00')]),
        now: _open);
    expect(ev[0].rail, RailStyle.dashed);
    expect(ev[0].railColor, MyDayColors.late.dot);
    expect(ev[1].tone, MyDayColors.late);
    expect(ev[1].badge, '17 min late');
  });

  test('overtime and early badges on the last check-out', () {
    final ot = buildTimeline(sampleMyDay(state: 'checked_out', overtimeMinutes: 42, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:42:00'),
    ]), now: _done);
    expect(ot.last.title, 'Check out');
    expect(ot.last.badge, '42 min overtime');
    expect(ot[ot.length - 2].title, 'Shift ends');
    expect(ot[ot.length - 2].rail, RailStyle.solid);
    expect(ot[ot.length - 2].railColor, MyDayColors.overtime.dot);

    final early = buildTimeline(sampleMyDay(state: 'checked_out', earlyMinutes: 50, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 09:10:00'),
    ]), now: _done);
    final out = early.firstWhere((e) => e.title == 'Check out');
    expect(out.badge, '50 min early');
    expect(out.rail, RailStyle.dashed);
    expect(out.railColor, MyDayColors.late.dot);
    expect(early.last.sub, 'Coming back? This counts as a break.');
  });

  test('missing: red start, Now row, lunch, end', () {
    final ev = buildTimeline(sampleMyDay(state: 'not_in', missing: true, punches: []), now: _open);
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
    expect(
        buildTimeline(sampleMyDay(punches: punchedLunch), now: _open)
            .any((e) => e.kind == TimelineKind.lunch),
        isFalse);
    final done = sampleMyDay(state: 'checked_out', punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]);
    expect(buildTimeline(done, now: _done).any((e) => e.kind == TimelineKind.lunch), isFalse);
    final exempt = sampleMyDay(state: 'checked_out', breakExempt: true, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]);
    expect(buildTimeline(exempt, now: _done).any((e) => e.kind == TimelineKind.lunch), isTrue);
  });

  test('finished ordinary day: the rail has no gap down to the last row', () {
    final ev = buildTimeline(sampleMyDay(state: 'checked_out', punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('break_start', '2026-10-05 05:05:00'),
      _p('break_end', '2026-10-05 05:50:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]), now: _done);
    expect(ev.map((e) => e.title),
        ['Shift starts', 'Check in', 'Break start', 'Break end', 'Shift ends', 'Check out']);
    final ends = ev.firstWhere((e) => e.title == 'Shift ends');
    expect(ends.rail, RailStyle.solid);
    expect(ends.railColor, MyDayColors.work.dot);
    expect(ev.where((e) => e.rail == RailStyle.none).toList(), [ev.last]);
  });

  test('a second check-in carries no badge and the normal tone', () {
    final ev = buildTimeline(sampleMyDay(lateMinutes: 17, punches: [
      _p('check_in', '2026-10-05 01:17:00'),
      _p('check_out', '2026-10-05 04:00:00'),
      _p('check_in', '2026-10-05 06:00:00'),
    ]), now: _open);
    final ins = ev.where((e) => e.title == 'Check in').toList();
    expect(ins.length, 2);
    expect(ins[0].badge, '17 min late');
    expect(ins[1].badge, '');
    expect(ins[1].tone, MyDayColors.work);
  });

  test('open break shows how long it has run', () {
    final day = sampleMyDay(state: 'on_break', punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('break_start', '2026-10-05 03:30:00'),
    ]);
    final ev = buildTimeline(day, now: DateTime.utc(2026, 10, 5, 3, 42));
    expect(ev.firstWhere((e) => e.title == 'Break start').badge, '12 min so far');
    // A clock before the punch never shows a negative count.
    final early = buildTimeline(day, now: DateTime.utc(2026, 10, 5, 3, 0));
    expect(early.firstWhere((e) => e.title == 'Break start').badge, '0 min so far');
  });

  test('an open break that began inside the lunch window hides the planned lunch', () {
    final ev = buildTimeline(
        sampleMyDay(state: 'on_break', punches: [
          _p('check_in', '2026-10-05 01:02:00'),
          _p('break_start', '2026-10-05 05:10:00'),
        ]),
        now: DateTime.utc(2026, 10, 5, 5, 20));
    expect(ev.any((e) => e.kind == TimelineKind.lunch), isFalse);
  });

  test('break-exempt finished day keeps the lunch row inside a solid teal rail', () {
    final ev = buildTimeline(sampleMyDay(state: 'checked_out', breakExempt: true, punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 10:02:00'),
    ]), now: _done);
    final lunch = ev.firstWhere((e) => e.kind == TimelineKind.lunch);
    expect(lunch.rail, RailStyle.solid);
    expect(lunch.railColor, MyDayColors.work.dot);
  });

  test('check-out inside the grace window: dotted grey before Shift ends', () {
    final ev = buildTimeline(sampleMyDay(state: 'checked_out', punches: [
      _p('check_in', '2026-10-05 01:02:00'),
      _p('check_out', '2026-10-05 09:55:00'),
    ]), now: _done);
    expect(ev.map((e) => e.title),
        ['Shift starts', 'Check in', 'Check out', 'Shift ends']);
    final out = ev.firstWhere((e) => e.title == 'Check out');
    expect(out.rail, RailStyle.dotted);
    expect(out.railColor, MyDayColors.waiting.dot);
    expect(ev.last.rail, RailStyle.none);
  });

  test('Shift ends is passed once the clock reaches it, but an open day still says check out', () {
    final open = sampleMyDay(punches: [_p('check_in', '2026-10-05 01:02:00')]);
    final before = buildTimeline(open, now: DateTime.utc(2026, 10, 5, 9, 59)).last;
    final after = buildTimeline(open, now: DateTime.utc(2026, 10, 5, 10, 1)).last;
    expect(before.upcoming, isTrue);
    expect(after.upcoming, isFalse);
    expect(after.sub, 'Check out at the kiosk');
    expect(after.tone, MyDayColors.work);
  });

  test('a check-out exactly at the shift end sorts after the Shift ends anchor, no rail gap', () {
    final ev = buildTimeline(
        sampleMyDay(state: 'checked_out', overtimeMinutes: 0, punches: [
          _p('check_in', '2026-10-05 01:02:00'),
          _p('check_out', '2026-10-05 10:00:00'),
        ]),
        now: _done);
    expect(ev.map((e) => e.title), ['Shift starts', 'Check in', 'Shift ends', 'Check out']);
    final ends = ev[ev.length - 2];
    expect(ends.rail, RailStyle.solid);
    expect(ends.railColor, MyDayColors.work.dot);
    expect(ev.last.rail, RailStyle.none);
    expect(ev.where((e) => e.rail == RailStyle.none).toList(), [ev.last]);
  });

  test('night shift: a carried punch from the day before sorts first and keeps a dotted rail', () {
    final ev = buildTimeline(
        sampleMyDay(punches: [_p('check_in', '2026-10-04 15:00:00')]),
        now: _open);
    expect(ev.first.title, 'Check in');
    expect(ev[1].title, 'Shift starts');
    expect(ev.first.current, isTrue);
    expect(ev.every((e) => e.rail == RailStyle.dotted || e.rail == RailStyle.none), isTrue);
    expect(ev.last.rail, RailStyle.none);
    expect(ev.take(ev.length - 1).every((e) => e.rail == RailStyle.dotted), isTrue);
  });

  test('a carried punch still yields rows when there is no shift', () {
    final ev = buildTimeline(
        sampleMyDay(withShift: false, punches: [_p('check_in', '2026-10-04 15:00:00')]),
        now: _open);
    expect(ev, isNotEmpty);
    expect(ev.first.title, 'Check in');
    expect(ev.any((e) => e.kind == TimelineKind.anchor), isFalse);
  });

  test('no shift but punches present: punch rows only, no anchors', () {
    final ev = buildTimeline(
        sampleMyDay(withShift: false, state: 'checked_out', punches: [
          _p('check_in', '2026-10-05 01:02:00'),
          _p('check_out', '2026-10-05 09:00:00'),
        ]),
        now: _done);
    expect(ev.map((e) => e.title), ['Check in', 'Check out']);
    expect(ev.any((e) => e.kind == TimelineKind.anchor), isFalse);
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
