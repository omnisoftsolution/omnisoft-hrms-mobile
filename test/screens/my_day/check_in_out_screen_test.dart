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

void main() {
  testWidgets('opens on the pulsing CHECK IN circle, then the capture', (
    tester,
  ) async {
    final host = _Host();
    final captured = <FaceCaptureResult>[];
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: false,
          shiftLabel: '08:00 – 17:00',
          placeLabel: 'At the office · 24 m',
          captureBuilder: _fakeCapture,
          run: (capture) async {
            captured.add(await capture());
            return const AttendanceActionOutcome.success(checkedIn: true);
          },
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BigCheckButton), findsOneWidget);
    expect(find.text('CHECK IN'), findsOneWidget);
    expect(find.text('Shift 08:00 – 17:00'), findsOneWidget);
    expect(find.text('At the office · 24 m'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-capture')), findsNothing);

    // The countdown starts by itself after the short pulse.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('fake-capture')), findsOneWidget);
    expect(find.byType(BigCheckButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    expect(captured.single.success, isTrue);
    expect(find.byKey(const ValueKey('check-done')), findsOneWidget);
    expect(find.textContaining('Checked in '), findsOneWidget);
    expect(host.done, isFalse);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.done, isTrue);
    expect(host.popped?.outcome?.checkedIn, isTrue);
    expect(host.popped?.error, isNull);
  });

  testWidgets('check-out reads CHECK OUT and the tick says Checked out', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: true,
          captureBuilder: _fakeCapture,
          run: (capture) async {
            await capture();
            return const AttendanceActionOutcome.success(checkedIn: false);
          },
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CHECK OUT'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    expect(find.textContaining('Checked out '), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.popped?.outcome?.checkedIn, isFalse);
  });

  testWidgets('shows the scanning circle while the punch is sent', (
    tester,
  ) async {
    final host = _Host();
    final sent = Completer<void>();
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: false,
          captureBuilder: _fakeCapture,
          run: (capture) async {
            await capture();
            await sent.future; // verify + POST still running
            return const AttendanceActionOutcome.success(checkedIn: true);
          },
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1, milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('SCANNING…'), findsOneWidget);
    sent.complete();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(host.popped?.outcome?.ok, isTrue);
  });

  testWidgets('an error outcome pops at once, without the tick', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: false,
          captureBuilder: _fakeCapture,
          run: (capture) async =>
              const AttendanceActionOutcome.failure('Outside the office'),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('check-done')), findsNothing);
    await tester.pumpAndSettle();
    expect(host.done, isTrue);
    expect(host.popped?.outcome?.error, 'Outside the office');
  });

  testWidgets('a cancelled capture pops with no outcome', (tester) async {
    final host = _Host();
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: false,
          captureBuilder: (onResult) =>
              _fakeCapture(onResult, result: FaceCaptureResult.cancelled()),
          run: (capture) async {
            final r = await capture();
            return r.success
                ? const AttendanceActionOutcome.success(checkedIn: true)
                : null;
          },
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1, milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pumpAndSettle();
    expect(host.done, isTrue);
    expect(host.popped?.outcome, isNull);
    expect(host.popped?.error, isNull);
  });

  testWidgets('a run that throws pops the error', (tester) async {
    final host = _Host();
    await tester.pumpWidget(
      host.build(
        CheckInOutScreen(
          checkingOut: false,
          captureBuilder: _fakeCapture,
          run: (capture) async => throw StateError('no device id'),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(host.done, isTrue);
    expect(host.popped?.error, isA<StateError>());
  });
}
