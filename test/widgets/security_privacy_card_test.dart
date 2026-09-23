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

Widget _host(
  BiometricAuthService svc, {
  PasswordVerifier? verify,
  String Function()? refreshTokenProvider,
  String authSource = '',
}) =>
    MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<BiometricAuthService>.value(
          value: svc,
          child: SingleChildScrollView(
            child: SecurityPrivacyCard(
              login: 'budi@acme.sg',
              displayName: 'Budi',
              verifyPassword: verify ?? (_) async => PasswordCheck.ok,
              refreshTokenProvider: refreshTokenProvider,
              authSource: authSource,
            ),
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

  testWidgets(
      'refresh token present: enables with the token, never stores the password',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(_host(svc,
        verify: (_) async => PasswordCheck.ok,
        refreshTokenProvider: () => 'RT-123'));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(svc.isEnabled, isTrue);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'biometric_refresh_token'), 'RT-123');
    expect(await storage.read(key: 'biometric_password'), isNull);
  });

  testWidgets('empty refresh token: falls back to storing the password',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
    await svc.load();
    await tester.pumpWidget(_host(svc,
        verify: (_) async => PasswordCheck.ok, refreshTokenProvider: () => ''));
    await tester.pumpAndSettle();
    await _tapToggleAndConfirm(tester);
    expect(svc.isEnabled, isTrue);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'biometric_password'), 'whatever');
    expect(await storage.read(key: 'biometric_refresh_token'), isNull);
  });

  testWidgets('authSource omni: shows Your devices and Change password tiles',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: false));
    await tester.pumpWidget(_host(svc, authSource: 'omni'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Your devices'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Change password'), findsOneWidget);
    expect(find.textContaining('Odoo password'), findsNothing);
  });

  testWidgets('authSource odoo: shows only the app-invite info tile',
      (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: false));
    await tester.pumpWidget(_host(svc, authSource: 'odoo'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Signed in with your Odoo password. HR will send you an app invite.'),
        findsOneWidget);
    expect(find.text('Your devices'), findsNothing);
    expect(find.text('Change password'), findsNothing);
  });

  testWidgets('authSource empty: no identity tiles', (tester) async {
    final svc = BiometricAuthService(gate: FakeBiometricGate(available: false));
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();
    expect(find.text('Your devices'), findsNothing);
    expect(find.text('Change password'), findsNothing);
    expect(find.textContaining('Odoo password'), findsNothing);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
