import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// /me answers whatever [onMe] says; nothing touches the network.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.onMe)
      : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Future<Map<String, dynamic>> Function() onMe;

  @override
  Future<Map<String, dynamic>> me() => onMe();
}

/// The `employee` block of /login and /me. A null argument leaves the key
/// out, as a connector older than 2.65.0 does.
Map<String, dynamic> _employee({
  Object? tracked,
  Object? access,
  Object? source,
  Object? sig,
  String? department,
}) =>
    {
      'id': 6,
      'name': 'Mei Lin Ong',
      'department_name': ?department,
      'attendance_tracked': ?tracked,
      'overview_access': ?access,
      'team_leave_source': ?source,
      'team_scope_sig': ?sig,
    };

Map<String, dynamic> _login({
  Object? tracked,
  Object? access,
  Object? source,
  Object? sig,
}) =>
    {
      'success': true,
      'access_token': 'tok-A',
      'expires_at': '2099-01-01 00:00:00',
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'meilin', 'name': 'Mei Lin Ong'},
      'employee': _employee(
          tracked: tracked, access: access, source: source, sig: sig),
    };

Map<String, dynamic> _me({
  Object? tracked,
  Object? access,
  Object? source,
  Object? sig,
  String? department,
}) =>
    {
      'success': true,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'meilin', 'name': 'Mei Lin Ong'},
      'employee': _employee(
        tracked: tracked,
        access: access,
        source: source,
        sig: sig,
        department: department,
      ),
    };

/// Sets the SaaS plan features the getters read.
Future<void> _features(SessionService s,
        {required bool attendance, required bool timeOff}) =>
    s.saveCompany(
      saasUrl: 'https://saas.test',
      companyCode: 'ACME',
      clientUrl: 'https://acme.test',
      clientDb: 'acme',
      features: {'attendance': attendance, 'time_off': timeOff},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a fresh session reads the defaults', () {
    final s = SessionService();
    expect(s.attendanceTracked, isFalse);
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.homeView, HomeView.myDay);
    expect(s.teamLeaveEnabled, isFalse);
    expect(s.teamScopeSig, '');
    // No server signature: grant / setting / department / company.
    expect(s.teamCacheSignature, 'none/off//');
  });

  test('a /login body with the keys sets all three flags', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: true, access: 'department', source: 'approver'));
    expect(s.attendanceTracked, isTrue);
    expect(s.overviewAccess, 'department');
    expect(s.teamLeaveSource, 'approver');
    expect(s.teamCacheSignature, 'department/approver//');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('attendance_tracked'), isTrue);
    expect(prefs.getString('overview_access'), 'department');
    expect(prefs.getString('team_leave_source'), 'approver');
  });

  test('a /me update changes the flags and notifies', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: false, access: 'none', source: 'department'));
    var notified = 0;
    s.addListener(() => notified++);

    final ok = await s.refreshMeWith(_FakeApi(
        () async => _me(tracked: true, access: 'company', source: 'off')));
    expect(ok, isTrue);
    expect(s.attendanceTracked, isTrue);
    expect(s.overviewAccess, 'company');
    expect(s.teamLeaveSource, 'off');
    expect(notified, greaterThan(0));
  });

  test('missing keys (connector before 2.65.0, or rolled back) reset to the '
      'defaults', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: true, access: 'company', source: 'department'));
    expect(s.homeView, HomeView.dual);

    final ok = await s.refreshMeWith(_FakeApi(() async => _me()));
    expect(ok, isTrue);
    expect(s.attendanceTracked, isFalse);
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.homeView, HomeView.myDay);
    expect(s.teamLeaveEnabled, isFalse);

    await s.saveLoginResponse(_login());
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
  });

  test('an unknown or malformed value reads as the default', () async {
    final s = SessionService();
    for (final (access, source, tracked) in <(Object?, Object?, Object?)>[
      ('manager', 'division', 'yes'),
      (5, true, 1),
      ('', '', null),
      ('COMPANY', 'Department', false),
    ]) {
      await s.refreshMeWith(_FakeApi(
          () async => _me(tracked: tracked, access: access, source: source)));
      expect(s.overviewAccess, 'none', reason: '$access');
      expect(s.teamLeaveSource, 'off', reason: '$source');
      expect(s.attendanceTracked, isFalse, reason: '$tracked');
    }
    // The stored value is the default too, not the odd one.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('overview_access'), 'none');
    expect(prefs.getString('team_leave_source'), 'off');
  });

  test('homeView truth table (access × tracked × attendance × time off)',
      () async {
    // (overview_access, attendance_tracked, feature attendance,
    //  feature time_off) → expected Home.
    const rows = <(String, bool, bool, bool, HomeView)>[
      ('none', false, true, true, HomeView.myDay),
      ('none', true, true, true, HomeView.myDay),
      ('department', false, true, true, HomeView.overview),
      ('department', true, true, true, HomeView.dual),
      // Attendance without Time Off: the overview (Who's out hidden, T8).
      ('approvees', false, true, false, HomeView.overview),
      ('approvees', true, true, false, HomeView.dual),
      // Team overview is part of Attendance (A-L24): without it, My day
      // (attendance pane locked), whatever Time Off is.
      ('company', false, false, true, HomeView.myDay),
      ('company', true, false, true, HomeView.myDay),
      ('department', false, false, true, HomeView.myDay),
      ('company', false, false, false, HomeView.myDay),
      ('department', true, false, false, HomeView.myDay),
    ];
    for (final (access, tracked, attendance, timeOff, expected) in rows) {
      SharedPreferences.setMockInitialValues({});
      final s = SessionService();
      await _features(s, attendance: attendance, timeOff: timeOff);
      await s.refreshMeWith(_FakeApi(() async =>
          _me(tracked: tracked, access: access, source: 'department')));
      expect(s.homeView, expected,
          reason: 'access=$access tracked=$tracked '
              'attendance=$attendance timeOff=$timeOff');
    }
  });

  test('teamLeaveEnabled truth table (source × time off)', () async {
    const rows = <(String?, bool, bool)>[
      ('department', true, true),
      ('approver', true, true),
      ('off', true, false),
      ('department', false, false),
      ('approver', false, false),
      (null, true, false), // older connector: no key
    ];
    for (final (source, timeOff, expected) in rows) {
      SharedPreferences.setMockInitialValues({});
      final s = SessionService();
      await _features(s, attendance: true, timeOff: timeOff);
      await s.refreshMeWith(
          _FakeApi(() async => _me(access: 'none', source: source)));
      expect(s.teamLeaveEnabled, expected,
          reason: 'source=$source timeOff=$timeOff');
    }
  });

  test('the flags are persisted and loaded back', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: true, access: 'approvees', source: 'approver'));

    final again = SessionService();
    await again.load();
    expect(again.attendanceTracked, isTrue);
    expect(again.overviewAccess, 'approvees');
    expect(again.teamLeaveSource, 'approver');
    expect(again.teamCacheSignature, 'approvees/approver//');
  });

  group('team_scope_sig (K1, A-L14)', () {
    const sigA = '3f9a0c1d2e4b5a69';
    const sigB = '0123456789abcdef';

    test('a valid signature is stored, loaded back and used as the cache '
        'signature', () async {
      final s = SessionService();
      await s.saveLoginResponse(
          _login(tracked: true, access: 'company', source: 'department',
              sig: sigA));
      expect(s.teamScopeSig, sigA);
      expect(s.teamCacheSignature, sigA);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('team_scope_sig'), sigA);

      final again = SessionService();
      await again.load();
      expect(again.teamScopeSig, sigA);
      expect(again.teamCacheSignature, sigA);
    });

    test('an approver change arrives as a new signature through /me and '
        'notifies', () async {
      final s = SessionService();
      await s.saveLoginResponse(
          _login(access: 'approvees', source: 'approver', sig: sigA));
      var notified = 0;
      s.addListener(() => notified++);
      // Same grant and setting; only the people approved changed.
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'approvees', source: 'approver', sig: sigB)));
      expect(s.teamCacheSignature, sigB);
      expect(notified, greaterThan(0));
    });

    test('without a signature, a department transfer through /me changes '
        'the fallback signature', () async {
      final s = SessionService();
      await s.saveLoginResponse(_login(access: 'department', source: 'department'));
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'department', source: 'department',
              department: 'Marketing')));
      final before = s.teamCacheSignature;
      expect(before, 'department/department/Marketing/');
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'department', source: 'department',
              department: 'Fabric')));
      expect(s.teamCacheSignature, 'department/department/Fabric/');
      expect(s.teamCacheSignature, isNot(before));
    });

    test('a malformed or missing signature reads as none; a /me without it '
        'drops the stored one', () async {
      final s = SessionService();
      for (final bad in <Object?>[
        'XYZ',
        '3F9A0C1D2E4B5A69', // upper case
        '3f9a0c1d2e4b5a6', // 15 characters
        42,
        true,
      ]) {
        await s.refreshMeWith(_FakeApi(() async =>
            _me(access: 'company', source: 'department', sig: bad)));
        expect(s.teamScopeSig, '', reason: '$bad');
        expect(s.teamCacheSignature, 'company/department//', reason: '$bad');
      }
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'company', source: 'department', sig: sigA)));
      expect(s.teamScopeSig, sigA);
      await s.refreshMeWith(
          _FakeApi(() async => _me(access: 'company', source: 'department')));
      expect(s.teamScopeSig, '');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('team_scope_sig'), '');
    });

    test('load() ignores a malformed stored signature', () async {
      SharedPreferences.setMockInitialValues({
        'overview_access': 'company',
        'team_leave_source': 'department',
        'team_scope_sig': 'not-a-signature',
      });
      final s = SessionService();
      await s.load();
      expect(s.teamScopeSig, '');
    });

    test('clearSession removes the signature', () async {
      final s = SessionService();
      await s.saveLoginResponse(
          _login(access: 'company', source: 'department', sig: sigA));
      await s.clearSession();
      expect(s.teamScopeSig, '');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('team_scope_sig'), isFalse);
    });
  });

  test('load() reads an unknown stored value as the default', () async {
    SharedPreferences.setMockInitialValues({
      'overview_access': 'everyone',
      'team_leave_source': 'division',
      'attendance_tracked': true,
    });
    final s = SessionService();
    await s.load();
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.attendanceTracked, isTrue);
  });

  test('clearSession resets the flags and removes the stored keys', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: true, access: 'company', source: 'department'));
    await s.clearSession();
    expect(s.attendanceTracked, isFalse);
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.homeView, HomeView.myDay);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('attendance_tracked'), isFalse);
    expect(prefs.containsKey('overview_access'), isFalse);
    expect(prefs.containsKey('team_leave_source'), isFalse);
  });

  test('logout resets the flags too', () async {
    final s = SessionService();
    await s.saveLoginResponse(
        _login(tracked: true, access: 'company', source: 'department'));
    await s.logout();
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.attendanceTracked, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('overview_access'), isFalse);
  });

  test('a /me answer that lands after a sign-out is dropped: the next '
      'session never gets the old grant', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok-A'});
    SharedPreferences.setMockInitialValues({
      'company_code': 'ACME',
      'client_url': 'https://acme.test',
      'client_db': 'acme',
    });
    final s = SessionService();
    await s.load();
    expect(s.isLoggedIn, isTrue);
    final gate = Completer<void>();
    final pending = s.refreshMeWith(_FakeApi(() async {
      await gate.future;
      return _me(tracked: true, access: 'company', source: 'department');
    }));
    await s.clearSession();
    gate.complete();
    expect(await pending, isFalse);
    expect(s.overviewAccess, 'none');
    expect(s.teamLeaveSource, 'off');
    expect(s.attendanceTracked, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('overview_access'), isFalse);
  });

  test('a /me answer that lands after another sign-in is dropped: the new '
      'user never gets the old user\'s grant', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok-A'});
    SharedPreferences.setMockInitialValues({
      'company_code': 'ACME',
      'client_url': 'https://acme.test',
      'client_db': 'acme',
    });
    final s = SessionService();
    await s.load();
    final gate = Completer<void>();
    final pending = s.refreshMeWith(_FakeApi(() async {
      await gate.future;
      return _me(tracked: true, access: 'company', source: 'department');
    }));
    await s.saveLoginResponse({
      'access_token': 'tok-B',
      'user': {'id': 2, 'login': 'budi', 'name': 'Budi'},
      'employee': {'id': 2, 'name': 'Budi'},
    });
    gate.complete();
    expect(await pending, isFalse);
    expect(s.overviewAccess, 'none');
    expect(s.employeeName, 'Budi');
  });
}
