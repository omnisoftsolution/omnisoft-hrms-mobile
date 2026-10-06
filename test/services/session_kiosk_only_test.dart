import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

class _FakeApi extends OmniMobileApi {
  _FakeApi(this.onMe)
      : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Future<Map<String, dynamic>> Function() onMe;

  @override
  Future<Map<String, dynamic>> me() => onMe();
}

Map<String, dynamic> _login({bool? kioskOnly}) => {
      'success': true,
      'access_token': 'A',
      'expires_at': '2026-10-13 10:00:00',
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {
        'id': 6,
        'name': 'A',
        'attendance_kiosk_only': ?kioskOnly,
      },
    };

Map<String, dynamic> _me({bool? kioskOnly}) => {
      'success': true,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {
        'id': 6,
        'name': 'A',
        'attendance_kiosk_only': ?kioskOnly,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('defaults to false', () {
    expect(SessionService().attendanceKioskOnly, isFalse);
  });

  test('login response sets the flag', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(kioskOnly: true));
    expect(s.attendanceKioskOnly, isTrue);
  });

  test('a login response without the key reads as false', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(kioskOnly: true));
    await s.saveLoginResponse(_login());
    expect(s.attendanceKioskOnly, isFalse);
  });

  test('the flag is persisted and loaded back', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(kioskOnly: true));
    final again = SessionService();
    await again.load();
    expect(again.attendanceKioskOnly, isTrue);
  });

  test('/me refresh turns the flag on, off, and off when missing', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login());
    var notified = 0;
    s.addListener(() => notified++);

    expect(await s.refreshMeWith(_FakeApi(() async => _me(kioskOnly: true))),
        isTrue);
    expect(s.attendanceKioskOnly, isTrue);
    expect(notified, greaterThan(0));

    await s.refreshMeWith(_FakeApi(() async => _me(kioskOnly: false)));
    expect(s.attendanceKioskOnly, isFalse);

    await s.refreshMeWith(_FakeApi(() async => _me(kioskOnly: true)));
    await s.refreshMeWith(_FakeApi(() async => _me()));
    expect(s.attendanceKioskOnly, isFalse);
  });

  test('a failed /me keeps the flag', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(kioskOnly: true));
    expect(
        await s.refreshMeWith(
            _FakeApi(() async => throw ApiException('network_error'))),
        isFalse);
    expect(s.attendanceKioskOnly, isTrue);
  });

  test('clearSession resets the flag', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(kioskOnly: true));
    await s.clearSession();
    expect(s.attendanceKioskOnly, isFalse);
    final again = SessionService();
    await again.load();
    expect(again.attendanceKioskOnly, isFalse);
  });
}
