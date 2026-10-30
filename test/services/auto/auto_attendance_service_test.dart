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
  bool loggedIn = true;

  @override
  bool get isLoggedIn => loggedIn;
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

  void changed() => notifyListeners();
}

/// Prefs whose queue removal throws (the queue cannot be cleared).
class _QueueThrowingPrefs extends SharedPreferencesAsync {
  @override
  Future<void> remove(String key) {
    if (key == AutoEventQueue.storageKey) throw StateError('disk');
    return super.remove(key);
  }
}

/// Prefs whose opt-out writes throw (a full disk, a broken platform).
class _OptOutThrowingPrefs extends SharedPreferencesAsync {
  @override
  Future<void> setBool(String key, bool value) {
    if (key.startsWith('omni_auto_opted_out')) throw StateError('disk');
    return super.setBool(key, value);
  }

  @override
  Future<void> remove(String key) {
    if (key.startsWith('omni_auto_opted_out')) throw StateError('disk');
    return super.remove(key);
  }
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
  _FakeAutoApi(
    this.statuses, {
    super.autoKey,
    this.answer = const AutoAccepted('ok'),
  }) : super(baseUrl: 'http://localhost', db: 'acme', bearer: 'tok');

  final List<Map<String, dynamic>> statuses;
  final AutoPostResult answer;

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
    return answer;
  }
}

/// In-memory secure storage that records every call.
class _RecordingSecure extends FlutterSecureStorage {
  final Map<String, String> data = {};
  final List<String> calls = [];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('read $key');
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('write $key');
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('delete $key');
    data.remove(key);
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

  /// When set, a flush waits for it (a post on the wire), then runs
  /// [afterHold] (the real sender saves the server's answer then).
  Completer<void>? hold;
  Future<void> Function()? afterHold;
  final called = Completer<void>();

  @override
  Future<FlushOutcome> flush() async {
    log.add('flush');
    if (!called.isCompleted) called.complete();
    final h = hold;
    if (h != null) {
      await h.future;
      await afterHold?.call();
    }
    return outcomes.isEmpty ? FlushOutcome.done : outcomes.removeAt(0);
  }
}

/// Keeps what [create] was given and answers [registered] from it.
class _FakePort implements GeofencePort {
  final Map<String, Geofence> store = {};
  final List<Geofence> created = [];
  final List<String> removed = [];
  int reCreated = 0;

  /// Every plugin call, in order.
  final List<String> calls = [];

  /// How many [registered] calls throw next (a failing plugin channel).
  int failRegistered = 0;

  /// When set, [registered] waits for it (a stalled plugin call).
  Completer<void>? holdRegistered;

  /// When set, [create] waits for it (the plugin call on the wire).
  Completer<void>? holdCreate;
  final createCalled = Completer<void>();

  @override
  Future<List<ActiveGeofence>> registered() async {
    calls.add('registered');
    if (failRegistered > 0) {
      failRegistered--;
      throw StateError('plugin');
    }
    final h = holdRegistered;
    if (h != null) await h.future;
    return [
      for (final g in store.values)
        ActiveGeofence(
          id: g.id,
          location: g.location,
          radiusMeters: g.radiusMeters,
          triggers: g.triggers,
          androidSettings: null,
        ),
    ];
  }

  @override
  Future<void> create(Geofence g) async {
    calls.add('create');
    if (!createCalled.isCompleted) createCalled.complete();
    final h = holdCreate;
    if (h != null) await h.future;
    created.add(g);
    store[g.id] = g;
  }

  @override
  Future<void> removeById(String id) async {
    calls.add('remove');
    removed.add(id);
    store.remove(id);
  }

  @override
  Future<void> reCreateAll() async {
    calls.add('reCreate');
    reCreated++;
  }

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
  late AutoPostResult statusAnswer;

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
    statusAnswer = const AutoAccepted('ok');
  });

  AutoAttendanceService service({
    String platform = 'ios',
    String appVersion = '1.36.0',
    Future<String> Function()? permissionSeam,
    bool android = false,
    Future<AutoSample> Function()? samplerSeam,
    Future<String> Function()? deviceIdSeam,
    AutoFence? fence,
    Duration clearingCap = const Duration(seconds: 2),
    SharedPreferencesAsync? prefsOverride,
    AutoEventQueue? queueOverride,
  }) => AutoAttendanceService(
    session: session,
    permission:
        permissionSeam ??
        () async {
          log.add('permission');
          return permission;
        },
    fence: fence ?? AutoFence(port: port, isAndroid: android),
    keyStore: keyStore,
    apiBuilder: (_) => _FakeMobileApi(log, error: keyError),
    autoApiBuilder: (_, key) =>
        _FakeAutoApi(statuses, autoKey: key, answer: statusAnswer),
    sender: sender,
    sampler:
        samplerSeam ??
        () async {
          samples++;
          return sample;
        },
    platform: platform,
    queue: queueOverride ?? queue,
    prefs: prefsOverride ?? prefs,
    refresh: () async => log.add('refresh'),
    deviceId: deviceIdSeam ?? () async => 'dev-1',
    appVersion: () => appVersion,
    now: () => now,
    clearingCap: clearingCap,
  );

  Future<void> answered(String state, {Duration ago = Duration.zero}) =>
      prefs.setString(
        AutoSender.lastAnswerKey,
        jsonEncode(
          AutoLastAnswer(state: state, at: now.subtract(ago)).toJson(),
        ),
      );

  group('HR switch off (R21: the off path only retracts)', () {
    test('never switched on → no plugin, keychain or status call, on start '
        'and on resume', () async {
      session.config = null;
      final secure = _RecordingSecure();
      keyStore = AutoKeyStore(storage: secure);

      final auto = service();
      await auto.sync(appStart: true);
      await auto.sync();
      await auto.sync();

      expect(auto.state, AutoPhoneState.off);
      expect(port.calls, isEmpty);
      expect(secure.calls, isEmpty);
      expect(statuses, isEmpty);
      expect(log, isNot(contains('fetchKey')));
      expect(log, isNot(contains('flush')));
    });

    test('status was sent, then HR switches off → one enabled:false post, '
        'region removed, key deleted', () async {
      final auto = service();
      await auto.sync(appStart: true);
      expect(port.store.keys, [_region]);
      expect(await keyStore.read(), 'K1');
      expect(statuses.single['enabled'], true);

      session.config = null;
      await auto.sync();
      await auto.sync(appStart: true);
      await auto.sync();

      expect(auto.state, AutoPhoneState.off);
      expect(port.store, isEmpty);
      expect(port.removed, [_region]);
      expect(await keyStore.read(), isNull);
      expect(statuses, hasLength(2));
      expect(statuses.last, {
        'permission': 'always',
        'enabled': false,
        'platform': 'ios',
        'key': null,
      });
      // Retracted: nothing left to clean or tell.
      expect(await prefs.getString(autoStatusSentKey), isNull);
      final keys = await prefs.getKeys();
      expect(
        keys.where((k) => k.startsWith('omni_auto_')),
        isNot(contains(autoEngagedKey)),
      );
    });

    test('a retraction the server did not take is sent again next time, '
        'until it lands', () async {
      await prefs.setString(autoStatusSentKey, 'always|true|ios');
      session.config = null;
      statusAnswer = const AutoRetry('http_503');
      final auto = service();
      await auto.sync();
      await auto.sync();
      expect(statuses, hasLength(2));

      statusAnswer = const AutoAccepted('ok');
      await auto.sync();
      await auto.sync();
      expect(statuses, hasLength(3));
      expect(await prefs.getString(autoStatusSentKey), isNull);
    });

    test('older connector (status route answers HTML 404) → not re-posted on '
        'every resume', () async {
      session.config = null;
      statusAnswer = const AutoRetry('http_404');
      final auto = service();
      await auto.sync(appStart: true);
      for (var i = 0; i < 3; i++) {
        await auto.sync();
      }
      expect(statuses, isEmpty);
      expect(port.calls, isEmpty);
    });

    test('a region armed without a status (status post failed) is still '
        'removed when HR switches off', () async {
      statusAnswer = const AutoRetry('timeout');
      final auto = service();
      await auto.sync(appStart: true);
      expect(port.store.keys, [_region]);
      expect(await prefs.getString(autoStatusSentKey), isNull);

      session.config = null;
      await auto.sync();
      expect(port.store, isEmpty);
      expect(await keyStore.read(), isNull);
      // No signature: nothing to retract, so no enabled:false post.
      expect(statuses.where((s) => s['enabled'] == false), isEmpty);
    });
  });

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
    await keyStore.write('K0', 'dev-1', owner: 'acme|7');
    await service().sync();
    expect(log, isNot(contains('fetchKey')));
  });

  test('a fetched key is stored with its owner <db>|<employee>', () async {
    await service().sync();
    expect(await keyStore.read(), 'K1');
    expect(await keyStore.owner(), 'acme|7');
  });

  group('a stored key of someone else (F4)', () {
    for (final (what, owner) in [
      ('another employee', 'acme|8'),
      ('another company', 'other|7'),
      ('no owner', null),
    ]) {
      test('$what → deleted, a new key is fetched and used', () async {
        if (owner == null) {
          // A key written before owners existed.
          await const FlutterSecureStorage().write(
            key: AutoKeyStore.keyName,
            value: 'K0',
          );
        } else {
          await keyStore.write('K0', 'dev-0', owner: owner);
        }
        final auto = service();
        await auto.sync();

        expect(log.where((c) => c == 'fetchKey'), hasLength(1));
        expect(await keyStore.read(), 'K1');
        expect(await keyStore.owner(), 'acme|7');
        expect(auto.state, AutoPhoneState.on);
      });
    }
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
    await keyStore.write('K0', 'dev-1', owner: 'acme|7');
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
    await keyStore.write('K0', 'dev-1', owner: 'acme|7');
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

  test('turning off on this phone drops the queued events (M3)', () async {
    final auto = service();
    await auto.sync(appStart: true);
    await queue.add(
      AutoEvent(
        eventUid: 'a-1',
        kind: AutoKind.leave,
        eventAt: now,
        isMocked: false,
        deviceId: 'dev-1',
        appVersion: '1.36.0',
        source: AutoSource.geofence,
      ),
    );

    await auto.turnOffOnThisPhone();
    expect(await queue.ordered(), isEmpty);
    expect(auto.state, AutoPhoneState.optedOut);
  });

  test('a prefs failure in turn off / turn on never reaches the button '
      '(M6)', () async {
    final auto = service(prefsOverride: _OptOutThrowingPrefs());
    await auto.sync(appStart: true);
    await expectLater(auto.turnOffOnThisPhone(), completes);
    await expectLater(auto.turnOnAgain(), completes);
  });

  test('HR switching on / off while the app is open runs sync (M2)', () async {
    session.config = null;
    final auto = service();
    await auto.sync(appStart: true);
    expect(auto.state, AutoPhoneState.off);

    // Only the session listener may start a run here.
    Future<void> settle(AutoPhoneState want) async {
      for (var i = 0; i < 200 && auto.state != want; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    session.config = _config;
    session.changed();
    await settle(AutoPhoneState.on);
    expect(auto.state, AutoPhoneState.on);
    expect(port.store.keys, [_region]);

    final runs = log.where((c) => c == 'permission').length;
    session.changed(); // nothing changed: no extra run
    await Future<void>.delayed(Duration.zero);
    expect(log.where((c) => c == 'permission').length, runs);

    session.config = null;
    session.changed();
    await settle(AutoPhoneState.off);
    expect(auto.state, AutoPhoneState.off);
    expect(port.store, isEmpty);
  });

  group('sign-out while a sync runs (review round 1)', () {
    Future<void> expectNothingLeft(AutoAttendanceService auto) async {
      expect(port.store, isEmpty);
      expect(await queue.ordered(), isEmpty);
      expect(await keyStore.read(), isNull);
      final keys = await prefs.getKeys();
      expect(keys.where((k) => k.startsWith('omni_auto_')), isEmpty);
      expect(auto.state, AutoPhoneState.off);
    }

    test('while the region is being created: the region is removed after '
        'the create', () async {
      port.holdCreate = Completer<void>();
      final auto = service();
      final run = auto.sync(appStart: true);
      await port.createCalled.future;

      final clearing = auto.onSessionClearing();
      port.holdCreate!.complete();
      await clearing;
      await run;

      expect(port.created.single.id, _region);
      expect(statuses, isEmpty);
      expect(samples, 0);
      expect(log, isNot(contains('flush')));
      await expectNothingLeft(auto);
    });

    test('while the fix is taken: no event and no inside state', () async {
      final fix = Completer<AutoSample>();
      final asked = Completer<void>();
      final auto = service(
        samplerSeam: () {
          asked.complete();
          return fix.future;
        },
      );
      final run = auto.sync();
      await asked.future;

      await auto.onSessionClearing();
      fix.complete(_inside);
      await run;

      expect(log, isNot(contains('flush')));
      await expectNothingLeft(auto);
    });

    test('while the device id is read: no event and no inside state', () async {
      final id = Completer<String>();
      final asked = Completer<void>();
      final auto = service(
        deviceIdSeam: () {
          asked.complete();
          return id.future;
        },
      );
      final run = auto.sync();
      await asked.future;

      await auto.onSessionClearing();
      id.complete('dev-1');
      await run;

      await expectNothingLeft(auto);
    });

    test('while a flush is on the wire: its late answer is swept', () async {
      await prefs.setString(autoLastStateKey, autoStateInside);
      sender.hold = Completer<void>();
      sender.afterHold = () => answered('waiting_wifi');
      final auto = service();
      final run = auto.sync();
      await sender.called.future;

      await auto.onSessionClearing();
      sender.hold!.complete();
      await run;

      await expectNothingLeft(auto);
    });

    test('a stalled plugin holds the sign-out no longer than the cap; the '
        'rest is still wiped', () async {
      await keyStore.write('K0', 'dev-1', owner: 'acme|7');
      await prefs.setString(autoLastStateKey, autoStateInside);
      final stalled = _StalledPort();
      final auto = service(
        fence: AutoFence(port: stalled, isAndroid: false),
        clearingCap: const Duration(milliseconds: 50),
      );

      final watch = Stopwatch()..start();
      await auto.onSessionClearing();
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));

      expect(await keyStore.read(), isNull);
      final keys = await prefs.getKeys();
      // Only the retry marker of the unfinished region removal is left.
      expect(keys.where((k) => k.startsWith('omni_auto_')), [
        '${autoFencePendingPrefix}acme',
      ]);
      expect(auto.state, AutoPhoneState.off);
    });
  });

  group('retry gap: a failed region removal is retried', () {
    test('HR off, removeAll throws once → marker kept → next sync removes '
        'the region', () async {
      final auto = service();
      await auto.sync(appStart: true);
      expect(port.store.keys, [_region]);

      session.config = null;
      port.failRegistered = 1;
      await auto.sync();
      expect(port.store.keys, [_region]);
      expect(await prefs.getBool(autoEngagedKey), isTrue);

      await auto.sync();
      expect(port.store, isEmpty);
      expect(await prefs.getBool(autoEngagedKey), isNull);
      // The retraction itself went out once.
      expect(statuses.where((s) => s['enabled'] == false), hasLength(1));

      final calls = port.calls.length;
      await auto.sync();
      expect(port.calls, hasLength(calls)); // nothing left to clean
    });

    test(
      'sign-out removal fails → only a retry marker survives the wipe; the '
      'next sign-in (HR off) removes the region and does nothing else',
      () async {
        final auto = service();
        await auto.sync(appStart: true);
        expect(port.store.keys, [_region]);
        final posts = statuses.length;

        port.failRegistered = 1;
        await auto.onSessionClearing();
        expect(port.store.keys, [_region]);
        expect(await keyStore.read(), isNull);
        expect(await queue.ordered(), isEmpty);
        final keys = await prefs.getKeys();
        expect(keys.where((k) => k.startsWith('omni_auto_')), [
          '${autoFencePendingPrefix}acme',
        ]);

        // The next sign-in: HR's switch off for this employee.
        session.config = null;
        final secure = _RecordingSecure();
        keyStore = AutoKeyStore(storage: secure);
        log.clear();
        final next = service();
        await next.sync(appStart: true);

        expect(port.store, isEmpty);
        expect(
          await prefs.getKeys(),
          isNot(contains('${autoFencePendingPrefix}acme')),
        );
        expect(statuses, hasLength(posts)); // no status post
        expect(secure.calls, isEmpty); // no key work
        expect(log, isNot(contains('fetchKey')));
        expect(next.state, AutoPhoneState.off);
      },
    );

    test('a pending removal is retried with no one signed in', () async {
      port.seed(_region);
      await prefs.setBool('${autoFencePendingPrefix}acme', true);
      session.loggedIn = false;
      await service().sync();
      expect(port.store, isEmpty);
      expect(await prefs.getBool('${autoFencePendingPrefix}acme'), isNull);
      expect(statuses, isEmpty);
    });

    test('a pending removal keeps the region of the employee now signed in '
        'with HR on, and removes the previous one', () async {
      port.seed('omni_office_acme_5'); // the previous employee's
      port.seed(_region); // already the current one's, same office
      await prefs.setBool('${autoFencePendingPrefix}acme', true);

      final auto = service();
      await auto.sync(appStart: true);

      expect(port.store.keys, [_region]);
      expect(port.removed, ['omni_office_acme_5']);
      expect(port.created, isEmpty); // not re-registered (L3)
      expect(auto.state, AutoPhoneState.on);
    });

    test('a removal still running at the cap keeps its marker until it '
        'succeeds', () async {
      port.seed(_region);
      port.holdRegistered = Completer<void>();
      final auto = service(clearingCap: const Duration(milliseconds: 20));
      await auto.onSessionClearing();
      expect(await prefs.getBool('${autoFencePendingPrefix}acme'), isTrue);

      port.holdRegistered!.complete();
      for (
        var i = 0;
        i < 200 && await prefs.getBool('${autoFencePendingPrefix}acme') != null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(port.store, isEmpty);
      expect(await prefs.getBool('${autoFencePendingPrefix}acme'), isNull);
    });
  });

  test('turn off: a queue that cannot be cleared still disarms (opt-out '
      'saved)', () async {
    final auto = service();
    await auto.sync(appStart: true);
    final throwing = AutoEventQueue(prefs: _QueueThrowingPrefs());
    final off = service(queueOverride: throwing);
    await expectLater(off.turnOffOnThisPhone(), completes);
    expect(await prefs.getBool(autoOptedOutKey(7)), isTrue);
    expect(off.state, AutoPhoneState.optedOut);
    expect(port.store, isEmpty);
    auto.dispose();
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

/// A plugin channel that never answers.
class _StalledPort implements GeofencePort {
  @override
  Future<void> create(Geofence g) => Completer<void>().future;
  @override
  Future<void> reCreateAll() => Completer<void>().future;
  @override
  Future<List<ActiveGeofence>> registered() =>
      Completer<List<ActiveGeofence>>().future;
  @override
  Future<void> removeById(String id) => Completer<void>().future;
}
