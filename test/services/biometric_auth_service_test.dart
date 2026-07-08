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
}
