import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';

/// Scriptable BiometricGate for tests — no platform channel.
class FakeBiometricGate implements BiometricGate {
  bool available;
  List<BiometricType> types;
  BiometricAuthOutcome nextOutcome;
  int authCalls = 0;

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
  Future<BiometricAuthOutcome> authenticate(String reason) async {
    authCalls++;
    return nextOutcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('capability', () {
    test('isDeviceCapable reflects the gate', () async {
      final svc = BiometricAuthService(gate: FakeBiometricGate(available: true));
      expect(await svc.isDeviceCapable(), isTrue);
      final svc2 =
          BiometricAuthService(gate: FakeBiometricGate(available: false));
      expect(await svc2.isDeviceCapable(), isFalse);
    });

    test('deviceBiometricKind maps enrolled types', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(types: [BiometricType.fingerprint]));
      // Host test platform is not iOS, so fingerprint → fingerprint.
      expect(await svc.deviceBiometricKind(), BiometricKind.fingerprint);
    });
  });

  group('enable / disable', () {
    test('enable stores creds + flag + display name on prompt success',
        () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      final ok = await svc.enable(
          login: 'budi@acme.sg', password: 'pw123', displayName: 'Budi');
      expect(ok, isTrue);
      expect(svc.isEnabled, isTrue);
      expect(svc.displayName, 'Budi');
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), 'budi@acme.sg');
      expect(await secure.read(key: 'biometric_password'), 'pw123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometric_enabled'), isTrue);
      expect(prefs.getString('biometric_display_name'), 'Budi');
    });

    test('enable stores nothing when the prompt is cancelled', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.canceled));
      await svc.load();
      final ok = await svc.enable(login: 'a@b.c', password: 'pw');
      expect(ok, isFalse);
      expect(svc.isEnabled, isFalse);
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), isNull);
    });

    test('disable clears creds + flag + display name', () async {
      final svc =
          BiometricAuthService(gate: FakeBiometricGate());
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw', displayName: 'A');
      await svc.disable();
      expect(svc.isEnabled, isFalse);
      expect(svc.displayName, '');
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'biometric_login'), isNull);
      expect(await secure.read(key: 'biometric_password'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometric_enabled'), anyOf(isFalse, isNull));
    });

    test('load reflects a previously enabled state', () async {
      SharedPreferences.setMockInitialValues({
        'biometric_enabled': true,
        'biometric_display_name': 'Sarah',
      });
      final svc = BiometricAuthService(gate: FakeBiometricGate());
      await svc.load();
      expect(svc.isEnabled, isTrue);
      expect(svc.displayName, 'Sarah');
    });

    test('opt-in dismissal persists', () async {
      final svc = BiometricAuthService(gate: FakeBiometricGate());
      expect(await svc.hasDismissedOptIn(), isFalse);
      await svc.markOptInDismissed();
      expect(await svc.hasDismissedOptIn(), isTrue);
    });
  });

  group('authenticateAndRetrieve', () {
    test('success returns the stored credential', () async {
      final gate = FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success);
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'budi@acme.sg', password: 'pw123');
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.success);
      expect(res.credential!.login, 'budi@acme.sg');
      expect(res.credential!.password, 'pw123');
    });

    test('cancel returns canceled + no credential', () async {
      final gate = FakeBiometricGate();
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      gate.nextOutcome = BiometricAuthOutcome.canceled;
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.canceled);
      expect(res.credential, isNull);
    });

    test('lockedOut propagates', () async {
      final gate = FakeBiometricGate();
      final svc = BiometricAuthService(gate: gate);
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      gate.nextOutcome = BiometricAuthOutcome.lockedOut;
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.lockedOut);
    });

    test('missing stored credential after a passed prompt → failed', () async {
      final gate = FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success);
      final svc = BiometricAuthService(gate: gate);
      await svc.load(); // never enabled → no secret stored
      final res = await svc.authenticateAndRetrieve();
      expect(res.outcome, BiometricAuthOutcome.failed);
      expect(res.credential, isNull);
    });
  });
}
