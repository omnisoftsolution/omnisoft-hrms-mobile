import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/datetime_utils.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/day_timeline.dart';

import '../../fixtures/my_day_fixture.dart';

Widget _host(MyDay day) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DayTimeline(day: day)),
      ),
    );

Map<String, dynamic> _punch(String kind, String at,
        {String source = 'kiosk', String place = 'Produksi Lt. 1'}) =>
    {'kind': kind, 'at': at, 'source': source, 'place': place};

Finder _row(int index, TimelineStatus status) =>
    find.byKey(ValueKey('timeline-$index-${status.name}'));

/// A night shift: an open check-in carried over from the previous day, and
/// today's shift (or none) starting well after it.
MyDay _carriedNightPunch({required bool withShift}) {
  final json = sampleMyDayJson();
  final today = Map<String, dynamic>.from(json['today'] as Map);
  today['state'] = 'checked_in';
  today['shift'] = withShift
      ? {
          'start': '2026-09-07 01:00:00',
          'end': '2026-09-07 10:00:00',
          'label': '08:00 – 17:00',
        }
      : null;
  today['punches'] = [_punch('check_in', '2026-09-06 15:00:00')];
  json['today'] = today;
  return MyDay.fromJson(json);
}

void main() {
  testWidgets('checked in: punch, shift start, shift end, ordered by time',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay()));
    // 00:54 UTC check-in sorts before the 01:00 UTC shift start.
    expect(
        find.descendant(
            of: _row(0, TimelineStatus.now), matching: find.text('Check in')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _row(1, TimelineStatus.done),
            matching: find.text('Shift starts')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _row(2, TimelineStatus.upcoming),
            matching: find.text('Shift ends')),
        findsOneWidget);
    expect(find.text('Produksi Lt. 1'), findsOneWidget);
    expect(find.text('08:00 – 17:00'), findsOneWidget);
    expect(find.text('Check out at the kiosk'), findsOneWidget);
    expect(
        find.text(DateTimeUtils.formatLocalTime('2026-10-05 00:54:00')),
        findsOneWidget);
  });

  testWidgets('not in yet: shift start is "now", shift end upcoming',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(state: 'not_in', punches: [])));
    expect(_row(0, TimelineStatus.now), findsOneWidget);
    expect(_row(1, TimelineStatus.upcoming), findsOneWidget);
    expect(find.text('Shift starts'), findsOneWidget);
    expect(find.text('Shift ends'), findsOneWidget);
  });

  testWidgets('break pair then checked out: all done, no shift end',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(state: 'checked_out', punches: [
      _punch('check_in', '2026-10-05 00:54:00'),
      _punch('break_start', '2026-10-05 05:02:00'),
      _punch('break_end', '2026-10-05 05:58:00'),
      _punch('check_out', '2026-10-05 10:06:00'),
    ])));
    for (final title in [
      'Check in',
      'Shift starts',
      'Break start',
      'Break end',
      'Check out',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Shift ends'), findsNothing);
    for (var i = 0; i < 5; i++) {
      expect(_row(i, TimelineStatus.done), findsOneWidget);
    }
  });

  testWidgets('on break: the last punch is "now"', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(state: 'on_break', punches: [
      _punch('check_in', '2026-10-05 01:10:00'),
      _punch('break_start', '2026-10-05 05:02:00'),
    ])));
    expect(
        find.descendant(
            of: _row(2, TimelineStatus.now),
            matching: find.text('Break start')),
        findsOneWidget);
    expect(_row(3, TimelineStatus.upcoming), findsOneWidget);
  });

  testWidgets('no shift, with punches: only the punches', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(
        state: 'checked_out',
        withShift: false,
        punches: [
          _punch('check_in', '2026-10-05 02:00:00'),
          _punch('check_out', '2026-10-05 04:00:00'),
        ])));
    expect(find.text('Shift starts'), findsNothing);
    expect(find.text('Shift ends'), findsNothing);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget);
  });

  testWidgets('no shift and no punches: the empty text', (tester) async {
    await tester.pumpWidget(
        _host(sampleMyDay(state: 'not_in', withShift: false, punches: [])));
    expect(find.text('No attendance recorded today.'), findsOneWidget);
  });

  testWidgets('a punch without a place shows where it came from',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(punches: [
      _punch('check_in', '2026-10-05 00:54:00', place: ''),
    ])));
    expect(find.text('Kiosk'), findsOneWidget);
  });

  testWidgets(
      'carried night-shift punch sorts before today\'s shift start and is "now"',
      (tester) async {
    await tester.pumpWidget(_host(_carriedNightPunch(withShift: true)));
    expect(
        find.descendant(
            of: _row(0, TimelineStatus.now), matching: find.text('Check in')),
        findsOneWidget);
    // A punch exists, so the shift start is done rather than "now".
    expect(
        find.descendant(
            of: _row(1, TimelineStatus.done),
            matching: find.text('Shift starts')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _row(2, TimelineStatus.upcoming),
            matching: find.text('Shift ends')),
        findsOneWidget);
    expect(find.text(DayTimeline.emptyText), findsNothing);
  });

  testWidgets('carried punch with no shift today: one "now" row, no empty text',
      (tester) async {
    await tester.pumpWidget(_host(_carriedNightPunch(withShift: false)));
    expect(
        find.descendant(
            of: _row(0, TimelineStatus.now), matching: find.text('Check in')),
        findsOneWidget);
    expect(find.text('Shift starts'), findsNothing);
    expect(find.text('Shift ends'), findsNothing);
    expect(find.text(DayTimeline.emptyText), findsNothing);
    expect(find.byKey(const ValueKey('timeline-1-done')), findsNothing);
  });
}
