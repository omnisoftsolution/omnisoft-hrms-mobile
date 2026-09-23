import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';

void main() {
  testWidgets(
      'prefilled token hides the code field and asks for email + password',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ActivationScreen(companyCode: 'NOVAWORKS', token: 'T')));
    expect(find.byKey(const Key('activation_code')), findsNothing);
    expect(find.byKey(const Key('activation_email')), findsOneWidget);
    expect(find.byKey(const Key('activation_password')), findsOneWidget);
    expect(find.text('NOVAWORKS'), findsOneWidget);
  });
  testWidgets(
      'manual mode shows company code, email, code, password; '
      'button disabled until valid', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    expect(find.byKey(const Key('activation_company')), findsOneWidget);
    expect(find.byKey(const Key('activation_code')), findsOneWidget);
    final btn = find.widgetWithText(FilledButton, 'Activate');
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('activation_company')), 'NOVAWORKS');
    await tester.enterText(find.byKey(const Key('activation_email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('activation_code')), '123456');
    await tester.enterText(
        find.byKey(const Key('activation_password')), 'longenough');
    await tester.enterText(
        find.byKey(const Key('activation_password2')), 'longenough');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
  });
}
