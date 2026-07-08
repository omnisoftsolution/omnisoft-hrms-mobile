import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import 'biometric_types.dart';

/// Real gate over `local_auth`.
class LocalAuthGate implements BiometricGate {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BiometricType>> enrolledTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<BiometricAuthOutcome> authenticate(String localizedReason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return ok ? BiometricAuthOutcome.success : BiometricAuthOutcome.canceled;
    } on Exception catch (e) {
      final code = _codeOf(e);
      if (code == auth_error.lockedOut ||
          code == auth_error.permanentlyLockedOut) {
        return BiometricAuthOutcome.lockedOut;
      }
      if (code == auth_error.notAvailable ||
          code == auth_error.notEnrolled ||
          code == auth_error.passcodeNotSet) {
        return BiometricAuthOutcome.unavailable;
      }
      return BiometricAuthOutcome.failed;
    }
  }

  String _codeOf(Object e) {
    try {
      // PlatformException has a `.code`; read defensively.
      return (e as dynamic).code?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// Owns the "biometric login" capability and the stored credential.
/// Does NOT perform the network login — it returns a verified credential
/// for the caller to replay against the existing `/login`.
class BiometricAuthService extends ChangeNotifier {
  BiometricAuthService({BiometricGate? gate}) : _gate = gate ?? LocalAuthGate();

  final BiometricGate _gate;

  Future<bool> isDeviceCapable() => _gate.isAvailable();

  Future<BiometricKind> deviceBiometricKind() async {
    final types = await _gate.enrolledTypes();
    return biometricKindFor(Platform.isIOS, types);
  }
}
