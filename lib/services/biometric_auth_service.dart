import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';

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
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  static const _sLogin = 'biometric_login';
  static const _sPassword = 'biometric_password';
  static const _kEnabled = 'biometric_enabled';
  static const _kOptInDismissed = 'biometric_optin_dismissed';
  static const _kDisplayName = 'biometric_display_name';

  Future<bool> isDeviceCapable() => _gate.isAvailable();

  Future<BiometricKind> deviceBiometricKind() async {
    final types = await _gate.enrolledTypes();
    return biometricKindFor(Platform.isIOS, types);
  }

  bool _enabled = false;
  String _displayName = '';

  bool get isEnabled => _enabled;
  String get displayName => _displayName;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _displayName = prefs.getString(_kDisplayName) ?? '';
    notifyListeners();
  }

  Future<bool> enable({
    required String login,
    required String password,
    String? displayName,
  }) async {
    final outcome = await _gate
        .authenticate('Confirm your identity to enable biometric login');
    if (outcome != BiometricAuthOutcome.success) return false;
    await _secure.write(key: _sLogin, value: login);
    await _secure.write(key: _sPassword, value: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    if (displayName != null && displayName.isNotEmpty) {
      await prefs.setString(_kDisplayName, displayName);
      _displayName = displayName;
    }
    _enabled = true;
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    try {
      await _secure.delete(key: _sLogin);
      await _secure.delete(key: _sPassword);
    } catch (_) {
      // Continue — prefs cleanup below must always run.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEnabled);
    await prefs.remove(_kDisplayName);
    _enabled = false;
    _displayName = '';
    notifyListeners();
  }

  Future<bool> hasDismissedOptIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptInDismissed) ?? false;
  }

  Future<void> markOptInDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptInDismissed, true);
  }
}
