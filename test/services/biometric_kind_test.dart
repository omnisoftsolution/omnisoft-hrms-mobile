import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:omni_hr/services/biometric_types.dart';

void main() {
  group('biometricKindFor', () {
    test('iOS + face → faceId', () {
      expect(biometricKindFor(true, [BiometricType.face]), BiometricKind.faceId);
    });
    test('iOS + fingerprint → touchId', () {
      expect(biometricKindFor(true, [BiometricType.fingerprint]),
          BiometricKind.touchId);
    });
    test('Android + face → face', () {
      expect(biometricKindFor(false, [BiometricType.face]), BiometricKind.face);
    });
    test('Android + fingerprint → fingerprint', () {
      expect(biometricKindFor(false, [BiometricType.fingerprint]),
          BiometricKind.fingerprint);
    });
    test('iris → iris', () {
      expect(biometricKindFor(false, [BiometricType.iris]), BiometricKind.iris);
    });
    test('face wins over fingerprint when both present on iOS', () {
      expect(
          biometricKindFor(true, [BiometricType.fingerprint, BiometricType.face]),
          BiometricKind.faceId);
    });
    test('only strong/weak (no specific modality) → generic', () {
      expect(biometricKindFor(false, [BiometricType.strong]),
          BiometricKind.generic);
    });
    test('empty → none', () {
      expect(biometricKindFor(false, const []), BiometricKind.none);
    });
  });
}
