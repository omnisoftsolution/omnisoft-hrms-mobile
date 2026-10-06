import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';
import 'package:omni_hr/screens/home/my_day/week_strip.dart';

import '../../fixtures/my_day_fixture.dart';

Widget _host(MyDay day) => MaterialApp(
  home: Scaffold(body: WeekStrip(day: day)),
);

Color _cellFill(WidgetTester tester, String date) {
  return _cellMaterial(tester, date).color ?? Colors.transparent;
}

Material _cellMaterial(WidgetTester tester, String date) =>
    tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey('week-$date')),
            matching: find.byType(Material),
          )
          .first,
    );

List<Map<String, dynamic>> _week() => [
  {'date': '2026-10-05', 'kind': 'worked', 'verdict': 'ok'},
  {'date': '2026-10-06', 'kind': 'today'},
  {'date': '2026-10-07', 'kind': 'absent'},
  {'date': '2026-10-08', 'kind': 'public_holiday', 'name': 'Deepavali'},
  {'date': '2026-10-09', 'kind': 'leave', 'name': 'Annual leave'},
  {'date': '2026-10-10', 'kind': 'scheduled'},
  {'date': '2026-10-11', 'kind': 'off'},
];

void main() {
  testWidgets('seven cells, each kind tinted, no legend chips', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(week: _week())));
    for (final name in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(_cellFill(tester, '2026-10-05'), MyDayColors.work.tint);
    expect(
      _cellFill(tester, '2026-10-06'),
      MyDayColors.work.tint,
    ); // today, checked in
    expect(_cellFill(tester, '2026-10-07'), MyDayColors.missing.tint);
    expect(_cellFill(tester, '2026-10-08'), MyDayColors.holiday.tint);
    expect(_cellFill(tester, '2026-10-09'), MyDayColors.leave.tint);
    expect(_cellFill(tester, '2026-10-10'), Colors.white);
    expect(_cellFill(tester, '2026-10-11'), Colors.transparent);
    expect(find.text('Thu · Deepavali'), findsNothing);
    expect(find.text('Fri · Annual leave'), findsNothing);
    expect(find.text('2 days worked so far'), findsOneWidget);
  });

  testWidgets('a scheduled day has a visible edge', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(week: _week())));
    final shape =
        _cellMaterial(tester, '2026-10-10').shape! as RoundedRectangleBorder;
    expect(shape.side.color, AppTheme.outlineVariant);
    expect(shape.side.width, 1);
  });

  testWidgets('today takes the colour of the day', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(week: _week(), lateMinutes: 17)));
    expect(_cellFill(tester, '2026-10-06'), MyDayColors.late.tint);
  });

  testWidgets('a late past day keeps a teal cell with an amber dot', (
    tester,
  ) async {
    final week = _week();
    week[0] = {'date': '2026-10-05', 'kind': 'worked', 'verdict': 'late'};
    await tester.pumpWidget(_host(sampleMyDay(week: week)));
    expect(_cellFill(tester, '2026-10-05'), MyDayColors.work.tint);
    final dot = tester.widget<Container>(
      find.byKey(const ValueKey('week-dot-2026-10-05')),
    );
    expect((dot.decoration as BoxDecoration).color, MyDayColors.late.dot);
  });

  testWidgets('hidden on an older connector', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(week: [])));
    expect(find.text('This week'), findsNothing);
  });

  test('workedSoFar counts worked days plus today when in', () {
    expect(
      WeekStrip.workedSoFar(sampleMyDay(week: _week())),
      '2 days worked so far',
    );
    expect(
      WeekStrip.workedSoFar(
        sampleMyDay(week: _week(), state: 'not_in', punches: []),
      ),
      '1 day worked so far',
    );
  });

  testWidgets('tapping a past day opens the sheet above the body', (
    tester,
  ) async {
    await tester.pumpWidget(_host(sampleMyDay(week: _week())));
    await tester.tap(find.byKey(const ValueKey('week-tap-2026-10-08')));
    await tester.pumpAndSettle();
    expect(find.text('Thursday 8 October'), findsOneWidget);
    expect(find.text('Public holiday'), findsOneWidget);
    expect(find.text('Deepavali'), findsOneWidget);
    // Dismiss by tapping the barrier (above the sheet).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Thursday 8 October'), findsNothing);
  });

  testWidgets('tapping today does nothing', (tester) async {
    await tester.pumpWidget(_host(sampleMyDay(week: _week())));
    await tester.tap(find.byKey(const ValueKey('week-tap-2026-10-06')));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday 6 October'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('cells expose one clean semantics node each', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(sampleMyDay(week: _week())));
    final thu = tester.getSemantics(
      find.byKey(const ValueKey('week-tap-2026-10-08')),
    );
    expect(
      thu,
      matchesSemantics(
        isButton: true,
        label: 'Thu, public holiday, Deepavali',
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    final tue = tester.getSemantics(
      find.byKey(const ValueKey('week-tap-2026-10-06')),
    );
    expect(tue, matchesSemantics(isButton: false, label: 'Tue, today'));
    handle.dispose();
  });
}
