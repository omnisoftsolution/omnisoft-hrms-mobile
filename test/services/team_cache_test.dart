import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/team_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The storage under SharedPreferences, to hold one write (A-L23). It comes
// with shared_preferences; the app does not list it itself.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The platform storage of the A-L23 test: it runs one operation at a
/// time, in the order sent (as the platform does), and the write of
/// [holdKey] waits for [release].
class _HeldStore extends InMemorySharedPreferencesStore {
  _HeldStore() : super.empty();

  /// The storage key (`flutter.` + the prefs key) whose write is held.
  String? holdKey;
  final release = Completer<void>();

  /// True once the held write has reached storage and waits.
  bool holding = false;

  /// Every removal, in the order it was sent to storage.
  final removals = <String>[];

  Future<void> _last = Future<void>.value();

  Future<bool> _inOrder(Future<bool> Function() op) {
    final run = _last.then((_) => op());
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _inOrder(() async {
        if (key == holdKey) {
          holding = true;
          await release.future;
        }
        return super.setValue(valueType, key, value);
      });

  @override
  Future<bool> remove(String key) {
    removals.add(key);
    return _inOrder(() => super.remove(key));
  }
}

class _FakeApi extends OmniMobileApi {
  _FakeApi(this.onMe)
      : super(baseUrl: 'https://acme.test', db: 'acme', token: '');

  final Future<Map<String, dynamic>> Function() onMe;

  @override
  Future<Map<String, dynamic>> me() => onMe();
}

/// A signed-in ACME session for employee [employeeId] with the given
/// grant / setting / scope signature (Task 1 flags), no network.
Future<SessionService> _session({
  int employeeId = 6,
  String access = 'company',
  String source = 'department',
  String? sig,
}) async {
  final s = SessionService();
  await s.saveCompany(
    saasUrl: 'https://saas.test',
    companyCode: 'ACME',
    clientUrl: 'https://acme.test',
    clientDb: 'acme',
  );
  await s.saveLoginResponse(_loginBody(employeeId, access, source, sig));
  return s;
}

Map<String, dynamic> _loginBody(
  int employeeId,
  String access,
  String source,
  String? sig,
) =>
    {
      'access_token': 'tok-$employeeId',
      'user': {'id': employeeId + 100, 'login': 'u$employeeId', 'name': 'U'},
      'employee': {
        'id': employeeId,
        'name': 'Employee $employeeId',
        'overview_access': access,
        'team_leave_source': source,
        'team_scope_sig': ?sig,
      },
    };

/// A /me answer for employee 6.
Map<String, dynamic> _me({
  String access = 'company',
  String source = 'department',
  String? sig,
  String? department,
}) =>
    {
      'success': true,
      'employee': {
        'id': 6,
        'name': 'Employee 6',
        'department_name': ?department,
        'overview_access': access,
        'team_leave_source': source,
        'team_scope_sig': ?sig,
      },
    };

/// A write whose binding is taken right now (no fetch in between).
Future<void> _write(SessionService s, String key, Map<String, dynamic> body) =>
    TeamCache.write(s, key, body, binding: TeamCache.bind(s));

Map<String, dynamic> _body(int n) => {
      'success': true,
      'summary': {'this_week_off': n, 'label': 'Marketing'},
    };

Future<List<String>> _teamKeys() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getKeys().where((k) => k.startsWith('team_v1|')).toList()
    ..sort();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 10, 22, 9, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TeamCache.clock = () => t0;
  });
  tearDown(() => TeamCache.clock = DateTime.now);

  group('keys', () {
    test('the A-L3 format', () async {
      final s = await _session();
      expect(TeamCache.employeePrefix(s), 'team_v1|acme|6|');
      expect(
        TeamCache.key(
          session: s,
          kind: TeamCache.kindOutlook,
          context: 'team',
          view: 'approvees',
          span: '60',
        ),
        'team_v1|acme|6|outlook|team|approvees|-|60',
      );
      expect(TeamCache.outlookKey(s, days: 30),
          'team_v1|acme|6|outlook|team|team|-|30');
      // The server ignores `view` in the overview context.
      expect(
        TeamCache.outlookKey(s,
            days: 90, context: 'overview', view: 'company', departmentId: 5),
        'team_v1|acme|6|outlook|overview|-|5|90',
      );
      expect(TeamCache.overviewKey(s), 'team_v1|acme|6|overview|-|-|-|today');
      expect(TeamCache.overviewKey(s, day: 'yesterday', departmentId: 5),
          'team_v1|acme|6|overview|-|-|5|yesterday');
    });
  });

  group('read / write', () {
    test('round trip keeps the body and the save time', () async {
      final s = await _session();
      final key = TeamCache.outlookKey(s, days: 30);
      await _write(s, key, _body(2));

      final hit = await TeamCache.read(s, key);
      expect(hit, isNotNull);
      final (body, savedAt) = hit!;
      expect(body, _body(2));
      expect(savedAt, t0);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      expect(stored.keys, containsAll(['saved_at', 'signature', 'body']));
      // No server signature: the A-L14 fallback (no department, no company
      // name in this session).
      expect(stored['signature'], 'company/department//');
    });

    test('the server signature is what an entry is stored under', () async {
      final s = await _session(sig: '3f9a0c1d2e4b5a69');
      final key = TeamCache.overviewKey(s);
      await _write(s, key, _body(1));
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      expect(stored['signature'], '3f9a0c1d2e4b5a69');
    });

    test('an absent key reads as null', () async {
      final s = await _session();
      expect(await TeamCache.read(s, TeamCache.overviewKey(s)), isNull);
    });

    test('a signature mismatch is ignored (grant or setting changed)',
        () async {
      final s = await _session(access: 'company', source: 'department');
      final key = TeamCache.overviewKey(s);
      await _write(s, key, _body(1));
      expect(await TeamCache.read(s, key), isNotNull);

      // HR narrows the grant: the /me that says so changes the signature.
      await s.refreshMeWith(
          _FakeApi(() async => _me(access: 'department', source: 'department')));
      expect(s.teamCacheSignature, 'department/department//');
      expect(await TeamCache.read(s, key), isNull);
    });

    test('a department transfer through /me invalidates the entries (A1)',
        () async {
      final s = await _session(access: 'department', source: 'department');
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'department', source: 'department',
              department: 'Marketing')));
      final key = TeamCache.outlookKey(s, days: 30);
      await _write(s, key, _body(1));
      expect(await TeamCache.read(s, key), isNotNull);

      // Same grant, same setting: only the department changed.
      await s.refreshMeWith(_FakeApi(() async =>
          _me(access: 'department', source: 'department',
              department: 'Fabric')));
      expect(await TeamCache.read(s, key), isNull);

      // A connector that sends team_scope_sig: the server signature
      // changes on the transfer, so the entry goes the same way.
      await s.refreshMeWith(_FakeApi(() async => _me(
          access: 'department', source: 'department',
          department: 'Fabric', sig: '1111111111111111')));
      await _write(s, key, _body(2));
      expect(await TeamCache.read(s, key), isNotNull);
      await s.refreshMeWith(_FakeApi(() async => _me(
          access: 'department', source: 'department',
          department: 'Marketing', sig: '2222222222222222')));
      expect(await TeamCache.read(s, key), isNull);
    });

    test('an approver change through /me (new team_scope_sig) invalidates '
        'the entries (A1)', () async {
      final s = await _session(
          access: 'approvees', source: 'approver', sig: '3f9a0c1d2e4b5a69');
      final key = TeamCache.overviewKey(s);
      await _write(s, key, _body(1));
      expect(await TeamCache.read(s, key), isNotNull);
      // Grant and setting unchanged; the people approved changed.
      await s.refreshMeWith(_FakeApi(() async => _me(
          access: 'approvees', source: 'approver', sig: '0123456789abcdef')));
      expect(await TeamCache.read(s, key), isNull);
    });

    test('corrupt JSON and wrong shapes are ignored', () async {
      final s = await _session();
      final prefs = await SharedPreferences.getInstance();
      final key = TeamCache.outlookKey(s, days: 30);
      for (final bad in [
        '{not json',
        '[1, 2]',
        jsonEncode({'signature': 'company/department', 'body': 'x', 'saved_at': '2026-10-22T01:12:00.000Z'}),
        jsonEncode({'signature': 'company/department', 'body': {}, 'saved_at': 'yesterday'}),
        jsonEncode({'body': {}, 'saved_at': '2026-10-22T01:12:00.000Z'}),
      ]) {
        await prefs.setString(key, bad);
        expect(await TeamCache.read(s, key), isNull, reason: bad);
      }
    });

    test("another employee's key is never read", () async {
      final s = await _session(employeeId: 6);
      final prefs = await SharedPreferences.getInstance();
      const other = 'team_v1|acme|7|outlook|team|team|-|30';
      await prefs.setString(
          other,
          jsonEncode({
            'saved_at': t0.toUtc().toIso8601String(),
            'signature': s.teamCacheSignature,
            'body': _body(9),
          }));
      expect(await TeamCache.read(s, other), isNull);
    });

    test('a write for another employee, or while signed out, is dropped',
        () async {
      final s = await _session(employeeId: 6);
      await _write(s, 'team_v1|acme|7|overview|-|-|-|today', _body(1));
      expect(await _teamKeys(), isEmpty);

      final key = TeamCache.overviewKey(s);
      await s.clearSession();
      await _write(s, key, _body(1)); // a fetch that landed late
      expect(await _teamKeys(), isEmpty);
    });

    test('a write that lands while a sign-out runs is dropped', () async {
      final s = await _session();
      final key = TeamCache.overviewKey(s);
      final hook = Completer<void>();
      s.onSessionClearing = () => hook.future;
      final out = s.clearSession(); // waits in the hook: isClearing is true
      await _write(s, key, _body(1));
      hook.complete();
      await out;
      expect(await _teamKeys(), isEmpty);
    });
  });

  group('binding: signature + generation taken before the fetch (A-L15)', () {
    test('clearEmployee and clearAll bump the generation', () async {
      final s = await _session();
      final g0 = TeamCache.generation;
      await TeamCache.clearEmployee(s);
      expect(TeamCache.generation, g0 + 1);
      await TeamCache.clearAll();
      expect(TeamCache.generation, g0 + 2);
      await s.clearSession(); // the session wipe calls clearAll
      expect(TeamCache.generation, g0 + 3);
    });

    test('changes and watch notify at once on every clear (A-L22)', () async {
      final s = await _session();
      var changes = 0;
      var watched = 0;
      void onChange() => changes++;
      void onWatch() => watched++;
      final watch = TeamCache.watch(s);
      TeamCache.changes.addListener(onChange);
      watch.addListener(onWatch);
      addTearDown(() {
        TeamCache.changes.removeListener(onChange);
        watch.removeListener(onWatch);
      });
      final cleared = TeamCache.clearEmployee(s);
      // Synchronously, before the removal runs.
      expect(changes, 1);
      expect(watched, 1);
      await cleared;
      await TeamCache.clearAll();
      expect(changes, 2);
      expect(watched, 2);
      // watch also hears the session: the wipe's clearAll, then the
      // sign-out's own notify.
      await s.clearSession();
      expect(changes, 3);
      expect(watched, greaterThanOrEqualTo(4));
    });

    test('a delayed success after an access-lost clear is dropped', () async {
      final s = await _session();
      final key = TeamCache.overviewKey(s);
      // The request starts under company access…
      final binding = TeamCache.bind(s);
      // …another screen gets not_allowed: clear + /me (department now).
      await TeamCache.clearEmployee(s);
      await s.refreshMeWith(
          _FakeApi(() async => _me(access: 'department', source: 'department')));
      // The old company-wide answer lands last.
      expect(binding.isCurrent(s), isFalse);
      await TeamCache.write(s, key, _body(9), binding: binding);
      expect(await _teamKeys(), isEmpty);
      expect(await TeamCache.read(s, key), isNull);
    });

    test('a delayed success after a clear is dropped even when the signature '
        'did not change', () async {
      final s = await _session();
      final key = TeamCache.outlookKey(s, days: 30);
      final binding = TeamCache.bind(s);
      await TeamCache.clearEmployee(s); // feature_unavailable, say
      expect(s.teamCacheSignature, binding.signature);
      expect(binding.isCurrent(s), isFalse);
      await TeamCache.write(s, key, _body(9), binding: binding);
      expect(await _teamKeys(), isEmpty);
    });

    test('a write taken under the old signature is dropped after a /me '
        'narrowed the grant (no clear in between)', () async {
      final s = await _session(access: 'company');
      final key = TeamCache.overviewKey(s);
      final binding = TeamCache.bind(s);
      await s.refreshMeWith(
          _FakeApi(() async => _me(access: 'department', source: 'department')));
      expect(binding.isCurrent(s), isFalse);
      await TeamCache.write(s, key, _body(9), binding: binding);
      expect(await _teamKeys(), isEmpty);
    });

    test('a delayed success after the same employee signed in again is '
        'dropped', () async {
      final s = await _session(employeeId: 6);
      final key = TeamCache.overviewKey(s);
      final binding = TeamCache.bind(s);
      await s.clearSession();
      await s.saveLoginResponse(
          _loginBody(6, 'company', 'department', null));
      // Same employee, same key, same signature: the generation (the wipe
      // cleared the cache) and the request epoch tell the old request apart.
      expect(TeamCache.overviewKey(s), key);
      expect(s.teamCacheSignature, binding.signature);
      expect(binding.isCurrent(s), isFalse);
      await TeamCache.write(s, key, _body(9), binding: binding);
      expect(await _teamKeys(), isEmpty);

      // A request started in the new sign-in is stored.
      await _write(s, key, _body(1));
      expect((await TeamCache.read(s, key))!.$1, _body(1));
    });

    test('writes and clears run one at a time: a clear called while a write '
        'is on its way wins', () async {
      final s = await _session();
      final key = TeamCache.overviewKey(s);
      final write = _write(s, key, _body(1)); // not awaited yet
      final clear = TeamCache.clearEmployee(s);
      await Future.wait([write, clear]);
      expect(await _teamKeys(), isEmpty);

      // And a write queued after a clear finishes is stored.
      await TeamCache.clearEmployee(s);
      await _write(s, key, _body(2));
      expect(await _teamKeys(), [key]);
    });

    test('an access-lost clear hides the entry from reads before it '
        'notifies, while its removal still waits behind an earlier write '
        '(A-L23, TLP4-F01)', () async {
      final store = _HeldStore();
      SharedPreferencesStorePlatform.instance = store;
      // A failed expect must not leave TeamCache's queue stuck behind the
      // held write for the tests after this one.
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await Future<void>.delayed(Duration.zero);
      });
      final s = await _session();
      final key = TeamCache.overviewKey(s);
      // The overview shows this entry (colleague details).
      await _write(s, key, _body(1));
      expect(await TeamCache.read(s, key), isNotNull);

      // 1. An earlier cache write waits in storage; the queue waits on it.
      final other = TeamCache.outlookKey(s, days: 30);
      store.holdKey = 'flutter.$other';
      final held = _write(s, other, _body(2));
      await Future<void>.delayed(Duration.zero);
      expect(store.holding, isTrue);

      // 2. The overview's listener: on the clear's notify it drops what it
      //    shows and asks again under the new binding. That request fails
      //    at once (offline), so it falls back to the cache, read under
      //    the new binding, in the same synchronous step.
      TeamCacheBinding? rebound;
      final fallbacks = <Future<(Map<String, dynamic>, DateTime)?>>[];
      void onClear() {
        rebound = TeamCache.bind(s);
        fallbacks.add(TeamCache.read(s, key));
      }

      TeamCache.changes.addListener(onClear);
      addTearDown(() => TeamCache.changes.removeListener(onClear));

      // 3. Another screen gets not_allowed: the access-lost clear.
      var cleared = false;
      final clear = TeamCache.clearEmployee(s).then((_) => cleared = true);
      expect(fallbacks, hasLength(1));
      // The binding the reload took is current: the screen would show
      // whatever the fallback read returns.
      expect(rebound!.isCurrent(s), isTrue);
      expect(await fallbacks.single, isNull);
      expect(await TeamCache.read(s, key), isNull);
      // The deletion has not completed: it waits behind the held write.
      expect(cleared, isFalse);
      // But the removal is already sent to storage, ahead of TeamCache's
      // queue: an app killed now keeps no entry for the next start.
      expect(store.removals, contains('flutter.$key'));

      // 4. The held write lands; the deletion completes.
      store.release.complete();
      await held;
      await clear;
      expect(cleared, isTrue);
      expect(await TeamCache.read(s, key), isNull);
      expect(await _teamKeys(), isEmpty);
      final stored = await store.getAll();
      expect(stored.keys.where((k) => k.contains('team_v1|')), isEmpty);

      // A write under the new binding is stored and read again.
      await _write(s, key, _body(3));
      expect((await TeamCache.read(s, key))!.$1, _body(3));
    });
  });

  group('request epoch: the session lifecycle (A-L21)', () {
    test('advances at once when a sign-out or a logout begins, and when a '
        'new sign-in is saved', () async {
      final s = await _session();
      final e0 = s.requestEpoch;
      final hook = Completer<void>();
      s.onSessionClearing = () => hook.future;
      final out = s.clearSession(); // waits in its hook
      expect(s.requestEpoch, e0 + 1); // before the hook ends, before any wipe
      hook.complete();
      await out;
      expect(s.requestEpoch, e0 + 1);

      await s.saveLoginResponse(_loginBody(6, 'company', 'department', null));
      expect(s.requestEpoch, e0 + 2);

      s.onSessionClearing = null;
      final gone = s.logout();
      expect(s.requestEpoch, e0 + 3);
      await gone;
    });

    test('a binding taken before a sign-out is stale at once', () async {
      final s = await _session();
      final binding = TeamCache.bind(s);
      expect(binding.isCurrent(s), isTrue);
      final hook = Completer<void>();
      s.onSessionClearing = () => hook.future;
      final out = s.clearSession();
      expect(binding.isCurrent(s), isFalse);
      hook.complete();
      await out;
      expect(binding.isCurrent(s), isFalse);
    });

    test('overlapping hook, the same employee signs in again: the old answer, '
        'released after the clearing finished, is neither current nor '
        'stored', () async {
      const sig = 'a1b2c3d4e5f60718';
      final s = await _session(employeeId: 6, sig: sig);
      final key = TeamCache.overviewKey(s);
      // 1. A request starts: employee 6, signature S, generation G.
      final before = TeamCache.bind(s);
      // 2. A sign-out starts and waits in its hook.
      final hook = Completer<void>();
      s.onSessionClearing = () => hook.future;
      final out = s.clearSession();
      // 3. Employee 6 signs in again, with the same signature.
      await s.saveLoginResponse(_loginBody(6, 'company', 'department', sig));
      // 4. The sign-out skips its wipe (the sign-in is newer) and finishes.
      hook.complete();
      await out;
      expect(s.isLoggedIn, isTrue);
      expect(s.employeeId, 6);
      expect(TeamCache.overviewKey(s), key);
      expect(s.teamCacheSignature, before.signature);
      expect(TeamCache.generation, before.generation); // no clear ran
      // 5. The old answer arrives now.
      expect(before.isCurrent(s), isFalse);
      await TeamCache.write(s, key, _body(9), binding: before);
      expect(await _teamKeys(), isEmpty);
      expect(await TeamCache.read(s, key), isNull);

      // A request started in the new sign-in is stored.
      await _write(s, key, _body(1));
      expect((await TeamCache.read(s, key))!.$1, _body(1));
    });
  });

  group('cap', () {
    test('at most 24 entries per employee, the oldest go first', () async {
      final s = await _session();
      for (var i = 0; i < 26; i++) {
        TeamCache.clock = () => t0.add(Duration(minutes: i));
        await _write(
          s,
          TeamCache.key(session: s, kind: TeamCache.kindOutlook, span: '$i'),
          _body(i),
        );
      }
      final keys = await _teamKeys();
      expect(keys, hasLength(24));
      expect(keys, isNot(contains('team_v1|acme|6|outlook|-|-|-|0')));
      expect(keys, isNot(contains('team_v1|acme|6|outlook|-|-|-|1')));
      expect(keys, contains('team_v1|acme|6|outlook|-|-|-|2'));
      expect(keys, contains('team_v1|acme|6|outlook|-|-|-|25'));
    });

    test('rewriting an existing key does not grow the count', () async {
      final s = await _session();
      final key = TeamCache.outlookKey(s, days: 30);
      for (var i = 0; i < 30; i++) {
        TeamCache.clock = () => t0.add(Duration(minutes: i));
        await _write(s, key, _body(i));
      }
      expect(await _teamKeys(), [key]);
      final (body, savedAt) = (await TeamCache.read(s, key))!;
      expect(body, _body(29));
      expect(savedAt, t0.add(const Duration(minutes: 29)));
    });

    test("the cap counts this employee only; others' entries stay", () async {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 5; i++) {
        await prefs.setString('team_v1|acme|7|outlook|team|team|-|$i', '{}');
      }
      final s = await _session(employeeId: 6);
      for (var i = 0; i < 25; i++) { // the 25th write trims employee 6
        TeamCache.clock = () => t0.add(Duration(minutes: i));
        await _write(
          s,
          TeamCache.key(session: s, kind: TeamCache.kindOverview, span: '$i'),
          _body(i),
        );
      }
      final keys = await _teamKeys();
      expect(keys.where((k) => k.startsWith('team_v1|acme|6|')), hasLength(24));
      expect(keys.where((k) => k.startsWith('team_v1|acme|7|')), hasLength(5));
    });
  });

  group('clearing', () {
    test("clearEmployee removes this employee's keys only", () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('team_v1|acme|7|overview|-|-|-|today', '{}');
      await prefs.setString('team_v1|other|6|overview|-|-|-|today', '{}');
      await prefs.setString('team_leave_range|acme|6', '60');
      final s = await _session(employeeId: 6);
      await _write(s, TeamCache.overviewKey(s), _body(1));
      await _write(s, TeamCache.outlookKey(s, days: 30), _body(2));

      await TeamCache.clearEmployee(s);
      expect(await _teamKeys(), [
        'team_v1|acme|7|overview|-|-|-|today',
        'team_v1|other|6|overview|-|-|-|today',
      ]);
      expect(prefs.getString('team_leave_range|acme|6'), '60');
    });

    test('clearAll removes every team_v1 key and nothing else', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('team_v1|acme|7|overview|-|-|-|today', '{}');
      await prefs.setString('home_mode|acme|6', 'my_day');
      final s = await _session();
      await _write(s, TeamCache.overviewKey(s), _body(1));
      await TeamCache.clearAll();
      expect(await _teamKeys(), isEmpty);
      expect(prefs.getString('home_mode|acme|6'), 'my_day');
      expect(prefs.getString('company_code'), 'ACME');
    });

    test('sign-out (clearSession) clears the cache, routing stays', () async {
      final s = await _session();
      await _write(s, TeamCache.overviewKey(s), _body(1));
      await _write(s, TeamCache.outlookKey(s, days: 60), _body(2));
      await s.clearSession();
      expect(await _teamKeys(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('company_code'), 'ACME');
    });

    test('logout clears the cache too', () async {
      final s = await _session();
      await _write(s, TeamCache.overviewKey(s), _body(1));
      await s.logout();
      expect(await _teamKeys(), isEmpty);
    });

    test('a sign-in that completed during the sign-out hook stays, and its '
        'cache works once the sign-out is over', () async {
      final s = await _session(employeeId: 6);
      final hook = Completer<void>();
      s.onSessionClearing = () => hook.future;
      final out = s.clearSession();
      // Another sign-in lands while the hook runs; it is newer and stays
      // (the wipe is skipped). Until the sign-out ends, writes are dropped.
      await s.saveLoginResponse({
        'access_token': 'tok-8',
        'user': {'id': 108, 'login': 'u8', 'name': 'U'},
        'employee': {
          'id': 8,
          'name': 'Employee 8',
          'overview_access': 'company',
          'team_leave_source': 'department',
        },
      });
      await _write(s, TeamCache.overviewKey(s), _body(3));
      expect(await _teamKeys(), isEmpty); // isClearing: dropped
      hook.complete();
      await out;
      expect(s.employeeId, 8);
      expect(s.isLoggedIn, isTrue);
      await _write(s, TeamCache.overviewKey(s), _body(3));
      final hit = await TeamCache.read(s, TeamCache.overviewKey(s));
      expect(hit!.$1, _body(3));
    });
  });
}
