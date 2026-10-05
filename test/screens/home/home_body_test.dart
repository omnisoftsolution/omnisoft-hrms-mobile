import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/home_body.dart';

Widget host({required bool attendanceEnabled}) => MaterialApp(
      home: Scaffold(
        body: HomeBody(
          attendanceEnabled: attendanceEnabled,
          approvalsCard: const Text('APPROVALS CARD'),
          lockedPane: const Text('LOCKED PANE'),
          onRefresh: () async {},
          children: const [Text('ATTENDANCE CONTENT')],
        ),
      ),
    );

void main() {
  testWidgets('attendance off: the approvals card shows above the locked pane',
      (tester) async {
    await tester.pumpWidget(host(attendanceEnabled: false));
    expect(find.text('APPROVALS CARD'), findsOneWidget);
    expect(find.text('LOCKED PANE'), findsOneWidget);
    expect(find.text('ATTENDANCE CONTENT'), findsNothing);
    expect(tester.getTopLeft(find.text('APPROVALS CARD')).dy,
        lessThan(tester.getTopLeft(find.text('LOCKED PANE')).dy));
  });

  testWidgets('attendance on: the card is first, before the attendance content',
      (tester) async {
    await tester.pumpWidget(host(attendanceEnabled: true));
    expect(find.text('LOCKED PANE'), findsNothing);
    expect(find.text('ATTENDANCE CONTENT'), findsOneWidget);
    expect(tester.getTopLeft(find.text('APPROVALS CARD')).dy,
        lessThan(tester.getTopLeft(find.text('ATTENDANCE CONTENT')).dy));
  });

  // FeatureLockedPane is a non-scrolling, centred Column of about 360px
  // (about 60px more with its refresh-error banner). The real widget
  // overflows horizontally under the test font (its PrimaryButton row),
  // which would mask the vertical check, so these tests use a stand-in
  // with the same layout contract.
  group('attendance off on a small phone', () {
    Widget pane({bool banner = false}) => Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 300, child: Text('PANE TOP')),
              if (banner) const SizedBox(height: 60, child: Text('BANNER')),
              const Text('PANE BOTTOM'),
            ],
          ),
        );

    Widget host({
      required Widget card,
      required Widget lockedPane,
      Future<void> Function()? onRefresh,
      bool scaled = true,
    }) =>
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scaled ? 1.3 : 1.0)),
            child: child!,
          ),
          home: Scaffold(
            body: HomeBody(
              attendanceEnabled: false,
              approvalsCard: card,
              lockedPane: lockedPane,
              onRefresh: onRefresh ?? () async {},
              children: const [],
            ),
          ),
        );

    setUp(() {});
    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('no overflow with the card, the banner and big text; '
        'the pane is reachable by scrolling', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(host(
        card: const SizedBox(height: 90, child: Text('APPROVALS CARD')),
        lockedPane: pane(banner: true),
      ));
      expect(find.text('APPROVALS CARD'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('PANE BOTTOM'), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('PANE BOTTOM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pull-to-refresh works on the locked path', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      var refreshes = 0;
      await tester.pumpWidget(host(
        card: const SizedBox.shrink(),
        lockedPane: pane(),
        onRefresh: () async => refreshes++,
      ));
      await tester.fling(
          find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });

    testWidgets('a non-approver sees the pane exactly where it was before',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
          host(card: const SizedBox.shrink(), lockedPane: pane(), scaled: false));
      final inBody = tester.getTopLeft(find.text('PANE TOP')).dy;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: pane()),
      ));
      // Vertical position only: the stand-in shrink-wraps horizontally.
      expect(tester.getTopLeft(find.text('PANE TOP')).dy, inBody);
    });
  });
}
