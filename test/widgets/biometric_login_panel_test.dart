import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/biometric_login_panel.dart';

void main() {
  testWidgets('renders greeting + button, fires callbacks', (tester) async {
    var bio = 0;
    var pwd = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricLoginPanel(
          kind: BiometricKind.faceId,
          greetingName: 'Budi',
          companyName: 'Acme',
          companyLogoB64: null,
          busy: false,
          onBiometric: () => bio++,
          onUsePassword: () => pwd++,
        ),
      ),
    ));
    expect(find.textContaining('Budi'), findsOneWidget);
    expect(find.text('Log in with Face ID'), findsOneWidget);
    await tester.tap(find.text('Log in with Face ID'));
    expect(bio, 1);
    await tester.tap(find.text('Use password instead'));
    expect(pwd, 1);
  });

  testWidgets('falls back to generic greeting when name empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricLoginPanel(
          kind: BiometricKind.fingerprint,
          greetingName: '',
          companyName: 'Acme',
          companyLogoB64: null,
          busy: false,
          onBiometric: () {},
          onUsePassword: () {},
        ),
      ),
    ));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in with fingerprint'), findsOneWidget);
  });
}
