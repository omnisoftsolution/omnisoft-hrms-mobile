import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:native_geofence/native_geofence.dart';
import 'package:omni_hr/models/auto_attendance_config.dart';
import 'package:omni_hr/models/wifi_info_result.dart';
import 'package:omni_hr/services/auto/auto_api.dart';
import 'package:omni_hr/services/auto/auto_background.dart';
import 'package:omni_hr/services/auto/auto_event.dart';
import 'package:omni_hr/services/auto/auto_event_queue.dart';
import 'package:omni_hr/services/auto/auto_key_store.dart';
import 'package:omni_hr/services/auto/auto_sampler.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../push_fakes.dart';

final _config = AutoAttendanceConfig.fromJson({
  'trigger': 'location_wifi',
  'dwell_min': 5,
  'exit_min': 10,
  'office': {'name': 'HQ', 'latitude': 1.3, 'longitude': 103.8, 'area_m': 150},
  'wifi_required': true,
})!;

AutoBackgroundContext _ctx({String? autoKey = 'K', int employeeId = 7}) =>
    AutoBackgroundContext(
      baseUrl: 'http://localhost',
      db: 'acme',
      deviceId: 'ios-dev-1',
      appVersion: '1.36.0',
      employeeId: employeeId,
      autoKey: autoKey,
      config: _config,
    );

const _sample = AutoSample(
  latitude: 1.3001,
  longitude: 103.8002,
  accuracy: 12,
  isMocked: false,
  ssid: 'Office',
  bssid: 'aa:bb:cc:dd:ee:ff',
);

/// Records every posted event body; answers [answer].
class _FakeApi extends AutoApi {
  _FakeApi({this.answer = const AutoAccepted('checked_in')})
    : super(baseUrl: 'http://localhost', db: 'acme');

  final AutoPostResult answer;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AutoPostResult> postEvent(AutoEvent e) async {
    bodies.add(e.toBody());
    return answer;
  }
}

/// A session whose refresh is recorded instead of sent.
class _FakeSession extends SessionService {
  _FakeSession({this.storedRefresh = 'R'});

  final String storedRefresh;
  final calls = <String>[];
  bool? forgot;

  @override
  String get refreshToken => storedRefresh;

  @override
  Future<RefreshOutcome> refreshAccessToken(
    String deviceId, {
    String? refreshToken,
    bool forgetOnRefusal = true,
  }) async {
    calls.add(deviceId);
    forgot = forgetOnRefusal;
    return RefreshOutcome.ok;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 30, 1, 0, 0);
  late SharedPreferencesAsync prefs;
  late AutoEventQueue queue;
  late _FakeApi api;
  late List<String> apiAuth;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = SharedPreferencesAsync();
    queue = AutoEventQueue(prefs: prefs);
    api = _FakeApi();
    apiAuth = [];
  });

  Future<void> wake({
    required AutoKind kind,
    required AutoSource source,
    AutoBackgroundContext? ctx,
    Future<AutoBackgroundContext?> Function()? loadContext,
    Future<AutoSample> Function()? sampler,
    Future<String?> Function()? bearer,
    Duration timeout = const Duration(seconds: 25),
  }) => handleAutoWake(
    kind: kind,
    source: source,
    ctx: ctx,
    // Still the same sign-in when the fix is taken, unless a test says not.
    loadContext: loadContext ?? () async => ctx ?? _ctx(),
    sampler: sampler ?? () async => _sample,
    queue: queue,
    prefs: prefs,
    refresh: () async {},
    bearer: bearer ?? () async => null,
    apiBuilder: (c, token, client) {
      apiAuth.add(c.autoKey ?? 'bearer:$token');
      return api;
    },
    notifyDropped: (_) async {},
    now: () => now,
    timeout: timeout,
  );

  /// Routes a geofence callback into [wake] with the test's fakes.
  Future<void> geofence(GeofenceEvent event, List<String> ids) =>
      handleGeofenceEvent(
        event,
        ids,
        loadContext: () async => _ctx(),
        wake: ({required kind, required source, ctx}) =>
            wake(kind: kind, source: source, ctx: ctx),
      );

  group('a sign-out while the fix is taken (R136-F03)', () {
    for (final (name, after) in [
      ('signed out', null),
      ('another employee signed in', _ctx(employeeId: 8)),
    ]) {
      test('$name: the event is dropped, nothing is sent', () async {
        await wake(
          kind: AutoKind.arrive,
          source: AutoSource.geofence,
          ctx: _ctx(),
          loadContext: () async => after,
        );
        expect(await queue.ordered(), isEmpty);
        expect(api.bodies, isEmpty);
      });
    }
  });

  test(
    'a wake stamps its event with the signed-in employee (R136-F03)',
    () async {
      api = _FakeApi(answer: const AutoRetry('timeout')); // stays queued
      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        ctx: _ctx(),
      );
      expect((await queue.ordered()).single.owner, 'acme|7');
    },
  );

  group('geofence wake', () {
    test('enter posts an arrive with the sample and device id', () async {
      await geofence(GeofenceEvent.enter, ['omni_office_acme_7']);

      expect(api.bodies, hasLength(1));
      final body = api.bodies.single;
      expect(body['kind'], 'arrive');
      expect(body.containsKey('source'), isFalse); // geofence = default
      expect(body['event_at'], '2026-10-30 01:00:00');
      expect(body['latitude'], 1.3001);
      expect(body['longitude'], 103.8002);
      expect(body['location_accuracy'], 12);
      expect(body['is_mocked'], false);
      expect(body['wifi_ssid'], 'Office');
      expect(body['wifi_bssid'], 'aa:bb:cc:dd:ee:ff');
      expect(body['device_id'], 'ios-dev-1');
      expect(body['app_version'], '1.36.0');
      expect(apiAuth, ['K']);
      expect(await prefs.getString(autoLastStateKey), autoStateInside);
      expect(await queue.ordered(), isEmpty);
    });

    test('exit records outside and posts a leave', () async {
      await prefs.setString(autoLastStateKey, autoStateInside);
      await geofence(GeofenceEvent.exit, ['omni_office_acme_7']);

      expect(api.bodies.single['kind'], 'leave');
      expect(await prefs.getString(autoLastStateKey), autoStateOutside);
    });

    test('dwell sends source dwell', () async {
      await geofence(GeofenceEvent.dwell, ['omni_office_acme_7']);

      expect(api.bodies.single['kind'], 'arrive');
      expect(api.bodies.single['source'], 'dwell');
      expect(await prefs.getString(autoLastStateKey), autoStateInside);
    });

    test('foreign region id is ignored', () async {
      var woke = 0;
      await handleGeofenceEvent(
        GeofenceEvent.enter,
        ['omni_office_acme_8', 'omni_office_other_7'],
        loadContext: () async => _ctx(),
        wake: ({required kind, required source, ctx}) async => woke++,
      );
      await handleGeofenceEvent(
        GeofenceEvent.enter,
        const [],
        loadContext: () async => _ctx(),
        wake: ({required kind, required source, ctx}) async => woke++,
      );
      expect(woke, 0);
    });

    test('signed out: the geofence callback wakes nothing', () async {
      var woke = 0;
      await handleGeofenceEvent(
        GeofenceEvent.enter,
        ['omni_office_acme_7'],
        loadContext: () async => null,
        wake: ({required kind, required source, ctx}) async => woke++,
      );
      expect(woke, 0);
    });

    test('autoRegionId is omni_office_<db>_<employee>', () {
      expect(autoRegionId('acme', 7), 'omni_office_acme_7');
      expect(_ctx().regionId, 'omni_office_acme_7');
    });
  });

  group('signed out or opted out', () {
    Future<AutoBackgroundContext?> load() => AutoBackgroundContext.load(
      asyncPrefs: prefs,
      keyStore: AutoKeyStore(),
      appVersion: () async => '1.36.0',
    );

    void signedIn() => SharedPreferences.setMockInitialValues({
      SessionService.clientUrlPrefsKey: 'https://acme.example',
      SessionService.clientDbPrefsKey: 'acme',
      SessionService.employeeIdPrefsKey: 7,
      'employee_auto_attendance': jsonEncode(_config.toJson()),
      'omni_hr_device_id': 'ios-dev-1',
    });

    test('a signed-in phone loads the context with the key', () async {
      signedIn();
      await AutoKeyStore().write('KEY', 'ios-dev-1', owner: 'acme|7');
      final c = await load();
      expect(c, isNotNull);
      expect(c!.baseUrl, 'https://acme.example');
      expect(c.db, 'acme');
      expect(c.employeeId, 7);
      expect(c.deviceId, 'ios-dev-1');
      expect(c.appVersion, '1.36.0');
      expect(c.autoKey, 'KEY');
      expect(c.config!.office.areaM, 150);
    });

    test('a key of another employee or company, or without an owner, is not '
        'used (F4): no key, the wake falls back to bearer / queue', () async {
      signedIn();
      for (final owner in ['acme|8', 'other|7', null]) {
        if (owner == null) {
          await AutoKeyStore().delete();
          await const FlutterSecureStorage().write(
            key: AutoKeyStore.keyName,
            value: 'KEY',
          );
        } else {
          await AutoKeyStore().write('KEY', 'ios-dev-1', owner: owner);
        }
        final c = await load();
        expect(c, isNotNull, reason: '$owner');
        expect(c!.autoKey, isNull, reason: '$owner');
      }

      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        loadContext: load,
        bearer: () async => 'T',
      );
      expect(apiAuth, ['bearer:T']);
    });

    test('an unreadable app version still gives a context (M4)', () async {
      signedIn();
      await AutoKeyStore().write('KEY', 'ios-dev-1', owner: 'acme|7');
      final c = await AutoBackgroundContext.load(
        asyncPrefs: prefs,
        keyStore: AutoKeyStore(),
        appVersion: () async => throw StateError('package_info'),
      );
      expect(c, isNotNull);
      expect(c!.appVersion, '');
      expect(c.autoKey, 'KEY');
    });

    test('signed out → no context, nothing queued', () async {
      SharedPreferences.setMockInitialValues({
        // Company routing survives a sign-out; the employee does not.
        SessionService.clientUrlPrefsKey: 'https://acme.example',
        SessionService.clientDbPrefsKey: 'acme',
      });
      expect(await load(), isNull);

      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        loadContext: load,
      );
      expect(await queue.ordered(), isEmpty);
      expect(api.bodies, isEmpty);
      expect(await prefs.getString(autoLastStateKey), isNull);
    });

    test('opted out on this phone → no context, nothing queued', () async {
      signedIn();
      await prefs.setBool(autoOptedOutKey(7), true);
      expect(await load(), isNull);

      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        loadContext: load,
      );
      expect(await queue.ordered(), isEmpty);
      expect(api.bodies, isEmpty);
    });

    test('HR switched it off (no config) → no context', () async {
      signedIn();
      final p = await SharedPreferences.getInstance();
      await p.remove('employee_auto_attendance');
      expect(await load(), isNull);
    });
  });

  group('recheck', () {
    Future<int> recheck(String? state) async {
      if (state != null) await prefs.setString(autoLastStateKey, state);
      var woke = 0;
      AutoKind? k;
      AutoSource? s;
      await handleAutoRecheck(
        {'kind': 'auto_recheck', 'event_id': '5'},
        prefs: prefs,
        wake: ({required kind, required source, ctx}) async {
          woke++;
          k = kind;
          s = source;
        },
      );
      if (woke > 0) {
        expect(k, AutoKind.arrive);
        expect(s, AutoSource.recheck);
      }
      return woke;
    }

    test('recheck only when last state is inside', () async {
      expect(await recheck(null), 0);
      expect(await recheck(autoStateOutside), 0);
      expect(await recheck('unknown'), 0);
      expect(await recheck(autoStateInside), 1);
    });

    test('a recheck wake posts source recheck and keeps the state', () async {
      await prefs.setString(autoLastStateKey, autoStateInside);
      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.recheck,
        ctx: _ctx(),
      );
      expect(api.bodies.single['source'], 'recheck');
      expect(await prefs.getString(autoLastStateKey), autoStateInside);
    });

    test(
      'handleBackgroundData routes auto_recheck and shows nothing',
      () async {
        final native = FakeNative();
        final seen = <Map<String, dynamic>>[];
        await handleBackgroundData(
          {'kind': 'auto_recheck', 'action': 'remove', 'omni_key': 'x'},
          pushNative: native,
          companyCode: () async => 'ACME',
          signedIn: () async => true,
          autoRecheck: (data) async => seen.add(data),
        );
        expect(seen, hasLength(1));
        expect(native.calls, isEmpty);
      },
    );
  });

  group('robustness', () {
    test(
      'sampler failure still queues the event with null coordinates',
      () async {
        await wake(
          kind: AutoKind.arrive,
          source: AutoSource.geofence,
          ctx: _ctx(autoKey: null),
          sampler: () async => throw StateError('no fix'),
        );
        // Neither key nor bearer readable: queued for the foreground.
        final queued = await queue.ordered();
        expect(queued, hasLength(1));
        expect(queued.single.latitude, isNull);
        expect(queued.single.longitude, isNull);
        expect(queued.single.wifiSsid, isNull);
        expect(queued.single.kind, AutoKind.arrive);
        expect(api.bodies, isEmpty);
      },
    );

    test('no key: posts with the bearer token when readable', () async {
      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        ctx: _ctx(autoKey: null),
        bearer: () async => 'T',
      );
      expect(apiAuth, ['bearer:T']);
      expect(api.bodies, hasLength(1));
    });

    test('a retry answer keeps the event queued', () async {
      api = _FakeApi(answer: const AutoRetry('busy_retry'));
      await wake(
        kind: AutoKind.leave,
        source: AutoSource.geofence,
        ctx: _ctx(),
      );
      expect(await queue.ordered(), hasLength(1));
    });

    test('a hanging wake returns after the timeout without throwing', () async {
      await wake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        ctx: _ctx(),
        sampler: () => Completer<AutoSample>().future,
        timeout: const Duration(milliseconds: 50),
      );
      expect(api.bodies, isEmpty);
    });

    test('the wake closes the http client it made', () async {
      final client = _TrackingClient();
      await handleAutoWake(
        kind: AutoKind.arrive,
        source: AutoSource.geofence,
        ctx: _ctx(),
        sampler: () async => _sample,
        queue: queue,
        prefs: prefs,
        refresh: () async {},
        apiBuilder: (c, token, cl) {
          expect(cl, same(client));
          return api;
        },
        clientFactory: () => client,
        notifyDropped: (_) async {},
        now: () => now,
      );
      expect(client.closed, isTrue);
    });
  });

  group('sampleNow', () {
    Position pos({bool mocked = false}) => Position(
      latitude: 1.5,
      longitude: 103.5,
      timestamp: now,
      accuracy: 9,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

    test('fix and Wi-Fi are combined', () async {
      final s = await sampleNow(
        fix: () async => pos(mocked: true),
        wifi: () async => const WifiInfoResult.ready(
          ssid: 'Office',
          bssid: '01:02:03:04:05:06',
        ),
      );
      expect(s.latitude, 1.5);
      expect(s.longitude, 103.5);
      expect(s.accuracy, 9);
      expect(s.isMocked, isTrue);
      expect(s.ssid, 'Office');
      expect(s.bssid, '01:02:03:04:05:06');
    });

    test('a failed fix and no Wi-Fi give nulls, never a throw', () async {
      final s = await sampleNow(
        fix: () async => throw const LocationServiceDisabledException(),
        wifi: () async => const WifiInfoResult.notConnected(),
      );
      expect(s.latitude, isNull);
      expect(s.accuracy, isNull);
      expect(s.isMocked, isFalse);
      expect(s.ssid, isNull);
      expect(s.bssid, isNull);
    });

    test('a hanging Wi-Fi read is bounded', () async {
      final s = await sampleNow(
        fix: () async => pos(),
        wifi: () => Completer<WifiInfoResult>().future,
        wifiLimit: const Duration(milliseconds: 20),
      );
      expect(s.latitude, 1.5);
      expect(s.ssid, isNull);
    });

    test('a hanging fix is bounded', () async {
      final s = await sampleNow(
        fix: () => Completer<Position>().future,
        wifi: () async => const WifiInfoResult.ready(ssid: 'Office'),
        fixLimit: const Duration(milliseconds: 20),
      );
      expect(s.latitude, isNull);
      expect(s.ssid, 'Office');
    });
  });

  group('wake: refresh vs flush order (F2)', () {
    late List<String> order;

    setUp(() => order = []);

    Future<void> orderedWake({
      required bool due,
      Future<void> Function()? refresh,
      Duration refreshLimit = const Duration(seconds: 8),
      Duration timeout = const Duration(seconds: 25),
    }) => handleAutoWake(
      kind: AutoKind.arrive,
      source: AutoSource.geofence,
      ctx: _ctx(),
      loadContext: () async => _ctx(),
      sampler: () async => _sample,
      queue: queue,
      prefs: prefs,
      refreshDue: () async => due,
      refresh:
          refresh ??
          () async {
            order.add('refresh');
          },
      refreshLimit: refreshLimit,
      apiBuilder: (c, token, client) => _OrderApi(order),
      notifyDropped: (_) async {},
      now: () => now,
      timeout: timeout,
    );

    test('due: refresh, then post (AA-F06)', () async {
      await orderedWake(due: true);
      expect(order, ['refresh', 'post']);
    });

    test('not due: post without a refresh', () async {
      await orderedWake(due: false);
      expect(order, ['post']);
    });

    test('a hanging refresh is cut short and the flush still runs within '
        'the wake', () async {
      final watch = Stopwatch()..start();
      await orderedWake(
        due: true,
        refresh: () {
          order.add('refresh');
          return Completer<void>().future;
        },
        refreshLimit: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 5),
      );
      expect(order, ['refresh', 'post']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(await queue.ordered(), isEmpty);
    });

    test('the default refresh bound is 8 s', () {
      expect(autoWakeRefreshLimit, const Duration(seconds: 8));
    });

    test('autoRefreshDue: within 7 days of expiry or expired', () async {
      Future<bool> dueIn(Duration d) {
        SharedPreferences.setMockInitialValues({
          SessionService.expiresAtPrefsKey: now.add(d).toIso8601String(),
        });
        return autoRefreshDue(now: () => now);
      }

      expect(await dueIn(const Duration(days: 8)), isFalse);
      expect(await dueIn(const Duration(days: 6)), isTrue);
      expect(await dueIn(const Duration(hours: -1)), isTrue);
      SharedPreferences.setMockInitialValues({});
      expect(await autoRefreshDue(now: () => now), isFalse);
    });
  });

  group('refreshIfExpiringSoon (AA-F06)', () {
    late _FakeSession session;
    late int loads;

    setUp(() {
      session = _FakeSession();
      loads = 0;
    });

    Future<RefreshOutcome?> refresh(Duration expiresIn) async {
      SharedPreferences.setMockInitialValues({
        SessionService.expiresAtPrefsKey: now.add(expiresIn).toIso8601String(),
        'omni_hr_device_id': 'ios-dev-1',
      });
      return refreshIfExpiringSoon(
        loadSession: () async {
          loads++;
          return session;
        },
        prefs: prefs,
        now: () => now,
      );
    }

    test('refresh skipped when expiry is 8 days away', () async {
      expect(await refresh(const Duration(days: 8)), isNull);
      expect(loads, 0);
      expect(session.calls, isEmpty);
    });

    test('refreshes within 7 days, keeping the session on a refusal', () async {
      expect(await refresh(const Duration(days: 6)), RefreshOutcome.ok);
      expect(session.calls, ['ios-dev-1']);
      expect(session.forgot, isFalse);
      // The lease is released afterwards.
      expect(await prefs.getString(autoRefreshLeaseKey), isNull);
    });

    test('an already expired access session is refreshed too', () async {
      expect(await refresh(const Duration(hours: -2)), RefreshOutcome.ok);
    });

    test('skipped while another isolate holds the lease', () async {
      await prefs.setString(
        autoRefreshLeaseKey,
        now.add(const Duration(seconds: 30)).toIso8601String(),
      );
      expect(await refresh(const Duration(days: 1)), isNull);
      expect(session.calls, isEmpty);
    });

    test('an expired lease is taken over', () async {
      await prefs.setString(
        autoRefreshLeaseKey,
        now.subtract(const Duration(seconds: 1)).toIso8601String(),
      );
      expect(await refresh(const Duration(days: 1)), RefreshOutcome.ok);
    });

    test('an unreadable keychain (no session) skips silently', () async {
      SharedPreferences.setMockInitialValues({
        SessionService.expiresAtPrefsKey: now
            .add(const Duration(days: 1))
            .toIso8601String(),
        'omni_hr_device_id': 'ios-dev-1',
      });
      final out = await refreshIfExpiringSoon(
        loadSession: () async => null,
        prefs: prefs,
        now: () => now,
      );
      expect(out, isNull);
      expect(await prefs.getString(autoRefreshLeaseKey), isNull);
    });

    test('no refresh token → skipped', () async {
      session = _FakeSession(storedRefresh: '');
      expect(await refresh(const Duration(days: 1)), isNull);
      expect(session.calls, isEmpty);
    });

    test('a refusal leaves the stored refresh token alone', () async {
      // Real SessionService: the background passes forgetOnRefusal false.
      final s = SessionService();
      await s.saveLoginResponse({
        'success': true,
        'access_token': 'A',
        'expires_at': '2026-11-01 00:00:00',
        'refresh_token': 'R',
        'auth_source': 'omni',
        'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
        'employee': {'id': 7, 'name': 'A'},
      });
      final out = await s.refreshAccessTokenWith(
        _RefusingApi(),
        'ios-dev-1',
        forgetOnRefusal: false,
      );
      expect(out, RefreshOutcome.invalid);
      expect(s.refreshToken, 'R');
      expect(s.accessToken, 'A');
      expect(
        await const FlutterSecureStorage().read(key: 'refresh_token'),
        'R',
      );
    });
  });
}

class _RefusingApi extends OmniMobileApi {
  _RefusingApi()
    : super(baseUrl: 'https://example.test', db: 'acme', token: '');

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
    required String deviceId,
  }) async => throw ApiException('refresh_invalid');
}

/// Records each post in a shared [order] list.
class _OrderApi extends AutoApi {
  _OrderApi(this.order) : super(baseUrl: 'http://localhost', db: 'acme');

  final List<String> order;

  @override
  Future<AutoPostResult> postEvent(AutoEvent e) async {
    order.add('post');
    return const AutoAccepted('checked_in');
  }
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
