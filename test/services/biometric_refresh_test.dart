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
}
