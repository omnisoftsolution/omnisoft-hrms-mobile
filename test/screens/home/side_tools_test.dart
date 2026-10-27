import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/home/side_tab_column.dart';
import 'package:omni_hr/services/duo_service.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/omni_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _duo(WidgetTester tester, {double right = 0, double left = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(466, 678);
  tester.view.viewPadding = FakeViewPadding(
    right: right,
    left: left,
    bottom: 20,
  );
  tester.view.padding = FakeViewPadding(right: right, left: left, bottom: 20);
}

Widget _app(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SessionService>(create: (_) => SessionService()),
    ChangeNotifierProvider<NotificationService>(
      create: (_) => NotificationService(),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => SideColumnHost(child: child!),
    home: home,
  ),
);

SideColumnHostState _host(WidgetTester tester) =>
    tester.state<SideColumnHostState>(find.byType(SideColumnHost));

List<String> _labels(WidgetTester tester) => [
  for (final t in _host(tester).offeredTools ?? const <SideTool>[]) t.label,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('iPhone Duo closed: the bell and the profile move to the top '
      'of the column; the title stays in the bar', (tester) async {
    addTearDown(tester.view.reset);
    _duo(tester, right: 84);
    await tester.pumpWidget(
      _app(const Scaffold(appBar: OmniAppBar(title: 'Leave'))),
    );
    await tester.pump();
    expect(_labels(tester), ['Notifications', 'Profile']);
    expect(find.text('Leave'), findsOneWidget);
    expect(find.byType(OmniBellButton), findsNothing);
    final bell = tester.getTopLeft(find.bySemanticsLabel('Notifications'));
    expect(bell.dx, greaterThanOrEqualTo(466 - 84));
    expect(bell.dy, greaterThanOrEqualTo(kSideStatusHeight));
  });

  testWidgets('a pushed page adds Back on top; Back pops it', (tester) async {
    addTearDown(tester.view.reset);
    _duo(tester, right: 84);
    await tester.pumpWidget(
      _app(const Scaffold(appBar: OmniAppBar(title: 'Leave'))),
    );
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(appBar: OmniAppBar(title: 'Payroll')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_labels(tester), ['Back', 'Notifications', 'Profile']);
    // The bar keeps no back arrow of its own.
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Payroll'), findsNothing);
    expect(_labels(tester), ['Notifications', 'Profile']);
  });

  testWidgets('a page without OmniAppBar on top empties the tools', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    _duo(tester, right: 84);
    await tester.pumpWidget(
      _app(const Scaffold(appBar: OmniAppBar(title: 'Leave'))),
    );
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Profile'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(_host(tester).offeredTools, isNull);
  });

  testWidgets('a plain phone keeps the bell and avatar in the bar', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    _duo(tester);
    await tester.pumpWidget(
      _app(const Scaffold(appBar: OmniAppBar(title: 'Leave'))),
    );
    await tester.pump();
    expect(find.byType(OmniBellButton), findsOneWidget);
    expect(_host(tester).offeredTools, isNull);
  });

  testWidgets('a left column (split view) moves the fold into the app frame', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    _duo(tester, left: 84);
    late List<DisplayFeature> seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            displayFeatures: const [
              DisplayFeature(
                bounds: Rect.fromLTWH(200, 0, 40, 678),
                type: DisplayFeatureType.fold,
                state: DisplayFeatureState.postureHalfOpened,
              ),
            ],
          ),
          child: SideColumnHost(child: child!),
        ),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.of(context).displayFeatures;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.single.bounds, const Rect.fromLTWH(116, 0, 40, 678));
  });

  testWidgets('closed Duo: buttons start where iOS says the bar does and '
      'sit on its centre line (the camera)', (tester) async {
    addTearDown(tester.view.reset);
    final service = DuoService.instance;
    addTearDown(() => service.debugGeometry = DuoGeometry.none);
    _duo(tester, right: 84);
    // Measured on the iOS 27.1 simulator, closed (466 × 678).
    service.debugGeometry = DuoGeometry.fromMap(const {
      'available': true,
      'hinge': 'closed',
      'divisions': [],
      'occlusions': [],
      'barRight': [394, 170, 48, 474],
    });
    await tester.pumpWidget(
      DuoFeatures(
        child: _app(const Scaffold(appBar: OmniAppBar(title: 'Leave'))),
      ),
    );
    await tester.pump();
    await tester.pump();
    final bell = tester.getRect(find.byKey(const ValueKey('side-tool-0')));
    expect(bell.top, 170);
    expect(bell.center.dx, 418);
  });
}
