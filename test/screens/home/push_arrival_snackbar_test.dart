import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/home_shell.dart';
import 'package:omni_hr/services/push_service.dart';

const _arrival = PushArrival(
  kind: 'remind_check_out',
  title: 'Still checked in?',
  body: 'Your shift ended at 17:00 and you are still checked in. Tap to check out.',
);

/// Shows the reminder snackbar from a button, like HomeShell does.
Widget _host(VoidCallback onOpen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(pushArrivalSnackBar(_arrival, onOpen: onOpen)),
          child: const Text('ARRIVE'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the reminder snackbar shows the push text and Open goes Home', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_host(() => opened++));
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    expect(find.text('Still checked in?'), findsOneWidget);
    expect(find.textContaining('Your shift ended at 17:00'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  // Device test 2026-10-30: an automatic check-in arrived while My day was
  // open; My day kept "No check-in" and its Undo window ran out unseen.
  group('arrivalPlan', () {
    const auto = PushArrival(
      kind: 'auto_checked_in',
      title: 'Checked in automatically · 16:57',
      body: '',
    );

    test('automatic punch with My day on screen: reload it, no snackbar', () {
      final plan = arrivalPlan([auto], myDayOnScreen: true);
      expect(plan.refreshMyDay, isTrue);
      expect(plan.snack, isNull);
    });

    test('automatic punch elsewhere: the Open snackbar, no reload', () {
      final plan = arrivalPlan([auto], myDayOnScreen: false);
      expect(plan.refreshMyDay, isFalse);
      expect(plan.snack, same(auto));
    });

    test('a reminder keeps its snackbar on My day', () {
      final plan = arrivalPlan([_arrival], myDayOnScreen: true);
      expect(plan.refreshMyDay, isFalse);
      expect(plan.snack, same(_arrival));
    });

    test('a newer reminder over an automatic punch: reload and snackbar', () {
      final plan = arrivalPlan([_arrival, auto], myDayOnScreen: true);
      expect(plan.refreshMyDay, isTrue);
      expect(plan.snack, same(_arrival));
    });

    test('nothing arrived: nothing to do', () {
      final plan = arrivalPlan(const [], myDayOnScreen: true);
      expect(plan.refreshMyDay, isFalse);
      expect(plan.snack, isNull);
    });
  });

  testWidgets('it goes away by itself', (tester) async {
    await tester.pumpWidget(_host(() {}));
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
