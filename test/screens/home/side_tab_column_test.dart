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

  main2();

  testWidgets('renders under the dark theme', (tester) async {
    await tester.pumpWidget(_host(theme: AppTheme.darkTheme));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('HOME'), findsOneWidget);
  });
}

/// Stands in for HomeShell: offers tabs to the host and records what it sees.
class _Probe extends StatefulWidget {
  const _Probe({this.offerTabs = true});

  final bool offerTabs;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;
  int selected = 0;
  late EdgeInsets seenPadding;
  late double seenWidth;
  late SideColumn seenSide;
  SideColumnHostState? host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    host = SideColumnHost.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    seenPadding = MediaQuery.viewPaddingOf(context);
    seenSide = SideColumnHost.sideOf(context);
    if (widget.offerTabs && seenSide != SideColumn.none) {
      host?.offer(
        this,
        SideTabsSpec(
          tabs: _tabs,
          selectedIndex: selected,
          onSelected: (i) => setState(() => selected = i),
        ),
      );
    }
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          seenWidth = constraints.maxWidth;
          return Center(
            child: TextButton(
              onPressed: () => setState(() => taps++),
              child: Text('taps $taps'),
            ),
          );
        },
      ),
    );
  }
}

void _duo(WidgetTester tester, {required double right, Size? size}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size ?? const Size(466, 678);
  tester.view.viewPadding = FakeViewPadding(right: right, bottom: 20);
  tester.view.padding = FakeViewPadding(right: right, bottom: 20);
}

Widget _app({bool offerTabs = true}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, child) => SideColumnHost(child: child!),
  home: _Probe(offerTabs: offerTabs),
);

_ProbeState _probe(WidgetTester tester) =>
    tester.state<_ProbeState>(find.byType(_Probe));

void main2() {
  group('SideColumnHost', () {
    testWidgets('iPhone Duo closed: the app sits left of the 84 pt column, '
        'which shows the tabs', (tester) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 84);
      await tester.pumpWidget(_app());
      await tester.pump();
      final p = _probe(tester);
      expect(p.seenSide, SideColumn.right);
      expect(p.seenWidth, 466 - 84);
      expect(p.seenPadding.right, 0);
      expect(find.bySemanticsLabel('HOME'), findsOneWidget);
      expect(
        tester.getTopLeft(find.bySemanticsLabel('LEAVE')).dx,
        greaterThan(466 - 84),
      );
      await tester.tap(find.bySemanticsLabel('HISTORY'));
      await tester.pump();
      await tester.pump();
      expect(p.selected, 2);
    });

    testWidgets('open sideways (951×669) works the same way', (tester) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 84, size: const Size(951, 669));
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(_probe(tester).seenWidth, 951 - 84);
      expect(find.bySemanticsLabel('HOME'), findsOneWidget);
    });

    testWidgets('a plain phone: full width, no column, no side tabs', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 0, size: const Size(390, 844));
      await tester.pumpWidget(_app());
      await tester.pump();
      final p = _probe(tester);
      expect(p.seenSide, SideColumn.none);
      expect(p.seenWidth, 390);
      expect(find.bySemanticsLabel('HOME'), findsNothing);
    });

    testWidgets('before sign-in (no tabs offered) the column stays empty', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 84);
      await tester.pumpWidget(_app(offerTabs: false));
      await tester.pump();
      expect(_probe(tester).seenWidth, 466 - 84);
      expect(find.bySemanticsLabel('HOME'), findsNothing);
    });

    testWidgets('folding and unfolding keeps the app state', (tester) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 0, size: const Size(669, 951));
      await tester.pumpWidget(_app());
      await tester.tap(find.text('taps 0'));
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
      // Close the phone: the cover display has the side column.
      _duo(tester, right: 84);
      await tester.pump();
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
      expect(find.bySemanticsLabel('HOME'), findsOneWidget);
      // Open it again.
      _duo(tester, right: 0, size: const Size(669, 951));
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
    });

    testWidgets('a page pushed over everything also stays left of the column', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      _duo(tester, right: 84);
      late double pushedWidth;
      await tester.pumpWidget(_app());
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) => LayoutBuilder(
            builder: (context, c) {
              pushedWidth = c.maxWidth;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pushedWidth, 466 - 84);
    });
  });
}
