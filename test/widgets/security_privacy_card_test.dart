import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/widgets/security_privacy_card.dart';

/// Scriptable BiometricGate — no platform channel.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  FakeBiometricGate({
    this.available = true,
    this.types = const [BiometricType.fingerprint],
    this.nextOutcome = BiometricAuthOutcome.success,
  });
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<BiometricType>> enrolledTypes() async => types;
  @override
  Future<BiometricAuthOutcome> authenticate(String reason) async => nextOutcome;
}

Widget _host(BiometricAuthService svc) => MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<BiometricAuthService>.value(
          value: svc,
          child: const SecurityPrivacyCard(
              login: 'budi@acme.sg', displayName: 'Budi'),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows biometric toggle + Privacy Policy when device capable',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    expect(find.text('Security & Privacy'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('hides toggle but keeps Privacy Policy when not capable',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: false));
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('toggling on opens the "Confirm your password" dialog',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your password'), findsOneWidget);
  });

  testWidgets('toggling off disables biometric login', (tester) async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    expect(svc.isEnabled, isTrue);
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile)); // on -> off
    await tester.pumpAndSettle();
    expect(svc.isEnabled, isFalse);
  });
}
