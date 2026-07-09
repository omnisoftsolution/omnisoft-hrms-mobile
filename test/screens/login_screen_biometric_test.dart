import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/screens/login/login_screen.dart';

/// Scriptable gate. Default outcome `canceled` so the biometric path
/// stops before any network login — we only assert the prompt fired.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  int authCalls = 0;
  FakeBiometricGate({
    this.available = true,
    this.types = const [BiometricType.fingerprint],
    this.nextOutcome = BiometricAuthOutcome.canceled,
  });
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<BiometricType>> enrolledTypes() async => types;
  @override
  Future<BiometricAuthOutcome> authenticate(String reason) async {
    authCalls++;
    return nextOutcome;
  }
}

Widget _host(BiometricAuthService bio, {required bool autoPrompt}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(value: SessionService()),
        ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
      ],
      child: MaterialApp(home: LoginScreen(autoPromptBiometric: autoPrompt)),
    );

Future<BiometricAuthService> _loadedBio(FakeBiometricGate gate) async {
  final bio = BiometricAuthService(gate: gate);
  await bio.load();
  return bio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
  });

  testWidgets('shows the Face ID button when a credential is stored + capable, '
      'and does not auto-prompt when suppressed', (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    expect(gate.authCalls, 0);
  });

  testWidgets('hides the Face ID button when no credential is stored',
      (tester) async {
    SharedPreferences.setMockInitialValues({}); // biometric_enabled absent
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with'), findsNothing);
  });

  testWidgets('auto-prompts biometric on open when autoPromptBiometric is true',
      (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: true));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 1);
  });

  testWidgets('does not auto-prompt when suppressed, but tapping the button does',
      (tester) async {
    final gate = FakeBiometricGate(available: true);
    final bio = await _loadedBio(gate);
    await tester.pumpWidget(_host(bio, autoPrompt: false));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 0);
    await tester.ensureVisible(find.text('Sign in with fingerprint'));
    await tester.tap(find.text('Sign in with fingerprint'));
    await tester.pumpAndSettle();
    expect(gate.authCalls, 1);
  });
}
