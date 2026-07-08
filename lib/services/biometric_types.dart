import 'package:local_auth/local_auth.dart';

/// Which biometric modality to name in the UI.
enum BiometricKind { faceId, touchId, fingerprint, face, iris, generic, none }

/// A stored login+password pair, returned once a biometric prompt passes.
class BiometricCredential {
  final String login;
  final String password;
  const BiometricCredential(this.login, this.password);
}

/// Outcome of a biometric prompt / retrieve attempt.
enum BiometricAuthOutcome { success, canceled, lockedOut, unavailable, failed }

/// Result of [BiometricAuthService.authenticateAndRetrieve].
/// [credential] is non-null only when [outcome] == success.
class BiometricAuthResult {
  final BiometricAuthOutcome outcome;
  final BiometricCredential? credential;
  const BiometricAuthResult(this.outcome, [this.credential]);
}

/// Thin seam over `local_auth` so the service is unit-testable without a
/// platform channel. Real implementation: `LocalAuthGate`.
abstract class BiometricGate {
  /// Hardware present AND at least one biometric enrolled.
  Future<bool> isAvailable();

  /// Enrolled modalities, for choosing the UI label.
  Future<List<BiometricType>> enrolledTypes();

  /// Show the OS biometric prompt. Maps platform errors to an outcome.
  Future<BiometricAuthOutcome> authenticate(String localizedReason);
}

/// Pure mapping of platform + enrolled modalities to a UI kind.
/// iOS names face → Face ID and fingerprint → Touch ID.
BiometricKind biometricKindFor(bool isIOS, List<BiometricType> types) {
  if (types.isEmpty) return BiometricKind.none;
  if (types.contains(BiometricType.face)) {
    return isIOS ? BiometricKind.faceId : BiometricKind.face;
  }
  if (types.contains(BiometricType.fingerprint)) {
    return isIOS ? BiometricKind.touchId : BiometricKind.fingerprint;
  }
  if (types.contains(BiometricType.iris)) return BiometricKind.iris;
  return BiometricKind.generic;
}
