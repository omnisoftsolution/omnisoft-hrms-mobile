import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/home/side_tab_column.dart';

const _tabs = [
  SideTab(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: 'HOME',
  ),
  SideTab(
    icon: Icon(Icons.event_note_outlined),
    selectedIcon: Icon(Icons.event_note_rounded),
    label: 'LEAVE',
  ),
  SideTab(
    icon: Icon(Icons.history_rounded),
    selectedIcon: Icon(Icons.history_rounded),
    label: 'HISTORY',
  ),
];

Widget _host({
  required ThemeData theme,
  int selected = 0,
  ValueChanged<int>? onSelected,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Row(
      children: [
        const Expanded(child: SizedBox()),
        SideTabColumn(
          width: 84,
          bottomInset: 20,
          tabs: _tabs,
          selectedIndex: selected,
          onSelected: onSelected ?? (_) {},
        ),
      ],
    ),
  ),
);

void main() {
  group('sideColumnOf', () {
    test('a plain iPhone held upright has no side column', () {
      expect(
        sideColumnOf(const EdgeInsets.only(top: 59, bottom: 34)),
        SideColumn.none,
      );
    });

    test('a plain iPhone held sideways (insets on both sides) has none', () {
      expect(
        sideColumnOf(const EdgeInsets.only(left: 59, right: 59, bottom: 21)),
        SideColumn.none,
      );
    });

    test('iPhone Duo closed or open sideways: 84 pt on the right', () {
      expect(
        sideColumnOf(const EdgeInsets.only(right: 84, bottom: 20)),
        SideColumn.right,
      );
    });

    test('the column on the left is read as left', () {
      expect(
        sideColumnOf(const EdgeInsets.only(left: 84, bottom: 20)),
        SideColumn.left,
      );
    });

    test('a small lopsided inset is not a column', () {
      expect(sideColumnOf(const EdgeInsets.only(right: 44)), SideColumn.none);
    });
  });

  testWidgets('shows one button per tab and reports taps', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _host(theme: AppTheme.lightTheme, onSelected: (i) => tapped = i),
    );
    expect(find.bySemanticsLabel('HOME'), findsOneWidget);
    expect(find.bySemanticsLabel('LEAVE'), findsOneWidget);
    expect(find.bySemanticsLabel('HISTORY'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('LEAVE'));
    expect(tapped, 1);
  });

  testWidgets('the selected tab shows its selected icon', (tester) async {
    await tester.pumpWidget(_host(theme: AppTheme.lightTheme, selected: 1));
    expect(find.byIcon(Icons.event_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.event_note_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('renders under the dark theme', (tester) async {
    await tester.pumpWidget(_host(theme: AppTheme.darkTheme));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('HOME'), findsOneWidget);
  });
}
