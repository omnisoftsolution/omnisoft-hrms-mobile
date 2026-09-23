import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'fake_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('enableWithRefreshToken stores token, no password', () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    expect(
        await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'R'),
        isTrue);
    expect(svc.isEnabled, isTrue);
    expect(svc.usesRefreshToken, isTrue);
    const s = FlutterSecureStorage();
    expect(await s.read(key: 'biometric_refresh_token'), 'R');
    expect(await s.read(key: 'biometric_password'), isNull);
    final res = await svc.authenticateAndRetrieve();
    expect(res.outcome, BiometricAuthOutcome.success);
    expect(res.credential!.refreshToken, 'R');
    expect(res.credential!.login, 'a@b.c');
  });

  test('legacy password mode migrates to refresh token', () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    await svc.enable(login: 'a@b.c', password: 'pw');
    expect(svc.usesRefreshToken, isFalse);
    await svc.replacePasswordWithRefreshToken('R2');
    expect(svc.usesRefreshToken, isTrue);
    const s = FlutterSecureStorage();
    expect(await s.read(key: 'biometric_password'), isNull);
    expect(await s.read(key: 'biometric_refresh_token'), 'R2');
    final res = await svc.authenticateAndRetrieve();
    expect(res.credential!.refreshToken, 'R2');
    expect(res.credential!.password, isNull);
  });

  test('updateRefreshToken only when enabled in refresh mode', () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    await svc.updateRefreshToken('X'); // not enabled → no-op
    expect(await const FlutterSecureStorage().read(key: 'biometric_refresh_token'),
        isNull);
    await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'R');
    await svc.updateRefreshToken('R3');
    expect(await const FlutterSecureStorage().read(key: 'biometric_refresh_token'),
        'R3');
  });

  test('disable clears both secrets', () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'R');
    await svc.disable();
    const s = FlutterSecureStorage();
    expect(await s.read(key: 'biometric_refresh_token'), isNull);
    expect(svc.usesRefreshToken, isFalse);
  });

  test('re-enabling with password clears a stale refresh token', () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'R');
    await svc.enable(login: 'a@b.c', password: 'pw');
    expect(svc.usesRefreshToken, isFalse);
    const s = FlutterSecureStorage();
    expect(await s.read(key: 'biometric_refresh_token'), isNull);
    expect(await s.read(key: 'biometric_password'), 'pw');
    final res = await svc.authenticateAndRetrieve();
    expect(res.credential!.password, 'pw');
    expect(res.credential!.refreshToken, isNull);
  });

  test('enableWithRefreshToken rejects an empty token without changing state',
      () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    final ok =
        await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: '');
    expect(ok, isFalse);
    expect(svc.isEnabled, isFalse);
    expect(svc.usesRefreshToken, isFalse);
    const s = FlutterSecureStorage();
    expect(await s.read(key: 'biometric_refresh_token'), isNull);
  });

  test('updateRefreshToken is a no-op when enabled in legacy password mode',
      () async {
    final svc = BiometricAuthService(
        gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
    await svc.load();
    await svc.enable(login: 'a@b.c', password: 'pw');
    await svc.updateRefreshToken('X');
    expect(
        await const FlutterSecureStorage().read(key: 'biometric_refresh_token'),
        isNull);
  });

  group('adoptRefreshToken', () {
    const s = FlutterSecureStorage();

    test('is a no-op when biometric login is not enabled', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      expect(await svc.adoptRefreshToken('R', login: 'a@b.c'), isFalse);
      expect(svc.isEnabled, isFalse);
      expect(await s.read(key: 'biometric_refresh_token'), isNull);
    });

    test('replaces the stored token in refresh mode', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'OLD');
      expect(await svc.adoptRefreshToken('NEW', login: 'a@b.c'), isTrue);
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
      expect(svc.usesRefreshToken, isTrue);
    });

    test('migrates a legacy password credential to the token', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      expect(await svc.adoptRefreshToken('NEW', login: 'a@b.c'), isTrue);
      expect(svc.usesRefreshToken, isTrue);
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
      expect(await s.read(key: 'biometric_password'), isNull);
    });

    test('ignores an empty token', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'OLD');
      expect(await svc.adoptRefreshToken('', login: 'a@b.c'), isFalse);
      expect(await s.read(key: 'biometric_refresh_token'), 'OLD');
    });

    test('a different login leaves a password-mode credential untouched',
        () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enable(login: 'a@b.c', password: 'pw');
      expect(await svc.adoptRefreshToken('NEW', login: 'other@b.c'), isFalse);
      expect(svc.usesRefreshToken, isFalse);
      expect(await s.read(key: 'biometric_password'), 'pw');
      expect(await s.read(key: 'biometric_refresh_token'), isNull);
      expect(await s.read(key: 'biometric_login'), 'a@b.c');
    });

    test('a different login leaves the old refresh token in place', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'OLD');
      expect(await svc.adoptRefreshToken('NEW', login: 'other@b.c'), isFalse);
      expect(await s.read(key: 'biometric_refresh_token'), 'OLD');
      expect(await s.read(key: 'biometric_login'), 'a@b.c');
      expect(svc.usesRefreshToken, isTrue);
    });

    test('login match ignores case and surrounding whitespace', () async {
      final svc = BiometricAuthService(
          gate: FakeBiometricGate(nextOutcome: BiometricAuthOutcome.success));
      await svc.load();
      await svc.enable(login: 'Say.Puay@Example.com', password: 'pw');
      expect(
          await svc.adoptRefreshToken('NEW', login: '  say.puay@EXAMPLE.com '),
          isTrue);
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
      expect(await s.read(key: 'biometric_password'), isNull);
    });
  });
}
