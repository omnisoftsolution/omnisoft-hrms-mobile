import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Map<String, dynamic> omniRes() => {
    'success': true, 'access_token': 'A', 'expires_at': '2026-10-13 10:00:00',
    'refresh_token': 'R', 'refresh_expires_at': '2027-09-13 10:00:00', 'auth_source': 'omni',
    'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'}, 'employee': {'id': 6, 'name': 'A'},
  };

  test('omni login stores refresh token and auth source', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    expect(s.refreshToken, 'R');
    expect(s.authSource, 'omni');
    expect(s.supportsIdentity, isTrue);
    expect(s.refreshExpiresAt, DateTime.parse('2027-09-13 10:00:00'));
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'R');
  });

  test('odoo fallback login has auth source but no refresh token', () async {
    final s = SessionService();
    final res = omniRes()..remove('refresh_token')..remove('refresh_expires_at')..['auth_source'] = 'odoo';
    await s.saveLoginResponse(res);
    expect(s.refreshToken, ''); expect(s.authSource, 'odoo'); expect(s.supportsIdentity, isTrue);
  });

  test('legacy connector response leaves supportsIdentity false', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes()..remove('auth_source')..remove('refresh_token'));
    expect(s.supportsIdentity, isFalse);
  });

  test('clearSession wipes refresh token', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    await s.clearSession();
    expect(s.refreshToken, '');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
  });

  test('load restores refresh token and auth source', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final s2 = SessionService();
    await s2.load();
    expect(s2.refreshToken, 'R'); expect(s2.authSource, 'omni');
  });
}
