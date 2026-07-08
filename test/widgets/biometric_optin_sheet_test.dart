import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/biometric_optin_sheet.dart';

void main() {
  testWidgets('shows label + fires callbacks', (tester) async {
    var enabled = 0;
    var notNow = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricOptInSheet(
          kind: BiometricKind.faceId,
          onEnable: () => enabled++,
          onNotNow: () => notNow++,
        ),
      ),
    ));
    expect(find.text('Enable Face ID'), findsOneWidget);
    await tester.tap(find.text('Enable Face ID'));
    expect(enabled, 1);
    await tester.tap(find.text('Not now'));
    expect(notNow, 1);
  });

  test('biometricLabel maps kinds', () {
    expect(biometricLabel(BiometricKind.faceId), 'Face ID');
    expect(biometricLabel(BiometricKind.touchId), 'Touch ID');
    expect(biometricLabel(BiometricKind.fingerprint), 'fingerprint');
    expect(biometricLabel(BiometricKind.face), 'face unlock');
    expect(biometricLabel(BiometricKind.generic), 'biometric');
  });
}
