import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/login/device_code_dialog.dart';

void main() {
  testWidgets('returns the six digits, blocks submit until complete',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showDeviceCodeDialog(ctx, email: 'a@b.c');
                },
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a@b.c'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result, '123456');
  });

  testWidgets('cancel returns null', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showDeviceCodeDialog(ctx, email: 'a@b.c');
                },
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('the code field accepts digits only', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => TextButton(
                onPressed: () => showDeviceCodeDialog(ctx, email: 'a@b.c'),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12ab34 5');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12345');
    final submit = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('shows the error passed in', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => TextButton(
                onPressed: () => showDeviceCodeDialog(ctx,
                    email: 'a@b.c', error: 'That code is not right.'),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('That code is not right.'), findsOneWidget);
  });
}
