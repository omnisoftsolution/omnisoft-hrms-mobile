import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

/// Records the args it received and returns/throws whatever [onRefresh]
/// says, so refreshAccessTokenWith can be tested without real HTTP.
class _FakeApi extends OmniMobileApi {
  _FakeApi({this.onRefresh})
      : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

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
    final ok = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(ok, isTrue);
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
    final ok = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(ok, isFalse);
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
    final ok = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(ok, isFalse);
    expect(s.refreshToken, 'R');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'R');
  });

  test('refreshAccessTokenWith with no stored refresh token returns false '
      'without calling the api', () async {
    final s = SessionService();
    await s.load();
    final fake = _FakeApi();
    final ok = await s.refreshAccessTokenWith(fake, 'device-1');
    expect(ok, isFalse);
    expect(fake.callCount, 0);
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
