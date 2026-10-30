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
  test('write then read round-trips key, device id and owner', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    expect(await store.read(), isNull);
    expect(await store.deviceId(), isNull);
    expect(await store.owner(), isNull);
    await store.write('the-key', 'dev-9', owner: 'acme|7');
    expect(fake.data, {
      'omni_auto_key': 'the-key',
      'omni_auto_key_device': 'dev-9',
      'omni_auto_key_owner': 'acme|7',
    });
    expect(await store.read(), 'the-key');
    expect(await store.deviceId(), 'dev-9');
    expect(await store.owner(), 'acme|7');
  });

  test('ownerOf is <db>|<employeeId>', () {
    expect(AutoKeyStore.ownerOf('acme', 7), 'acme|7');
  });

  test('readFor gives the key only to its owner', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    await store.write('k', 'd', owner: 'acme|7');
    expect(await store.readFor('acme', 7), 'k');
    expect(await store.readFor('acme', 8), isNull);
    expect(await store.readFor('other', 7), isNull);

    // A key stored without an owner (or a lost owner write) is no one's.
    fake.data.remove('omni_auto_key_owner');
    expect(await store.readFor('acme', 7), isNull);
  });

  test('delete removes every entry', () async {
    final fake = _FakeSecure();
    final store = AutoKeyStore(storage: fake);
    await store.write('k', 'd', owner: 'acme|7');
    await store.delete();
    expect(fake.data, isEmpty);
    expect(await store.read(), isNull);
  });

  test('write uses first_unlock accessibility', () async {
    final fake = _FakeSecure();
    await AutoKeyStore(storage: fake).write('k', 'd', owner: 'acme|7');
    expect(fake.seen.length, 3);
    _expectFirstUnlock(fake.seen);
  });

  test(
    'read, deviceId, owner and delete use first_unlock accessibility',
    () async {
      final fake = _FakeSecure();
      final store = AutoKeyStore(storage: fake);
      await store.read();
      await store.deviceId();
      await store.owner();
      await store.delete();
      expect(fake.seen.length, 6); // read, deviceId, owner, delete x3
      _expectFirstUnlock(fake.seen);
    },
  );

  test('a keychain failure on read is swallowed (locked phone)', () async {
    final store = AutoKeyStore(storage: _ThrowingSecure());
    expect(await store.read(), isNull);
    expect(await store.deviceId(), isNull);
    expect(await store.owner(), isNull);
    expect(await store.readFor('acme', 7), isNull);
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
