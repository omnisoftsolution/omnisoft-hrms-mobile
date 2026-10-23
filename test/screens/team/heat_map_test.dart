import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/team/heat_map.dart';
import 'package:omni_hr/screens/team/team_colors.dart';

import 'team_fixture.dart';

Widget _host(
  TeamOutlook o, {
  DateTime? selected,
  ValueChanged<DateTime>? onSelect,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TeamHeatMap(
        outlook: o,
        selected: selected,
        onSelect: onSelect ?? (_) {},
      ),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _cell(String iso) => find.byKey(ValueKey('heat-cell-$iso'));

Material _material(WidgetTester tester, String iso) =>
    tester.widget<Material>(_cell(iso));

BorderSide _side(WidgetTester tester, String iso) =>
    (_material(tester, iso).shape! as RoundedRectangleBorder).side;

Text _dayText(WidgetTester tester, String iso, String day) => tester.widget<Text>(
  find.descendant(of: _cell(iso), matching: find.text(day)),
);

final _counts = outlook(
  off: const {
    '2026-10-22': 2,
    '2026-10-26': 1,
    '2026-10-27': 3,
    '2026-10-28': 5,
    '2026-11-10': 1,
  },
  holidays: const {
    '2026-11-09': {'name': 'Deepavali (observed)', 'everyone': true},
    '2026-11-10': {'name': 'Hari Raya Haji', 'everyone': false},
  },
);

void main() {
  testWidgets('one card per month in range, with the weekday header', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(outlook()));
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('December 2026'), findsNothing);
    expect(find.text('M'), findsNWidgets(2));
    expect(find.text('T'), findsNWidgets(4));
  });

  testWidgets('90 days reach into the next year', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(outlook(days: 90)));
    expect(find.text('December 2026'), findsOneWidget);
    expect(find.text('January 2027'), findsOneWidget);
  });

  testWidgets('the month starts under its weekday (leading blanks)', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(outlook()));
    // 1 Oct 2026 is a Thursday, like 22 Oct; 5 Oct is the Monday after.
    final oct1 = tester.getCenter(_cell('2026-10-01')).dx;
    expect(oct1, tester.getCenter(_cell('2026-10-22')).dx);
    expect(tester.getCenter(_cell('2026-10-05')).dx, lessThan(oct1));
  });

  testWidgets('the legend explains the shades', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(outlook()));
    expect(find.text('People off:'), findsOneWidget);
    expect(find.text('3+'), findsOneWidget);
    expect(find.text('PH = public holiday'), findsOneWidget);
    expect(find.text('Tap a day to see who'), findsOneWidget);
  });

  testWidgets('cells are shaded by the number of people off', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(_counts));
    expect(_material(tester, '2026-10-23').color, TeamColors.cell0);
    expect(_material(tester, '2026-10-26').color, TeamColors.c1);
    expect(_material(tester, '2026-10-22').color, TeamColors.c2);
    expect(_material(tester, '2026-10-27').color, TeamColors.c3);
    expect(_material(tester, '2026-10-28').color, TeamColors.c3);
    // Sub-labels.
    expect(
      find.descendant(of: _cell('2026-10-27'), matching: find.text('3 off')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _cell('2026-10-23'), matching: find.textContaining('off')),
      findsNothing,
    );
    // White text on the darkest shade only.
    expect(_dayText(tester, '2026-10-27', '27').style!.color, TeamColors.onC3);
    expect(_dayText(tester, '2026-10-26', '26').style!.color, AppTheme.onSurface);
  });

  testWidgets('a non-working day is pale', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(_counts));
    expect(_material(tester, '2026-10-24').color, TeamColors.cellOff);
    expect(_material(tester, '2026-10-25').color, TeamColors.cellOff);
  });

  testWidgets('a holiday for everyone is grey "PH"; for some, a red dot', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(_counts));
    expect(_material(tester, '2026-11-09').color, TeamColors.holCell);
    expect(
      find.descendant(of: _cell('2026-11-09'), matching: find.text('PH')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('heat-hol-dot-2026-11-09')), findsNothing);
    expect(_material(tester, '2026-11-10').color, TeamColors.c1);
    expect(find.byKey(const ValueKey('heat-hol-dot-2026-11-10')), findsOneWidget);
  });

  testWidgets('today has a thin accent ring, the selected day a thick one', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(_counts));
    expect(_side(tester, '2026-10-22').width, 1.5);
    expect(_side(tester, '2026-10-22').color, TeamColors.accent);
    expect(_side(tester, '2026-10-26').style, BorderStyle.none);

    await tester.pumpWidget(_host(_counts, selected: DateTime(2026, 10, 26)));
    expect(_side(tester, '2026-10-26').width, 2);
    expect(_side(tester, '2026-10-22').width, 1.5);

    await tester.pumpWidget(_host(_counts, selected: DateTime(2026, 10, 22)));
    expect(_side(tester, '2026-10-22').width, 2);
  });

  testWidgets('tapping a day in range selects it', (tester) async {
    _tall(tester);
    final picked = <DateTime>[];
    await tester.pumpWidget(_host(_counts, onSelect: picked.add));
    await tester.tap(find.byKey(const ValueKey('heat-tap-2026-10-27')));
    expect(picked, [DateTime(2026, 10, 27)]);
  });

  testWidgets('days outside the range are dimmed and cannot be tapped', (
    tester,
  ) async {
    _tall(tester);
    final picked = <DateTime>[];
    await tester.pumpWidget(_host(_counts, onSelect: picked.add));
    // 21 Oct is before today, 21 Nov after the 30-day range.
    for (final iso in ['2026-10-21', '2026-11-21']) {
      expect(find.byKey(ValueKey('heat-tap-$iso')), findsNothing);
      expect(
        find.ancestor(of: _cell(iso), matching: find.byType(Opacity)),
        findsWidgets,
      );
      await tester.tap(_cell(iso), warnIfMissed: false);
    }
    expect(picked, isEmpty);
  });

  testWidgets('each day reads its date, count and holiday', (tester) async {
    _tall(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_counts));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('heat-tap-2026-10-27'))),
      isSemantics(
        isButton: true,
        label: 'Tue 27 Oct, 3 off',
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('heat-tap-2026-11-09'))),
      isSemantics(
        isButton: true,
        label: 'Mon 9 Nov, 0 off, public holiday Deepavali (observed)',
      ),
    );
    handle.dispose();
  });
}
