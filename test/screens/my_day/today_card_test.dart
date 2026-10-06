import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/today_card.dart';

import '../../fixtures/my_day_fixture.dart';

Widget _host(MyDay day,
        {TodayCardMode mode = TodayCardMode.readOnly, Widget? action}) =>
    MaterialApp(
      home: Scaffold(body: TodayCard(day: day, mode: mode, action: action)),
    );

void main() {
  test('formatHoursToday', () {
    expect(formatHoursToday(0), '0h 00m');
    expect(formatHoursToday(3.2), '3h 12m');
    expect(formatHoursToday(8.27), '8h 16m');
  });

  test('todayStateLabel', () {
    expect(todayStateLabel('not_in'), 'Not checked in');
    expect(todayStateLabel('checked_in'), 'Checked in');
    expect(todayStateLabel('on_break'), 'On break');
    expect(todayStateLabel('checked_out'), 'Checked out');
    expect(todayStateLabel('future_state'), 'future_state');
  });

  testWidgets('read-only card: chip, hours, shift and the kiosk line',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay()));
    expect(find.text('Today · 08:00 – 17:00'), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('3h 12m'), findsOneWidget);
    expect(find.text('Hours today'), findsOneWidget);
    expect(find.text('Attendance is recorded at the kiosk.'), findsOneWidget);
  });

  testWidgets('each state has its chip text', (tester) async {
    for (final entry in {
      'not_in': 'Not checked in',
      'on_break': 'On break',
      'checked_out': 'Checked out',
    }.entries) {
      await tester.pumpWidget(_host(sampleMyDay(state: entry.key)));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('today-chip')),
              matching: find.text(entry.value)),
          findsOneWidget);
    }
  });

  testWidgets('no shift: the header is just "Today"', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(withShift: false)));
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('tapping the kiosk line explains why, OK closes the sheet',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay()));
    await tester.tap(find.byKey(const ValueKey('today-kiosk-line')));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsOneWidget);
    expect(find.textContaining('ask HR to change it'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsNothing);
  });

  testWidgets('action mode shows the action slot instead of the kiosk line',
      (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(),
        mode: TodayCardMode.action, action: const Text('ACTION SLOT')));
    expect(find.text('ACTION SLOT'), findsOneWidget);
    expect(find.text('Attendance is recorded at the kiosk.'), findsNothing);
    expect(find.text('Checked in'), findsOneWidget);
  });
}
