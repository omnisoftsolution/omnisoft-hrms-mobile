import 'dart:convert';

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

const _kPref = 'employee_auto_attendance';

Map<String, dynamic> _block({String trigger = 'location', int area = 150}) => {
      'trigger': trigger,
      'dwell_min': 5,
      'exit_min': 10,
      'office': {
        'name': 'NOVAWORKS HQ',
        'latitude': 1.2894,
        'longitude': 103.847,
        'area_m': area,
      },
      'wifi_required': false,
    };

Map<String, dynamic> _login({Object? auto}) => {
      'success': true,
      'access_token': 'A',
      'expires_at': '2026-10-13 10:00:00',
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {
        'id': 6,
        'name': 'A',
        'auto_attendance': ?auto,
      },
    };

Map<String, dynamic> _me({Object? auto}) => {
      'success': true,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {
        'id': 6,
        'name': 'A',
        'auto_attendance': ?auto,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('defaults to null', () {
    expect(SessionService().autoAttendance, isNull);
  });

  test('login stores the block; me without the key clears it; '
      'clearSession removes it', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(auto: _block()));
    expect(s.autoAttendance, isNotNull);
    expect(s.autoAttendance!.office.name, 'NOVAWORKS HQ');
    expect(s.autoAttendance!.office.areaM, 150);

    // Persisted and loaded back by a fresh service (background isolate).
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPref)!;
    expect((jsonDecode(raw) as Map)['office'], isA<Map>());
    final again = SessionService();
    await again.load();
    expect(again.autoAttendance?.signature, s.autoAttendance!.signature);

    // /me with a changed radius updates it.
    expect(
        await s.refreshMeWith(
            _FakeApi(() async => _me(auto: _block(area: 200)))),
        isTrue);
    expect(s.autoAttendance!.office.areaM, 200);

    // /me without the key (older connector) clears it.
    expect(await s.refreshMeWith(_FakeApi(() async => _me())), isTrue);
    expect(s.autoAttendance, isNull);
    expect(prefs.containsKey(_kPref), isFalse);

    // clearSession removes it.
    await s.refreshMeWith(_FakeApi(() async => _me(auto: _block())));
    expect(s.autoAttendance, isNotNull);
    await s.clearSession();
    expect(s.autoAttendance, isNull);
    expect(prefs.containsKey(_kPref), isFalse);
    final loaded = SessionService();
    await loaded.load();
    expect(loaded.autoAttendance, isNull);
  });

  test('a null or malformed block reads as off', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(auto: _block()));
    await s.saveLoginResponse({
      ..._login(),
      'employee': {'id': 6, 'name': 'A', 'auto_attendance': null},
    });
    expect(s.autoAttendance, isNull);
    await s.saveLoginResponse(_login(auto: _block()));
    await s.saveLoginResponse(_login(auto: {'trigger': 'location'}));
    expect(s.autoAttendance, isNull);
  });

  test('a failed /me keeps the block', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login(auto: _block()));
    expect(
        await s.refreshMeWith(
            _FakeApi(() async => throw ApiException('network_error'))),
        isFalse);
    expect(s.autoAttendance, isNotNull);
  });

  test('notifies listeners when the block changes', () async {
    final s = SessionService();
    await s.saveLoginResponse(_login());
    var n = 0;
    s.addListener(() => n++);
    await s.refreshMeWith(_FakeApi(() async => _me(auto: _block())));
    expect(n, greaterThan(0));
  });
}
