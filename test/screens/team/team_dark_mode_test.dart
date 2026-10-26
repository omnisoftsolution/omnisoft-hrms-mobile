import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/overview_tiles.dart';
import 'package:omni_hr/screens/team/heat_map.dart';
import 'package:omni_hr/screens/team/team_colors.dart';
import 'package:omni_hr/screens/team/team_day_detail.dart';
import 'package:omni_hr/screens/team/team_widgets.dart';

import '../../core/omni_colors_test.dart' show contrast;
import 'team_fixture.dart';

/// Dark mode: the Team screens read [TeamColors.of] and `context.omni`.
Widget _app(Widget child, {bool dark = true}) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _cell(String iso) => find.byKey(ValueKey('heat-cell-$iso'));

Color? _fill(WidgetTester tester, String iso) =>
    tester.widget<Material>(_cell(iso)).color;

Color? _digit(WidgetTester tester, String iso, String day) => tester
    .widget<Text>(find.descendant(of: _cell(iso), matching: find.text(day)))
    .style!
    .color;

/// Every day a workday, so Sundays get a shade: Sun 1 Nov = 1 off (c1),
/// Sun 8 Nov = 2 (c2), Sun 15 Nov = 3 (c3); Mon 9 Nov is a PH for all.
TeamOutlook _sundays() {
  final body = outlookJson(
    off: const {'2026-11-01': 1, '2026-11-08': 2, '2026-11-15': 3},
    holidays: const {
      '2026-11-09': {'name': 'Deepavali', 'everyone': true},
    },
  );
  for (final d in body['days'] as List) {
    (d as Map)['workday'] = true;
  }
  return TeamOutlook.fromJson(body);
}

void main() {
  const d = TeamColors.dark;
  const l = TeamColors.light;

  group('contrast (dark heat map)', () {
    test('digits on every shade pass 4.5', () {
      final text = OmniColors.dark.text;
      expect(contrast(text, d.cell0), greaterThanOrEqualTo(4.5));
      expect(contrast(d.onC1, d.c1), greaterThanOrEqualTo(4.5));
      expect(contrast(d.onC2, d.c2), greaterThanOrEqualTo(4.5));
      expect(contrast(d.onC3, d.c3), greaterThanOrEqualTo(4.5));
    });

    test('PH on the holiday cell and Sunday on cell0 / c1 pass 4.5', () {
      expect(contrast(d.holText, d.holCell), greaterThanOrEqualTo(4.5));
      expect(contrast(d.sunday, d.cell0), greaterThanOrEqualTo(4.5));
      expect(contrast(d.sunday, d.c1), greaterThanOrEqualTo(4.5));
    });

    test('a non-working day digit on the dark card passes 4.5', () {
      expect(
        contrast(d.offDigit, OmniColors.dark.card),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('palette', () {
    test('dark buckets: light fill, tint / onTint / dot of the dark My day '
        'tone of the same kind', () {
      for (final key in OverviewCounts.buckets) {
        final dark = d.bucket(key);
        final mine = MyDayPalette.dark.of(dark.kind);
        expect(dark.kind, l.bucket(key).kind, reason: key);
        expect(dark.fill, l.bucket(key).fill, reason: key);
        expect(dark.tint, mine.tint, reason: key);
        expect(dark.onTint, mine.onTint, reason: key);
        expect(dark.dot, mine.dot, reason: key);
      }
    });

    test('the dark tiles are the brand fill and the selected segment', () {
      expect(d.overviewTile, OmniColors.dark.brandFill);
      expect(d.overviewTileYesterday, OmniColors.dark.segmentOn);
      expect(l.overviewTile, AppTheme.primary);
      expect(l.overviewTileYesterday, AppTheme.secondary);
    });

    test('light keeps the 1.34.1 values', () {
      expect(l.cell0, const Color(0xFFF5F7F9));
      expect(l.c3, const Color(0xFF395F97));
      expect(l.onC1, AppTheme.onSurface);
      expect(l.onC2, AppTheme.onSurface);
      expect(l.sunday, AppTheme.error);
      expect(l.chipBorder, AppTheme.outlineVariant);
      expect(l.accent, AppTheme.primary);
    });

    testWidgets('TeamColors.of follows the theme', (tester) async {
      late TeamColors picked;
      Widget probe() => Builder(
        builder: (context) {
          picked = TeamColors.of(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(_app(probe()));
      expect(picked, same(d));
      await tester.pumpWidget(_app(probe(), dark: false));
      await tester.pumpAndSettle();
      expect(picked, same(l));
    });
  });

  testWidgets('heat map in dark: card, shades and digits', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        TeamHeatMap(outlook: _sundays(), selected: null, onSelect: (_) {}),
      ),
    );
    final card = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((b) => b.borderRadius == BorderRadius.circular(24));
    expect(card.color, OmniColors.dark.card);
    expect(card.boxShadow, isEmpty);

    // A working day nobody is off.
    expect(_fill(tester, '2026-10-23'), d.cell0);
    expect(_digit(tester, '2026-10-23', '23'), OmniColors.dark.text);
    // Sunday on c1: Sunday red; on c2 / c3 the shade's own digit.
    expect(_fill(tester, '2026-11-01'), d.c1);
    expect(_digit(tester, '2026-11-01', '1'), d.sunday);
    expect(_fill(tester, '2026-11-08'), d.c2);
    expect(_digit(tester, '2026-11-08', '8'), const Color(0xFFFFFFFF));
    expect(_fill(tester, '2026-11-15'), d.c3);
    expect(_digit(tester, '2026-11-15', '15'), d.onC3);
    // The sub line on c2 is white too.
    final sub = tester.widget<Text>(
      find.descendant(of: _cell('2026-11-08'), matching: find.text('2 off')),
    );
    expect(sub.style!.color, const Color(0xFFFFFFFF));
    // Public holiday for everyone.
    expect(_fill(tester, '2026-11-09'), d.holCell);
    final ph = tester.widget<Text>(
      find.descendant(of: _cell('2026-11-09'), matching: find.text('PH')),
    );
    expect(ph.style!.color, d.holText);
    // Today's ring.
    final side =
        (tester.widget<Material>(_cell('2026-10-22')).shape!
                as RoundedRectangleBorder)
            .side;
    expect(side.color, d.accent);
  });

  testWidgets('heat map in light: c1 / c2 digits keep the text colour', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        TeamHeatMap(outlook: _sundays(), selected: null, onSelect: (_) {}),
        dark: false,
      ),
    );
    expect(_fill(tester, '2026-11-08'), l.c2);
    expect(_digit(tester, '2026-11-08', '8'), AppTheme.onSurface);
    expect(_digit(tester, '2026-11-01', '1'), l.sunday);
    expect(_digit(tester, '2026-11-15', '15'), l.onC3);
  });

  testWidgets('day detail, chips and avatar in dark', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TeamDayDetail(outlook: outlook(), day: DateTime(2026, 10, 22)),
            TeamFilterChip(label: 'All', selected: true, onTap: () {}),
            TeamFilterChip(label: 'Sales', selected: false, onTap: () {}),
            const TeamAvatar(id: 7, initials: 'AB'),
            const TeamYouChip(),
            const TeamPendingChip(),
          ],
        ),
      ),
    );
    final title = tester.widget<Text>(
      find.textContaining('Thu 22 Oct').first,
    );
    expect(title.style!.color, OmniColors.dark.textSub);
    expect(
      tester.widget<Text>(find.text('All')).style!.color,
      d.onAccentTint,
    );
    expect(
      tester.widget<Text>(find.text('Sales')).style!.color,
      OmniColors.dark.textSub,
    );
    expect(
      tester.widget<Text>(find.text('AB')).style!.color,
      const Color(0xFFFFFFFF),
    );
    expect(
      tester.widget<Text>(find.text('You').last).style!.color,
      d.onAccentTint,
    );
    expect(
      tester.widget<Text>(find.text('Pending').last).style!.color,
      d.leave,
    );
  });

  testWidgets('overview tiles in dark', (tester) async {
    _tall(tester);
    const counts = OverviewCounts(
      onTime: 36,
      lateCount: 6,
      notInYet: 4,
      noCheckIn: 3,
      onLeave: 4,
      offToday: 1,
    );
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            const OverviewTodayTile(
              counts: counts,
              scopeLabel: 'Novaworks',
              asOf: '09:41',
              live: true,
            ),
            OverviewCountGrid(cells: todayCells(counts), onTap: (_) {}),
          ],
        ),
      ),
    );
    final tile = tester.widget<Container>(
      find.byKey(const ValueKey('ov-today-tile')),
    );
    expect(
      (tile.decoration! as BoxDecoration).color,
      OmniColors.dark.brandFill,
    );
    // The bar keeps the light fills (they sit on the tile).
    final late = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('ov-bar-late')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(late.color, l.late.fill);
    // Count tiles: dark card, dark My day dot.
    final onLeave = find.byKey(const ValueKey('ov-tile-on_leave'));
    expect(tester.widget<Material>(onLeave).color, OmniColors.dark.card);
    final dot = tester
        .widgetList<Container>(
          find.descendant(of: onLeave, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(dot.color, MyDayPalette.dark.leave.dot);
    expect(
      tester.widget<Text>(find.text('36')).style!.color,
      OmniColors.dark.text,
    );
  });
}
