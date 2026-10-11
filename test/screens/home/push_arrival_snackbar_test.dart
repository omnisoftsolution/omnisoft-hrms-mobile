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

  testWidgets('it goes away by itself', (tester) async {
    await tester.pumpWidget(_host(() {}));
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
