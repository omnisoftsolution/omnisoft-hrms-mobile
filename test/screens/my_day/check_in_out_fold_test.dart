import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/face_capture_result.dart';
import 'package:omni_hr/screens/home/my_day/check_in_out_screen.dart';
import 'package:omni_hr/services/attendance_action_controller.dart';
import 'package:omni_hr/widgets/big_check_button.dart';

/// A punch that never finishes: the page stays on its first phase.
final _never = Completer<AttendanceActionOutcome?>();

CheckInOutScreen _page() => CheckInOutScreen(
  checkingOut: false,
  employeeName: 'Ethan Smith',
  shiftLabel: '08:00 – 17:00',
  hoursToday: '0h 00m',
  lastLabel: 'Last out 18:25',
  captureBuilder: (ValueChanged<FaceCaptureResult> _) => const SizedBox(),
  run: (_, _) => _never.future,
);

Future<void> _show(
  WidgetTester tester, {
  required Size size,
  List<DisplayFeature> features = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(displayFeatures: features),
        child: child!,
      ),
      home: _page(),
    ),
  );
  await tester.pump();
}

DisplayFeature _fold(Rect r) => DisplayFeature(
  bounds: r,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

Rect _rectOf(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  testWidgets('flat: the usual one-column page', (tester) async {
    addTearDown(tester.view.reset);
    await _show(tester, size: const Size(951, 669));
    expect(find.byKey(const ValueKey('check-fold-vertical')), findsNothing);
    expect(find.byKey(const ValueKey('check-fold-horizontal')), findsNothing);
    expect(find.text('Location'), findsOneWidget);
  });

  testWidgets('half-folded like a book: circle left of the fold, checklist '
      'right of it, nothing in it', (tester) async {
    addTearDown(tester.view.reset);
    const fold = Rect.fromLTWH(455, 0, 41, 669);
    await _show(tester, size: const Size(951, 669), features: [_fold(fold)]);
    expect(find.byKey(const ValueKey('check-fold-vertical')), findsOneWidget);
    final circle = _rectOf(tester, find.byType(BigCheckButton));
    final location = _rectOf(tester, find.text('Location'));
    expect(circle.right, lessThanOrEqualTo(fold.left));
    expect(location.left, greaterThanOrEqualTo(fold.right));
  });

  testWidgets('half-folded on a desk: circle above the fold, checklist below', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    const fold = Rect.fromLTWH(0, 455, 669, 41);
    await _show(tester, size: const Size(669, 951), features: [_fold(fold)]);
    expect(find.byKey(const ValueKey('check-fold-horizontal')), findsOneWidget);
    final circle = _rectOf(tester, find.byType(BigCheckButton));
    final location = _rectOf(tester, find.text('Location'));
    expect(circle.bottom, lessThanOrEqualTo(fold.top));
    expect(location.top, greaterThanOrEqualTo(fold.bottom));
  });

  testWidgets('a fold too close to the edge keeps the one-column page', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _show(
      tester,
      size: const Size(951, 669),
      features: [_fold(const Rect.fromLTWH(120, 0, 20, 669))],
    );
    expect(find.byKey(const ValueKey('check-fold-vertical')), findsNothing);
  });
}
