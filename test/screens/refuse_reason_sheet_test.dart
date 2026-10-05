import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/approvals/refuse_reason_sheet.dart';

/// A page with one button that opens the sheet and records its result.
Widget host({
  required Future<String?> Function(String reason) onSubmit,
  required void Function(bool submitted) onClosed,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              onClosed(await showRefuseReasonSheet(ctx,
                  employeeName: 'Lim Say Puay', onSubmit: onSubmit));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

Finder get refuseButton => find.widgetWithText(FilledButton, 'Refuse');
Finder get cancelButton => find.widgetWithText(OutlinedButton, 'Cancel');

bool enabled<T extends ButtonStyleButton>(WidgetTester tester, Finder f) =>
    tester.widget<T>(f).onPressed != null;

void main() {
  testWidgets('Refuse is enabled only from 3 trimmed characters',
      (tester) async {
    await tester.pumpWidget(host(onSubmit: (_) async => null, onClosed: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Refuse this request'), findsOneWidget);
    expect(
        find.text('Lim Say Puay will see your reason in the app and in Odoo.'),
        findsOneWidget);
    expect(find.text('Reason (required)'), findsOneWidget);
    expect(enabled<FilledButton>(tester, refuseButton), isFalse);

    await tester.enterText(find.byType(TextField), '   no   ');
    await tester.pump();
    expect(enabled<FilledButton>(tester, refuseButton), isFalse);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(enabled<FilledButton>(tester, refuseButton), isTrue);
  });

  testWidgets('submits the trimmed reason and closes with true',
      (tester) async {
    final reasons = <String>[];
    final closed = <bool>[];
    await tester.pumpWidget(host(
      onSubmit: (r) async {
        reasons.add(r);
        return null;
      },
      onClosed: closed.add,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Month-end closing  ');
    await tester.pump();
    await tester.tap(refuseButton);
    await tester.pumpAndSettle();

    expect(reasons, ['Month-end closing']);
    expect(closed, [true]);
    expect(find.text('Refuse this request'), findsNothing);
  });

  testWidgets('Cancel closes with false and submits nothing', (tester) async {
    final reasons = <String>[];
    final closed = <bool>[];
    await tester.pumpWidget(host(
      onSubmit: (r) async {
        reasons.add(r);
        return null;
      },
      onClosed: closed.add,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Coverage issue');
    await tester.pump();
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(reasons, isEmpty);
    expect(closed, [false]);
  });

  testWidgets('both buttons are locked while the refusal is in flight',
      (tester) async {
    final gate = Completer<String?>();
    final closed = <bool>[];
    await tester.pumpWidget(
        host(onSubmit: (_) => gate.future, onClosed: closed.add));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Coverage issue');
    await tester.pump();
    await tester.tap(refuseButton);
    await tester.pump();

    expect(enabled<FilledButton>(tester, refuseButton), isFalse);
    expect(enabled<OutlinedButton>(tester, cancelButton), isFalse);
    expect(closed, isEmpty);

    gate.complete(null);
    await tester.pumpAndSettle();
    expect(closed, [true]);
  });

  testWidgets('a server message is shown under the field and the sheet stays',
      (tester) async {
    final closed = <bool>[];
    await tester.pumpWidget(host(
      onSubmit: (_) async => 'Write a reason of 3 to 500 characters.',
      onClosed: closed.add,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(refuseButton);
    await tester.pumpAndSettle();

    expect(find.text('Write a reason of 3 to 500 characters.'), findsOneWidget);
    expect(find.text('Refuse this request'), findsOneWidget);
    expect(closed, isEmpty);
    expect(enabled<FilledButton>(tester, refuseButton), isTrue);

    // Typing again clears the server message.
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    expect(find.text('Write a reason of 3 to 500 characters.'), findsNothing);
  });

  testWidgets('an onSubmit that throws is shown as a friendly message',
      (tester) async {
    await tester.pumpWidget(host(
      onSubmit: (_) async => throw Exception('network_error'),
      onClosed: (_) {},
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(refuseButton);
    await tester.pumpAndSettle();

    expect(
        find.text('No internet connection. Check your network and try again.'),
        findsOneWidget);
    expect(find.text('Refuse this request'), findsOneWidget);
  });
}
