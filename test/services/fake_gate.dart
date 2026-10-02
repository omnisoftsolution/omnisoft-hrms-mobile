import 'package:local_auth/local_auth.dart';
import 'package:omni_hr/services/biometric_types.dart';

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
