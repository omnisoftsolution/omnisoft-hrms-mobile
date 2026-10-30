import 'package:flutter_test/flutter_test.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:omni_hr/models/auto_attendance_config.dart';
import 'package:omni_hr/services/auto/auto_fence.dart';

/// Keeps what [create] was given and answers [registered] from it, like the
/// plugin does (same id overwrites).
class _FakePort implements GeofencePort {
  final Map<String, Geofence> store = {};
  final List<Geofence> created = [];
  final List<String> removed = [];

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

  /// A region the plugin knows without this fake having created it.
  void seed(String id, {double lat = 1.3, double lng = 103.8, double r = 100}) {
    store[id] = Geofence(
      id: id,
      location: Location(latitude: lat, longitude: lng),
      radiusMeters: r,
      triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
      iosSettings: const IosGeofenceSettings(),
      androidSettings: const AndroidGeofenceSettings(initialTriggers: {}),
    );
  }
}

AutoAttendanceConfig _config({
  double lat = 1.352083,
  double lng = 103.819836,
  int areaM = 150,
  int dwellMin = 5,
}) =>
    AutoAttendanceConfig(
      trigger: AutoTrigger.location,
      dwellMin: dwellMin,
      exitMin: 10,
      office: AutoOffice(
        name: 'HQ',
        latitude: lat,
        longitude: lng,
        areaM: areaM,
      ),
      wifiRequired: false,
    );

void main() {
  late _FakePort port;
  late AutoFence fence;

  setUp(() {
    port = _FakePort();
    fence = AutoFence(port: port, isAndroid: false);
  });

  Future<bool> sync(
    AutoAttendanceConfig? config, {
    String db = 'acme',
    int employeeId = 7,
    bool always = true,
  }) =>
      fence.sync(
        db: db,
        employeeId: employeeId,
        config: config,
        alwaysGranted: always,
      );

  test('region id is omni_office_<db>_<employee>', () {
    expect(AutoFence.regionId('acme', 7), 'omni_office_acme_7');
  });

  test('arms once and is a no-op on the second sync', () async {
    expect(await sync(_config()), isTrue);
    expect(await sync(_config()), isTrue);
    expect(await sync(_config()), isTrue);

    expect(port.created, hasLength(1));
    expect(port.removed, isEmpty);
    final g = port.created.single;
    expect(g.id, 'omni_office_acme_7');
    expect(g.location.latitude, 1.352083);
    expect(g.location.longitude, 103.819836);
    expect(g.radiusMeters, 150);
    expect(g.triggers, {GeofenceEvent.enter, GeofenceEvent.exit});
    expect(g.iosSettings.initialTrigger, isFalse);
  });

  test('a centre that differs below 6 decimals does not re-arm', () async {
    await sync(_config(lat: 1.3520831));
    await sync(_config(lat: 1.3520834));
    expect(port.created, hasLength(1));
  });

  test('re-creates when area_m changes', () async {
    await sync(_config(areaM: 150));
    await sync(_config(areaM: 200));
    expect(port.created, hasLength(2));
    expect(port.store['omni_office_acme_7']!.radiusMeters, 200);
    expect(port.store, hasLength(1));
  });

  test('re-creates when the centre moves', () async {
    await sync(_config());
    await sync(_config(lng: 103.820836));
    expect(port.created, hasLength(2));
    expect(port.store['omni_office_acme_7']!.location.longitude, 103.820836);
  });

  test('removes the region when config becomes null', () async {
    await sync(_config());
    expect(await sync(null), isFalse);
    expect(port.store, isEmpty);
    expect(port.created, hasLength(1));
  });

  test('removes a stale region of another employee in the same db', () async {
    port.seed('omni_office_acme_3');
    expect(await sync(_config(), employeeId: 7), isTrue);
    expect(port.store.keys, ['omni_office_acme_7']);
    expect(port.removed, contains('omni_office_acme_3'));
  });

  test('no region without Always', () async {
    port.seed('omni_office_acme_7');
    expect(await sync(_config(), always: false), isFalse);
    expect(port.store, isEmpty);
    expect(port.created, isEmpty);
  });

  test('leaves regions of other tenants and other plugins alone', () async {
    port.seed('omni_office_other_7');
    port.seed('omni_office_acme_b_7'); // db "acme_b", not "acme"
    port.seed('something_else');
    await sync(_config());
    expect(
      port.store.keys.toSet(),
      {
        'omni_office_other_7',
        'omni_office_acme_b_7',
        'something_else',
        'omni_office_acme_7',
      },
    );
  });

  test('android adds dwell with loitering = dwell_min', () async {
    final android = AutoFence(port: port, isAndroid: true);
    await android.sync(
      db: 'acme',
      employeeId: 7,
      config: _config(dwellMin: 12),
      alwaysGranted: true,
    );
    final g = port.created.single;
    expect(
      g.triggers,
      {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
    );
    expect(g.androidSettings.loiteringDelay, const Duration(minutes: 12));
    expect(g.androidSettings.initialTriggers, isEmpty);
    expect(g.androidSettings.expiration, const Duration(days: 365));
    expect(
      g.androidSettings.notificationResponsiveness,
      const Duration(minutes: 1),
    );
  });

  test('iOS has no dwell trigger', () async {
    await sync(_config());
    expect(port.created.single.triggers, isNot(contains(GeofenceEvent.dwell)));
  });

  test('removeAll removes only this db\'s office regions', () async {
    await sync(_config());
    port.seed('omni_office_acme_9');
    port.seed('omni_office_other_7');
    port.seed('something_else');
    await fence.removeAll('acme');
    expect(port.store.keys.toSet(), {'omni_office_other_7', 'something_else'});
  });
}
