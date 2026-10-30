import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/auto/auto_key_store.dart';

/// In-memory [FlutterSecureStorage] that records the `iOptions` of each call.
class _FakeSecure extends FlutterSecureStorage {
  _FakeSecure();

  final Map<String, String> data = {};
  final List<IOSOptions?> seen = [];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    seen.add(iOptions);
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    seen.add(iOptions);
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    seen.add(iOptions);
    data.remove(key);
  }
}

void _expectFirstUnlock(List<IOSOptions?> seen) {
  expect(seen, isNotEmpty);
  for (final o in seen) {
    expect(o, isNotNull);
    expect(
      o!.toMap()['accessibility'],
      KeychainAccessibility.first_unlock.name,
    );
  }
}

void main() {
  test('write then read round-trips key and device id', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    expect(await store.read(), isNull);
    expect(await store.deviceId(), isNull);
    await store.write('the-key', 'dev-9');
    expect(fake.data, {
      'omni_auto_key': 'the-key',
      'omni_auto_key_device': 'dev-9',
    });
    expect(await store.read(), 'the-key');
    expect(await store.deviceId(), 'dev-9');
  });

  test('delete removes both entries', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    await store.write('k', 'd');
    await store.delete();
    expect(fake.data, isEmpty);
    expect(await store.read(), isNull);
  });

  test('write uses first_unlock accessibility', () async {
    final fake = _FakeSecure();
    await AutoKeyStore(storage: fake).write('k', 'd');
    _expectFirstUnlock(fake.seen);
  });

  test('read, deviceId and delete use first_unlock accessibility', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    await store.read();
    await store.deviceId();
    await store.delete();
    expect(fake.seen.length, 4); // read, deviceId, delete x2
    _expectFirstUnlock(fake.seen);
  });

  test('a keychain failure on read is swallowed (locked phone)', () async {
    final store = AutoKeyStore(storage: _ThrowingSecure());
    expect(await store.read(), isNull);
    expect(await store.deviceId(), isNull);
  });
}

class _ThrowingSecure extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('keychain locked');
}
