import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';
import 'package:omni_hr/screens/home/my_day/status_tile.dart';
import 'package:omni_hr/models/my_day.dart';

import '../../fixtures/my_day_fixture.dart';

final _now = DateTime.utc(2026, 10, 5, 4, 24);

Widget _host(MyDay day) =>
    MaterialApp(home: Scaffold(body: StatusTile(day: day, now: _now)));

Color _fill(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(const ValueKey('status-tile')));
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('checked in: title, hours, shift, kiosk button', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay()));
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('3h 12m'), findsOneWidget);
    expect(find.text('Worked'), findsOneWidget);
    expect(find.text('08:00 – 17:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-kiosk-button')), findsOneWidget);
    expect(_fill(tester), MyDayColors.work.fill);
  });

  testWidgets('the tile takes the colour of the day', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(lateMinutes: 17)));
    expect(find.text('Checked in late'), findsOneWidget);
    expect(_fill(tester), MyDayColors.late.fill);
    await tester.pumpWidget(_host(sampleMyDay(state: 'not_in', missing: true, punches: [])));
    expect(find.text('No check-in'), findsOneWidget);
    expect(_fill(tester), MyDayColors.missing.fill);
    await tester.pumpWidget(_host(sampleMyDay(state: 'checked_out', overtimeMinutes: 42)));
    expect(find.text('Done for today'), findsOneWidget);
    expect(find.text('Overtime'), findsOneWidget);
    expect(find.text('42 min'), findsOneWidget);
    expect(_fill(tester), MyDayColors.overtime.fill);
  });

  testWidgets('left early shows the short figure', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(state: 'checked_out', earlyMinutes: 50)));
    expect(find.text('Left early'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('50 min'), findsOneWidget);
  });

  testWidgets('leave: days away and back on', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(withShift: false, state: 'not_in', punches: [],
        off: {'kind': 'leave', 'name': 'Annual leave', 'date_from': '2026-10-05',
              'date_to': '2026-10-06', 'back_on': '2026-10-08'})));
    expect(find.text('On leave'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('Back on'), findsOneWidget);
    expect(find.text('8 Oct'), findsOneWidget);
  });

  testWidgets('holiday and day off show the next shift', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(withShift: false, state: 'not_in', punches: [],
        off: {'kind': 'public_holiday', 'name': 'Deepavali'})));
    expect(find.text('Public holiday'), findsOneWidget);
    expect(find.text('Deepavali'), findsOneWidget);
    expect(find.text('Next shift'), findsOneWidget);
    expect(find.text('6 Oct'), findsOneWidget);
    expect(find.text('08:00 – 17:00'), findsOneWidget);
  });

  testWidgets('no kiosk button when not kiosk-only', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(kioskOnly: false)));
    expect(find.byKey(const ValueKey('status-kiosk-button')), findsNothing);
  });

  testWidgets('the kiosk button opens the sheet, OK closes it', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay()));
    await tester.tap(find.byKey(const ValueKey('status-kiosk-button')));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsNothing);
  });
}
