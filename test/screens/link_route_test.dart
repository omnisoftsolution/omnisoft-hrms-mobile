import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';
import 'package:omni_hr/screens/activation/add_phone_screen.dart';
import 'package:omni_hr/screens/activation/link_route.dart';
import 'package:omni_hr/services/deep_link_service.dart';

void main() {
  test('an add-phone link opens Add this phone with the link values', () {
    final w = screenForActivationLink(const ActivationArgs('NOVAWORKS', 'T',
        login: 'budi.s', kind: ActivationKind.addPhone));
    expect(w, isA<AddPhoneScreen>());
    final s = w as AddPhoneScreen;
    expect(s.companyCode, 'NOVAWORKS');
    expect(s.token, 'T');
    expect(s.login, 'budi.s');
  });

  test('an invite link opens the activation screen as before', () {
    final w = screenForActivationLink(
        const ActivationArgs('NOVAWORKS', 'T', login: 'budi.s'));
    expect(w, isA<ActivationScreen>());
    final s = w as ActivationScreen;
    expect(s.companyCode, 'NOVAWORKS');
    expect(s.token, 'T');
    expect(s.login, 'budi.s');
  });

  // main.dart's deep-link handler (cold start or warm link) goes through
  // pushActivationLink on the root navigator.
  testWidgets(
      'a k=add deep link pushes Add this phone above the root route, which '
      'stays underneath', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey, home: const Scaffold(body: Text('ROOT'))));
    final args = parseActivationLink(
        Uri.parse('omnihr://activate?k=add&c=NOVAWORKS&t=T&l=budi.s'))!;
    pushActivationLink(navKey.currentState!, args);
    await tester.pumpAndSettle();
    final screen = tester.widget<AddPhoneScreen>(find.byType(AddPhoneScreen));
    expect(screen.companyCode, 'NOVAWORKS');
    expect(screen.token, 'T');
    expect(screen.login, 'budi.s');
    expect(find.byType(ActivationScreen), findsNothing);
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AddPhoneScreen), findsNothing);
    expect(find.text('ROOT'), findsOneWidget);
  });

  testWidgets('an invite deep link (no k) pushes the activation screen',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey, home: const Scaffold(body: Text('ROOT'))));
    final args = parseActivationLink(
        Uri.parse('omnihr://activate?c=NOVAWORKS&t=T'))!;
    pushActivationLink(navKey.currentState!, args);
    await tester.pumpAndSettle();
    expect(find.byType(ActivationScreen), findsOneWidget);
    expect(find.byType(AddPhoneScreen), findsNothing);
  });
}
