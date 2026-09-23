import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

/// Records the args it received and returns/throws whatever [onRefresh]
/// says, so refreshAccessTokenWith can be tested without real HTTP.
class _FakeApi extends OmniMobileApi {
  _FakeApi({this.onRefresh, this.onMe})
      : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Future<Map<String, dynamic>> Function()? onMe;

  @override
  Future<Map<String, dynamic>> me() => onMe!();

  final Future<Map<String, dynamic>> Function({
    required String refreshToken,
    required String deviceId,
  })? onRefresh;

  String? lastRefreshToken;
  String? lastDeviceId;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
    required String deviceId,
  }) {
    callCount++;
    lastRefreshToken = refreshToken;
    lastDeviceId = deviceId;
    return onRefresh!(refreshToken: refreshToken, deviceId: deviceId);
  }
}

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

  test('refreshAccessTokenWith success updates the access token and keeps '
      'the refresh token', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async => {
        'success': true,
        'access_token': 'NEW-A',
        'expires_at': '2026-12-01 00:00:00',
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(out, RefreshOutcome.ok);
    expect(s.accessToken, 'NEW-A');
    expect(s.expiresAt, DateTime.parse('2026-12-01 00:00:00'));
    expect(s.refreshToken, 'R');
    expect(fake.lastRefreshToken, 'R');
    expect(fake.lastDeviceId, 'device-1');
  });

  test('refreshAccessTokenWith forgets the refresh token on refresh_invalid',
      () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async {
        throw ApiException('refresh_invalid');
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(out, RefreshOutcome.invalid);
    expect(s.refreshToken, '');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'),
        isNull);
  });

  test('refreshAccessTokenWith preserves the refresh token on other failures',
      () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async {
        throw ApiException('network_error');
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(out, RefreshOutcome.failed);
    expect(s.refreshToken, 'R');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'R');
  });

  test('refreshAccessTokenWith with no refresh token at all returns invalid '
      'without calling the api', () async {
    final s = SessionService();
    await s.load();
    final fake = _FakeApi();
    final out = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(out, RefreshOutcome.invalid);
    expect(fake.callCount, 0);
  });

  test('refreshAccessTokenWith uses the override token (Face ID) and '
      'persists it as the session refresh token on ok', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    await s.clearSession(); // signed out: session token and profile wiped
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async => {
        'success': true,
        'access_token': 'NEW-A',
        'expires_at': '2026-12-01 00:00:00',
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1',
        refreshToken: 'FACE');
    expect(out, RefreshOutcome.ok);
    expect(fake.lastRefreshToken, 'FACE');
    expect(s.accessToken, 'NEW-A');
    expect(s.refreshToken, 'FACE');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'),
        'FACE');
  });

  test('refreshAccessTokenWith returns failed on network_error and keeps '
      'the session token even with an override', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async {
        throw ApiException('network_error');
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1',
        refreshToken: 'FACE');
    expect(out, RefreshOutcome.failed);
    expect(s.refreshToken, 'R');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'R');
  });

  test('refreshAccessTokenWith returns invalid with an override token and '
      'clears the session token too', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async {
        throw ApiException('refresh_invalid');
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1',
        refreshToken: 'FACE');
    expect(out, RefreshOutcome.invalid);
    expect(s.refreshToken, '');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'),
        isNull);
  });

  test('refreshAccessTokenWith returns failed on a non-ApiException error',
      () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(
      onRefresh: ({required refreshToken, required deviceId}) async {
        throw StateError('boom');
      },
    );
    final out = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(out, RefreshOutcome.failed);
    expect(s.refreshToken, 'R');
  });

  test('refreshMeWith repopulates employee fields and auth source from /me',
      () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    await s.clearSession();
    final fake = _FakeApi(
      onMe: () async => {
        'success': true,
        'auth_source': 'omni',
        'device': {'label': 'iPhone · iPhone15,2'},
        'user': {'id': 9, 'login': 'agus@maxhill.test', 'name': 'Agus'},
        'employee': {
          'id': 6,
          'name': 'Agus Salim',
          'job_title': 'Operator',
          'department_name': 'Production',
        },
      },
    );
    final ok = await s.refreshMeWith(fake);
    expect(ok, isTrue);
    expect(s.userId, 9);
    expect(s.userLogin, 'agus@maxhill.test');
    // Persisted, so a restart keeps them.
    final s2 = SessionService();
    await s2.load();
    expect(s2.userId, 9);
    expect(s2.userLogin, 'agus@maxhill.test');
    expect(s.userName, 'Agus');
    expect(s.employeeId, 6);
    expect(s.employeeName, 'Agus Salim');
    expect(s.employeeJobTitle, 'Operator');
    expect(s.employeeDepartment, 'Production');
    expect(s.authSource, 'omni');
    expect(s.deviceLabel, 'iPhone · iPhone15,2');
  });

  test('refreshMeWith keeps userId/userLogin when /me omits user '
      '(older connector)', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes()); // userId 9, login a@b.c
    final fake = _FakeApi(
      onMe: () async => {
        'success': true,
        'employee': {'id': 6, 'name': 'A'},
      },
    );
    expect(await s.refreshMeWith(fake), isTrue);
    expect(s.userId, 9);
    expect(s.userLogin, 'a@b.c');
  });

  test('setUserLogin seeds and persists the login', () async {
    final s = SessionService();
    await s.load();
    await s.setUserLogin('face@b.c');
    expect(s.userLogin, 'face@b.c');
    final s2 = SessionService();
    await s2.load();
    expect(s2.userLogin, 'face@b.c');
  });

  test('refreshMeWith returns false and swallows errors', () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes());
    final fake = _FakeApi(onMe: () async => throw ApiException('network_error'));
    expect(await s.refreshMeWith(fake), isFalse);
    expect(s.employeeName, 'A'); // cached fields untouched
  });

  test('updateFromMe sets authSource and deviceLabel when present', () async {
    final s = SessionService();
    await s.load();
    s.updateFromMe({
      'auth_source': 'omni',
      'device': {'label': 'Pixel'},
    });
    expect(s.authSource, 'omni');
    expect(s.deviceLabel, 'Pixel');
    expect(s.supportsIdentity, isTrue);
  });

  test('updateFromMe is a no-op when auth_source is absent (legacy connector)',
      () async {
    final s = SessionService();
    await s.saveLoginResponse(omniRes()); // authSource == 'omni'
    s.updateFromMe({
      'user': {'id': 1, 'name': 'A'},
    });
    expect(s.authSource, 'omni');
  });
}
