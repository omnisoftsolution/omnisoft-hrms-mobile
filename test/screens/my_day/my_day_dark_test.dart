import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/day_sheet.dart';
import 'package:omni_hr/screens/home/my_day/day_timeline.dart';
import 'package:omni_hr/screens/home/my_day/my_day_display.dart';
import 'package:omni_hr/screens/home/my_day/status_tile.dart';
import 'package:omni_hr/screens/home/my_day/week_strip.dart';
import 'package:omni_hr/widgets/big_check_button.dart';

import '../../fixtures/my_day_fixture.dart';

/// Dark mode M2: My day and the check-in circle paint from the theme.
final _now = DateTime.utc(2026, 10, 5, 4, 24);
final _dark = OmniColors.dark;
const _darkDay = MyDayPalette.dark;

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: ThemeMode.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('pure helpers take the palette', () {
    test('toneOf picks from the given palette', () {
      expect(toneOf(MyDayDisplay.late, _darkDay), same(_darkDay.late));
      expect(toneOf(MyDayDisplay.late), same(MyDayPalette.light.late));
    });

    test('buildTimeline: dark tones and dark rails', () {
      final ev = buildTimeline(sampleMyDay(), now: _now, palette: _darkDay);
      final darkTones = _darkDay.all.toSet();
      for (final e in ev) {
        expect(darkTones.contains(e.tone), isTrue, reason: e.title);
      }
      final darkRails = {
        for (final t in _darkDay.all) t.dot,
        Colors.transparent,
      };
      for (final e in ev) {
        expect(darkRails.contains(e.railColor), isTrue, reason: e.title);
      }
    });

    test('daySummaryOf uses the palette', () {
      const absent = MyDayWeekDay(date: '2026-10-07', kind: 'absent');
      expect(
        daySummaryOf(absent, palette: _darkDay).tone,
        same(_darkDay.missing),
      );
      expect(daySummaryOf(absent).tone, same(MyDayPalette.light.missing));
    });
  });

  testWidgets('status tile: dark fill, no shadow', (tester) async {
    await tester.pumpWidget(_app(StatusTile(day: sampleMyDay(), now: _now)));
    final box = tester.widget<Container>(
      find.byKey(const ValueKey('status-tile')),
    );
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, _darkDay.work.fill);
    expect(deco.boxShadow, isNull);
  });

  testWidgets('week strip: dark tints', (tester) async {
    await tester.pumpWidget(
      _app(
        WeekStrip(
          day: sampleMyDay(
            week: [
              {'date': '2026-10-05', 'kind': 'worked', 'verdict': 'ok'},
              {'date': '2026-10-06', 'kind': 'today'},
              {'date': '2026-10-07', 'kind': 'absent'},
              {'date': '2026-10-10', 'kind': 'scheduled'},
            ],
          ),
        ),
      ),
    );
    Color fill(String date) => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byKey(ValueKey('week-$date')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    expect(fill('2026-10-05'), _darkDay.work.tint);
    expect(fill('2026-10-07'), _darkDay.missing.tint);
    expect(fill('2026-10-10'), _dark.card);
  });

  testWidgets('timeline: unfilled circles are card, filled icons dark', (
    tester,
  ) async {
    await tester.pumpWidget(_app(DayTimeline(day: sampleMyDay(), now: _now)));
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .toList();
    expect(circles, isNotEmpty);
    expect(circles.any((d) => d.color == _dark.card), isTrue);
    expect(circles.any((d) => d.color == Colors.white), isFalse);
    final icons = tester
        .widgetList<Icon>(find.byType(Icon))
        .map((i) => i.color);
    expect(icons.contains(Colors.white), isFalse);
  });

  testWidgets('big check button: deep teal in, blue out, card ring', (
    tester,
  ) async {
    Material circle() => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BigCheckButton),
            matching: find.byType(Material),
          )
          .first,
    );
    await tester.pumpWidget(
      _app(
        const BigCheckButton(
          checkedIn: false,
          state: CheckButtonState.ready,
          onPressed: null,
        ),
      ),
    );
    expect(circle().color, _dark.checkInFill);
    expect(((circle().shape! as CircleBorder).side).color, _dark.card);
    await tester.pumpWidget(
      _app(
        const BigCheckButton(
          checkedIn: true,
          state: CheckButtonState.ready,
          onPressed: null,
        ),
      ),
    );
    expect(circle().color, _dark.segmentOn);
  });
}
