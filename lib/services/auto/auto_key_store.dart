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
  static const ownerKeyName = 'omni_auto_key_owner';

  /// Whose key it is: `<db>|<employeeId>`.
  static String ownerOf(String db, int employeeId) => '$db|$employeeId';

  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage;

  /// The stored key, or null when none is stored or the keychain cannot be
  /// read right now (a background wake treats both as "no key" and skips).
  Future<String?> read() => _read(keyName);

  /// The device id the key was issued to, or null (same rules as [read]).
  Future<String?> deviceId() => _read(deviceKeyName);

  /// Whose key it is ([ownerOf]), or null (same rules as [read]).
  Future<String?> owner() => _read(ownerKeyName);

  /// The stored key when it belongs to employee [employeeId] of [db], else
  /// null. A sign-out whose delete failed or stalled can leave the previous
  /// employee's key behind; it must never post for the next one (F4). A key
  /// without an owner counts as someone else's.
  Future<String?> readFor(String db, int employeeId) async {
    final key = await read();
    if (key == null || key.isEmpty) return null;
    return await owner() == ownerOf(db, employeeId) ? key : null;
  }

  /// Stores [key] for [owner] (see [ownerOf]). The owner is written last: a
  /// reader in between sees no owner, which counts as "no key".
  Future<void> write(
    String key,
    String deviceId, {
    required String owner,
  }) async {
    await _storage.write(key: keyName, value: key, iOptions: _ios);
    await _storage.write(key: deviceKeyName, value: deviceId, iOptions: _ios);
    await _storage.write(key: ownerKeyName, value: owner, iOptions: _ios);
  }

  Future<void> delete() async {
    await _storage.delete(key: ownerKeyName, iOptions: _ios);
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
