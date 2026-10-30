import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / Keystore home of the automatic check-in key.
///
/// The key authenticates the background isolate's posts (header
/// `X-Omni-Auto-Key`), so a wake never depends on the access session. It is
/// stored `first_unlock` (lead decision L2): a geofence wake usually happens
/// with the phone locked, and the default `unlocked` class would not be
/// readable then. The access / refresh tokens keep their own options.
class AutoKeyStore {
  AutoKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const keyName = 'omni_auto_key';
  static const deviceKeyName = 'omni_auto_key_device';

  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage;

  /// The stored key, or null when none is stored or the keychain cannot be
  /// read right now (a background wake treats both as "no key" and skips).
  Future<String?> read() => _read(keyName);

  /// The device id the key was issued to, or null (same rules as [read]).
  Future<String?> deviceId() => _read(deviceKeyName);

  Future<void> write(String key, String deviceId) async {
    await _storage.write(key: keyName, value: key, iOptions: _ios);
    await _storage.write(key: deviceKeyName, value: deviceId, iOptions: _ios);
  }

  Future<void> delete() async {
    await _storage.delete(key: keyName, iOptions: _ios);
    await _storage.delete(key: deviceKeyName, iOptions: _ios);
  }

  Future<String?> _read(String name) async {
    try {
      return await _storage.read(key: name, iOptions: _ios);
    } catch (_) {
      // Locked or unreadable keychain: no key for this wake.
      return null;
    }
  }
}
