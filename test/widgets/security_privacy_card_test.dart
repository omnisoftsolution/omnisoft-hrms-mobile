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

Widget _host(BiometricAuthService svc, {PasswordVerifier? verify}) => MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<BiometricAuthService>.value(
          value: svc,
          child: SecurityPrivacyCard(
            login: 'budi@acme.sg',
            displayName: 'Budi',
            verifyPassword: verify ?? (_) async => PasswordCheck.ok,
          ),
        ),
      ),
    );

Future<void> _tapToggleAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'whatever');
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

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

  testWidgets('wrong password: shows error, does NOT enable', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.wrongPassword));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(find.textContaining('Incorrect password'), findsOneWidget);
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('network error: shows error, does NOT enable', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.error));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(find.textContaining("Couldn't verify"), findsOneWidget);
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('correct password: enables + shows confirmation', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.ok));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(svc.isEnabled, isTrue);
    expect(find.textContaining('login enabled'), findsOneWidget);
  });

  testWidgets('rate limited: shows too-many-attempts, does NOT enable',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.rateLimited));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(find.textContaining('Too many attempts'), findsOneWidget);
    expect(svc.isEnabled, isFalse);
  });

  testWidgets('verified but biometric confirm canceled: shows could-not-enable',
      (tester) async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(
            available: true, nextOutcome: BiometricAuthOutcome.canceled));
    await svc.load();
    await tester.pumpWidget(
        _host(svc, verify: (_) async => PasswordCheck.ok));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(svc.isEnabled, isFalse);
    expect(find.textContaining("Couldn't enable"), findsOneWidget);
  });

  testWidgets('cancelled password dialog: verifier not called, not enabled',
      (tester) async {
    var verifyCalls = 0;
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(_host(svc, verify: (_) async {
      verifyCalls++;
      return PasswordCheck.ok;
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(verifyCalls, 0);
    expect(svc.isEnabled, isFalse);
  });
}
