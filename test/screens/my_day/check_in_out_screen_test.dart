import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/face_capture_result.dart';
import 'package:omni_hr/screens/home/my_day/check_in_out_screen.dart';
import 'package:omni_hr/services/attendance_action_controller.dart';
import 'package:omni_hr/widgets/big_check_button.dart';

/// A capture stand-in: one button that reports the given result.
Widget _fakeCapture(
  ValueChanged<FaceCaptureResult> onResult, {
  FaceCaptureResult? result,
}) => Center(
  child: TextButton(
    key: const ValueKey('fake-capture'),
    onPressed: () =>
        onResult(result ?? FaceCaptureResult.success('/tmp/face.jpg')),
    child: const Text('SNAP'),
  ),
);

/// Pushes the page from a blank home and keeps what it pops.
class _Host {
  CheckInOutResult? popped;
  bool done = false;

  Widget build(CheckInOutScreen page) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              popped = await Navigator.of(
                context,
              ).push<CheckInOutResult>(MaterialPageRoute(builder: (_) => page));
              done = true;
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
}

/// The steps a successful perform() reports, around the capture.
Future<AttendanceActionOutcome?> _happyRun(
  Future<FaceCaptureResult> Function() capture,
  PunchStepCallback onStep, {
  bool checkedIn = true,
}) async {
  onStep(PunchStep.location, PunchStepState.running, 'Locating…');
  onStep(PunchStep.location, PunchStepState.done, 'Office (24 m)');
  onStep(PunchStep.wifi, PunchStepState.running, 'Checking…');
  onStep(PunchStep.wifi, PunchStepState.skipped, 'Not required');
  onStep(PunchStep.face, PunchStepState.running, 'Look at the camera');
  final r = await capture();
  if (!r.success) return null;
  onStep(PunchStep.face, PunchStepState.done, 'Matched');
  onStep(PunchStep.record, PunchStepState.running, 'Sending…');
  onStep(PunchStep.record, PunchStepState.done, '');
  return AttendanceActionOutcome.success(checkedIn: checkedIn);
}

CheckInOutScreen _page({
  bool checkingOut = false,
  required Future<AttendanceActionOutcome?> Function(
    Future<FaceCaptureResult> Function() capture,
    PunchStepCallback onStep,
  )
  run,
  Widget Function(ValueChanged<FaceCaptureResult>)? capture,
}) => CheckInOutScreen(
  checkingOut: checkingOut,
  employeeName: 'Ethan Smith',
  shiftLabel: '08:00 – 17:00',
  headerNote: '1h 53m late',
  hoursToday: '0h 00m',
  lastLabel: 'Last out 18:25',
  captureBuilder: capture ?? _fakeCapture,
  run: run,
);

Future<void> _open(
  WidgetTester tester,
  _Host host,
  CheckInOutScreen page,
) async {
  await tester.pumpWidget(host.build(page));
  await tester.tap(find.text('OPEN'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('header, circle and checklist; the camera starts by itself', (
    tester,
  ) async {
    final host = _Host();
    await _open(tester, host, _page(run: _happyRun));
    expect(find.text('Ethan Smith'), findsOneWidget);
    expect(find.textContaining('Shift 08:00 – 17:00'), findsOneWidget);
    expect(find.text('1h 53m late'), findsOneWidget);
    expect(find.text('Hours today 0h 00m'), findsOneWidget);
    expect(find.text('Last out 18:25'), findsOneWidget);
    expect(find.text('CHECK IN'), findsOneWidget);
    for (final t in [
      'Location',
      'Office Wi-Fi',
      'Face',
      'Record the check-in',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // The gates already ran: their rows carry the result.
    expect(find.text('Office (24 m)'), findsOneWidget);
    expect(find.text('Not required'), findsOneWidget);
    expect(find.text('Look at the camera'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-capture')), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('fake-capture')), findsOneWidget);
    expect(find.byType(BigCheckButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    expect(find.text('Matched'), findsOneWidget);
    expect(find.byKey(const ValueKey('check-done')), findsOneWidget);
    expect(find.textContaining('Checked in '), findsNWidgets(2)); // tick + row
    expect(host.done, isFalse);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.done, isTrue);
    expect(host.popped?.outcome?.checkedIn, isTrue);
  });

  testWidgets('the circle is 30% bigger than the 1.28 home button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 12
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final host = _Host();
    await _open(tester, host, _page(run: _happyRun));
    expect(
      tester.widget<BigCheckButton>(find.byType(BigCheckButton)).size,
      260,
    );
    expect(tester.getSize(find.byType(BigCheckButton)).width, 308);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('check-done'))).width, 308);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('rows tick live as perform() reports them', (tester) async {
    final host = _Host();
    final gps = Completer<void>();
    await _open(
      tester,
      host,
      _page(
        run: (capture, onStep) async {
          onStep(PunchStep.location, PunchStepState.running, 'Locating…');
          await gps.future;
          onStep(PunchStep.location, PunchStepState.done, 'Office (24 m)');
          return null;
        },
      ),
    );
    expect(find.text('Locating…'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-location-done')), findsNothing);
    gps.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('step-location-done')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('check-out reads CHECK OUT and Checked out', (tester) async {
    final host = _Host();
    await _open(
      tester,
      host,
      _page(
        checkingOut: true,
        run: (c, s) => _happyRun(c, s, checkedIn: false),
      ),
    );
    expect(find.text('CHECK OUT'), findsOneWidget);
    expect(find.text('Record the check-out'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    expect(find.textContaining('Checked out '), findsNWidgets(2));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.popped?.outcome?.checkedIn, isFalse);
  });

  testWidgets('the scanning circle shows while the punch is sent', (
    tester,
  ) async {
    final host = _Host();
    final sent = Completer<void>();
    await _open(
      tester,
      host,
      _page(
        run: (capture, onStep) async {
          await capture();
          onStep(PunchStep.record, PunchStepState.running, 'Sending…');
          await sent.future;
          return const AttendanceActionOutcome.success(checkedIn: true);
        },
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('SCANNING…'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);
    sent.complete();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.popped?.outcome?.ok, isTrue);
  });

  testWidgets('a failed step stays on the page with the reason and Close', (
    tester,
  ) async {
    final host = _Host();
    await _open(
      tester,
      host,
      _page(
        run: (capture, onStep) async {
          onStep(PunchStep.location, PunchStepState.running, 'Locating…');
          return const AttendanceActionOutcome.failure(
            'You are outside the office area.',
          );
        },
      ),
    );
    expect(find.byKey(const ValueKey('step-location-failed')), findsOneWidget);
    expect(find.text('You are outside the office area.'), findsOneWidget);
    expect(find.text('NOT READY'), findsOneWidget);
    expect(host.done, isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(host.done, isTrue);
    expect(host.popped?.outcome, isNull); // the page already said why
  });

  testWidgets('a run that throws shows the friendly reason', (tester) async {
    final host = _Host();
    await _open(
      tester,
      host,
      _page(run: (capture, onStep) async => throw StateError('boom')),
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-location-failed')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(host.popped?.outcome, isNull);
  });

  testWidgets('a cancelled capture closes the page at once', (tester) async {
    final host = _Host();
    await _open(
      tester,
      host,
      _page(
        run: _happyRun,
        capture: (onResult) =>
            _fakeCapture(onResult, result: FaceCaptureResult.cancelled()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pumpAndSettle();
    expect(host.done, isTrue);
    expect(host.popped?.outcome, isNull);
  });
}
