import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:omni_hr/models/auto_attendance_config.dart';
import 'package:omni_hr/services/auto/auto_api.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';
import 'package:omni_hr/services/auto/auto_background.dart';
import 'package:omni_hr/services/auto/auto_event.dart';
import 'package:omni_hr/services/auto/auto_event_queue.dart';
import 'package:omni_hr/services/auto/auto_fence.dart';
import 'package:omni_hr/services/auto/auto_key_store.dart';
import 'package:omni_hr/services/auto/auto_sampler.dart';
import 'package:omni_hr/services/auto/auto_sender.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _config = AutoAttendanceConfig.fromJson({
  'trigger': 'location_wifi',
  'dwell_min': 5,
  'exit_min': 10,
  'office': {'name': 'HQ', 'latitude': 1.3, 'longitude': 103.8, 'area_m': 150},
  'wifi_required': true,
})!;

const _region = 'omni_office_acme_7';

/// About 25 m from the office centre.
const _inside = AutoSample(
  latitude: 1.3002,
  longitude: 103.8001,
  accuracy: 10,
  ssid: 'Office',
  bssid: 'aa:bb:cc:dd:ee:ff',
);

/// About 1.1 km from the office centre.
const _outside = AutoSample(latitude: 1.31, longitude: 103.8, accuracy: 10);

/// A signed-in session for employee 7 of db `acme`.
class _FakeSession extends SessionService {
  _FakeSession({this.config});

  AutoAttendanceConfig? config;

  @override
  bool get isLoggedIn => true;
  @override
  String get token => 'tok';
  @override
  String get accessToken => 'tok';
  @override
  String get clientUrl => 'http://localhost';
  @override
  String get clientDb => 'acme';
  @override
  int get employeeId => 7;
  @override
  AutoAttendanceConfig? get autoAttendance => config;
}

/// The key route only; answers [key] or throws [error].
class _FakeMobileApi extends OmniMobileApi {
  _FakeMobileApi(this.log, {this.error})
    : super(baseUrl: 'http://localhost', db: 'acme', token: 'tok');

  final List<String> log;
  final ApiException? error;

  @override
  Future<({String key, String deviceId})> fetchAutoKey() async {
    log.add('fetchKey');
    final e = error;
    if (e != null) throw e;
    return (key: 'K1', deviceId: 'dev-1');
  }
}

/// Records status posts (and the key each client was built with).
class _FakeAutoApi extends AutoApi {
  _FakeAutoApi(this.statuses, {super.autoKey})
    : super(baseUrl: 'http://localhost', db: 'acme', bearer: 'tok');

  final List<Map<String, dynamic>> statuses;

  @override
  Future<AutoPostResult> postStatus({
    required String permission,
    required bool enabled,
    required String platform,
  }) async {
    statuses.add({
      'permission': permission,
      'enabled': enabled,
      'platform': platform,
      'key': autoKey,
    });
    return const AutoAccepted('ok');
  }
}

/// Answers [outcomes] in turn (then `done`) without posting anything.
class _FakeSender extends AutoSender {
  _FakeSender(this.log, AutoEventQueue queue)
    : super(
        queue: queue,
        api: () => throw StateError('not used'),
        notifyDropped: (_) async {},
      );

  final List<String> log;
  final outcomes = <FlushOutcome>[];

  @override
  Future<FlushOutcome> flush() async {
    log.add('flush');
    return outcomes.isEmpty ? FlushOutcome.done : outcomes.removeAt(0);
  }
}

/// Keeps what [create] was given and answers [registered] from it.
class _FakePort implements GeofencePort {
  final Map<String, Geofence> store = {};
  final List<Geofence> created = [];
  final List<String> removed = [];
  int reCreated = 0;

  @override
  Future<List<ActiveGeofence>> registered() async => [
    for (final g in store.values)
      ActiveGeofence(
        id: g.id,
        location: g.location,
        radiusMeters: g.radiusMeters,
        triggers: g.triggers,
        androidSettings: null,
      ),
  ];

  @override
  Future<void> create(Geofence g) async {
    created.add(g);
    store[g.id] = g;
  }

  @override
  Future<void> removeById(String id) async {
    removed.add(id);
    store.remove(id);
  }

  @override
  Future<void> reCreateAll() async => reCreated++;

  void seed(String id) {
    store[id] = Geofence(
      id: id,
      location: const Location(latitude: 1.3, longitude: 103.8),
      radiusMeters: 150,
      triggers: const {GeofenceEvent.enter, GeofenceEvent.exit},
      iosSettings: const IosGeofenceSettings(),
      androidSettings: const AndroidGeofenceSettings(initialTriggers: {}),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 30, 1, 0, 0);
  late SharedPreferencesAsync prefs;
  late AutoEventQueue queue;
  late AutoKeyStore keyStore;
  late _FakePort port;
  late _FakeSession session;
  late List<String> log;
  late List<Map<String, dynamic>> statuses;
  late _FakeSender sender;
  late String permission;
  late AutoSample sample;
  late int samples;
  ApiException? keyError;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = SharedPreferencesAsync();
    queue = AutoEventQueue(prefs: prefs);
    keyStore = AutoKeyStore();
    port = _FakePort();
    session = _FakeSession(config: _config);
    log = [];
    statuses = [];
    sender = _FakeSender(log, queue);
    permission = 'always';
    sample = _inside;
    samples = 0;
    keyError = null;
  });

  AutoAttendanceService service({
    String platform = 'ios',
    String appVersion = '1.36.0',
    Future<String> Function()? permissionSeam,
    bool android = false,
  }) => AutoAttendanceService(
    session: session,
    permission:
        permissionSeam ??
        () async {
          log.add('permission');
          return permission;
        },
    fence: AutoFence(port: port, isAndroid: android),
    keyStore: keyStore,
    apiBuilder: (_) => _FakeMobileApi(log, error: keyError),
    autoApiBuilder: (_, key) => _FakeAutoApi(statuses, autoKey: key),
    sender: sender,
    sampler: () async {
      samples++;
      return sample;
    },
    platform: platform,
    queue: queue,
    prefs: prefs,
    refresh: () async => log.add('refresh'),
    deviceId: () async => 'dev-1',
    appVersion: () => appVersion,
    now: () => now,
  );

  Future<void> answered(String state, {Duration ago = Duration.zero}) =>
      prefs.setString(
        AutoSender.lastAnswerKey,
        jsonEncode(
          AutoLastAnswer(state: state, at: now.subtract(ago)).toJson(),
        ),
      );

  test(
    'config null → removes fence, deletes key, posts enabled false',
    () async {
      session.config = null;
      port.seed(_region);
      await keyStore.write('K0', 'dev-1');

      final auto = service();
      await auto.sync(appStart: true);

      expect(auto.state, AutoPhoneState.off);
      expect(port.store, isEmpty);
      expect(port.removed, [_region]);
      expect(await keyStore.read(), isNull);
      expect(statuses, [
        {
          'permission': 'always',
          'enabled': false,
          'platform': 'ios',
          'key': null,
        },
      ]);
      expect(log, isNot(contains('fetchKey')));
      expect(log, isNot(contains('flush')));
    },
  );

  test('refresh runs before the key fetch', () async {
    final auto = service();
    await auto.sync();

    expect(log.where((c) => c == 'refresh' || c == 'fetchKey').toList(), [
      'refresh',
      'fetchKey',
    ]);
    expect(await keyStore.read(), 'K1');
    expect(await keyStore.deviceId(), 'dev-1');
    expect(auto.state, AutoPhoneState.on);
    expect(port.created.single.id, _region);
  });

  test('a stored key is not fetched again', () async {
    await keyStore.write('K0', 'dev-1');
    await service().sync();
    expect(log, isNot(contains('fetchKey')));
  });

  test('not_enabled on key fetch → state off', () async {
    keyError = ApiException('not_enabled');
    port.seed(_region);
    final auto = service();
    await auto.sync();

    expect(auto.state, AutoPhoneState.off);
    expect(port.store, isEmpty);
    expect(await keyStore.read(), isNull);
    expect(statuses.single['enabled'], false);
    expect(log, isNot(contains('flush')));
  });

  test('device_required on key fetch → needsSetup, no region', () async {
    keyError = ApiException('device_required');
    final auto = service();
    await auto.sync();

    expect(auto.state, AutoPhoneState.needsSetup);
    expect(port.created, isEmpty);
    expect(statuses.single['enabled'], false);
  });

  test('while_using → needsAlways, no region', () async {
    permission = 'while_using';
    port.seed(_region);
    final auto = service();
    await auto.sync(appStart: true);

    expect(auto.state, AutoPhoneState.needsAlways);
    expect(port.created, isEmpty);
    expect(port.store, isEmpty);
    expect(samples, 0);
    expect(statuses, [
      {
        'permission': 'while_using',
        'enabled': false,
        'platform': 'ios',
        'key': null,
      },
    ]);
  });

  test('session clearing wipes queue, key and fence', () async {
    port.seed(_region);
    port.seed('omni_office_other_7');
    await keyStore.write('K0', 'dev-1');
    await queue.add(
      AutoEvent(
        eventUid: 'a-1',
        kind: AutoKind.arrive,
        eventAt: now,
        isMocked: false,
        deviceId: 'dev-1',
        appVersion: '1.36.0',
        source: AutoSource.geofence,
      ),
    );
    await prefs.setString(autoLastStateKey, autoStateInside);
    await prefs.setBool(autoOptedOutKey(7), true);
    await prefs.setString(autoStatusSentKey, 'always|true|ios');
    await prefs.setString('other_pref', 'kept');

    final auto = service();
    await auto.onSessionClearing();

    expect(await queue.ordered(), isEmpty);
    expect(await keyStore.read(), isNull);
    expect(port.store.keys, ['omni_office_other_7']);
    final keys = await prefs.getKeys();
    expect(keys.where((k) => k.startsWith('omni_auto_')), isEmpty);
    expect(keys, contains('other_pref'));
    expect(auto.state, AutoPhoneState.off);
  });

  test('no foreground arrive when last state is inside', () async {
    await prefs.setString(autoLastStateKey, autoStateInside);
    await service().sync();

    expect(samples, 0);
    expect(await queue.ordered(), isEmpty);
    expect(log, contains('flush'));
  });

  test('foreground arrive when inside and state unknown', () async {
    final auto = service();
    auto.onAutoUndone();
    await Future<void>.delayed(Duration.zero);
    expect(await prefs.getString(autoLastStateKey), 'unknown');

    await auto.sync();

    final events = await queue.ordered();
    expect(events, hasLength(1));
    final e = events.single;
    expect(e.kind, AutoKind.arrive);
    expect(e.source, AutoSource.foreground);
    expect(e.latitude, _inside.latitude);
    expect(e.wifiSsid, 'Office');
    expect(e.deviceId, 'dev-1');
    expect(e.appVersion, '1.36.0');
    expect(e.eventAt, now);
    expect(await prefs.getString(autoLastStateKey), autoStateInside);
    // Queued before the queue is sent.
    expect(log.last, 'flush');
  });

  test('foreground arrive when inside and the last answer is waiting_wifi '
      '< 30 min', () async {
    await prefs.setString(autoLastStateKey, autoStateInside);
    await answered('waiting_wifi', ago: const Duration(minutes: 10));
    final auto = service();
    await auto.sync();

    expect((await queue.ordered()).single.source, AutoSource.foreground);
    expect(auto.state, AutoPhoneState.waitingWifi);
  });

  test(
    'an old waiting_wifi answer neither re-checks nor shows waiting',
    () async {
      await prefs.setString(autoLastStateKey, autoStateInside);
      await answered('waiting_wifi', ago: const Duration(minutes: 31));
      final auto = service();
      await auto.sync();

      expect(samples, 0);
      expect(auto.state, AutoPhoneState.on);
    },
  );

  test('no foreground arrive when the fix is outside the area', () async {
    sample = _outside;
    await service().sync();
    expect(samples, 1);
    expect(await queue.ordered(), isEmpty);
  });

  test('the fix accuracy widens the area by at most 100 m', () async {
    // ~222 m from the centre: inside 150 + 100, outside 150 + 50.
    sample = const AutoSample(latitude: 1.302, longitude: 103.8, accuracy: 500);
    await service().sync();
    expect(await queue.ordered(), hasLength(1));

    await queue.clear();
    await prefs.remove(autoLastStateKey);
    sample = const AutoSample(latitude: 1.302, longitude: 103.8, accuracy: 50);
    await service().sync();
    expect(await queue.ordered(), isEmpty);
  });

  test('status posted on app start and on change only', () async {
    final auto = service();
    await auto.sync(appStart: true);
    expect(statuses, hasLength(1));
    expect(statuses.single, {
      'permission': 'always',
      'enabled': true,
      'platform': 'ios',
      'key': null,
    });

    await auto.sync();
    expect(statuses, hasLength(1));

    permission = 'while_using';
    await auto.sync();
    expect(statuses, hasLength(2));
    expect(statuses.last['enabled'], false);

    await auto.sync();
    expect(statuses, hasLength(2));

    await auto.sync(appStart: true);
    expect(statuses, hasLength(3));
  });

  test('concurrent sync runs twice, not in parallel', () async {
    var active = 0;
    var maxActive = 0;
    var runs = 0;
    final gates = <Completer<void>>[];
    final auto = service(
      permissionSeam: () async {
        runs++;
        active++;
        if (active > maxActive) maxActive = active;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        active--;
        return 'always';
      },
    );
    // Release the gate only while a run waits on it; the run then finishes.
    final first = auto.sync();
    final second = auto.sync();
    final third = auto.sync();
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1);
    gates.last.complete();
    while (runs < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    gates.last.complete();
    await Future.wait([first, second, third]);

    expect(runs, 2);
    expect(maxActive, 1);
  });

  test('an invalid key is deleted and fetched once more', () async {
    await keyStore.write('K0', 'dev-1');
    sender.outcomes.add(FlushOutcome.keyInvalid);
    await service().sync();

    expect(log.where((c) => c == 'fetchKey'), hasLength(1));
    expect(log.where((c) => c == 'flush'), hasLength(2));
    expect(await keyStore.read(), 'K1');
  });

  test('turn off on this phone, then on again', () async {
    final auto = service();
    await auto.sync(appStart: true);
    expect(port.store.keys, [_region]);

    await auto.turnOffOnThisPhone();
    expect(auto.state, AutoPhoneState.optedOut);
    expect(port.store, isEmpty);
    expect(await keyStore.read(), isNull);
    expect(await prefs.getBool(autoOptedOutKey(7)), true);
    expect(statuses.last['enabled'], false);

    await auto.turnOnAgain();
    expect(auto.state, AutoPhoneState.on);
    expect(port.store.keys, [_region]);
    expect(statuses.last['enabled'], true);
  });

  group('Android app update (R9)', () {
    test('re-creates the regions once per new app version', () async {
      await prefs.setString(autoArmedAppVersionKey, '1.35.0');
      final auto = service(platform: 'android', android: true);
      await auto.sync(appStart: true);
      expect(port.reCreated, 1);
      expect(await prefs.getString(autoArmedAppVersionKey), '1.36.0');

      await auto.sync(appStart: true);
      await auto.sync();
      expect(port.reCreated, 1);
    });

    test('not on resume, and never on iPhone', () async {
      await prefs.setString(autoArmedAppVersionKey, '1.35.0');
      await service(platform: 'android', android: true).sync();
      expect(port.reCreated, 0);

      await service().sync(appStart: true);
      expect(port.reCreated, 0);
    });
  });

  test('a throwing plugin never makes sync throw', () async {
    final auto = AutoAttendanceService(
      session: session,
      permission: () async => 'always',
      fence: AutoFence(port: _ThrowingPort(), isAndroid: false),
      keyStore: keyStore,
      apiBuilder: (_) => _FakeMobileApi(log),
      autoApiBuilder: (_, key) => _FakeAutoApi(statuses, autoKey: key),
      sender: sender,
      sampler: () async => _outside,
      platform: 'ios',
      queue: queue,
      prefs: prefs,
      refresh: () async {},
      deviceId: () async => 'dev-1',
      appVersion: () => '1.36.0',
      now: () => now,
    );
    await auto.sync(appStart: true);
    await auto.onSessionClearing();
    expect(log, contains('flush'));
  });
}

class _ThrowingPort implements GeofencePort {
  @override
  Future<void> create(Geofence g) => throw StateError('plugin');
  @override
  Future<void> reCreateAll() => throw StateError('plugin');
  @override
  Future<List<ActiveGeofence>> registered() => throw StateError('plugin');
  @override
  Future<void> removeById(String id) => throw StateError('plugin');
}
