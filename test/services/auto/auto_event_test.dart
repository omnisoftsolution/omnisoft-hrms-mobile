import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/auto/auto_event.dart';

AutoEvent _event({
  DateTime? at,
  AutoSource source = AutoSource.geofence,
  String uid = 'a-0123456789abcdef01234567',
}) => AutoEvent(
  eventUid: uid,
  kind: AutoKind.arrive,
  eventAt: at ?? DateTime.utc(2026, 10, 30, 0, 47, 5),
  latitude: 1.3,
  longitude: 103.8,
  accuracy: 12.5,
  isMocked: false,
  wifiSsid: 'Office',
  wifiBssid: 'aa:bb:cc:dd:ee:ff',
  deviceId: 'dev-1',
  appVersion: '1.36.0',
  source: source,
);

void main() {
  test('toBody formats event_at as naive UTC', () {
    final local = DateTime.parse('2026-10-30T08:47:05+08:00');
    final body = _event(at: local).toBody();
    expect(body['event_at'], '2026-10-30 00:47:05');
  });

  test('toBody has exactly the contract keys', () {
    final body = _event(source: AutoSource.dwell).toBody();
    expect(body.keys.toSet(), {
      'event_uid',
      'kind',
      'event_at',
      'latitude',
      'longitude',
      'location_accuracy',
      'is_mocked',
      'wifi_ssid',
      'wifi_bssid',
      'device_id',
      'app_version',
      'source',
    });
    expect(body['kind'], 'arrive');
    expect(body['location_accuracy'], 12.5);
  });

  test("toBody omits source for geofence, sends 'dwell'", () {
    expect(_event().toBody().containsKey('source'), isFalse);
    expect(_event(source: AutoSource.dwell).toBody()['source'], 'dwell');
    expect(
      _event(source: AutoSource.foreground).toBody()['source'],
      'foreground',
    );
  });

  test('toBody sends null coordinates as null', () {
    final e = AutoEvent(
      eventUid: 'a-0123456789abcdef01234567',
      kind: AutoKind.leave,
      eventAt: DateTime.utc(2026, 10, 30),
      isMocked: false,
      deviceId: 'd',
      appVersion: '1.36.0',
      source: AutoSource.recheck,
    );
    final body = e.toBody();
    expect(body['kind'], 'leave');
    for (final k in [
      'latitude',
      'longitude',
      'location_accuracy',
      'wifi_ssid',
      'wifi_bssid',
    ]) {
      expect(body.containsKey(k), isTrue, reason: k);
      expect(body[k], isNull, reason: k);
    }
  });

  test('toJson / fromJson round trip', () {
    final e = _event(source: AutoSource.wifi);
    final back = AutoEvent.fromJson(e.toJson());
    expect(back.toBody(), e.toBody());
    expect(back.eventAt.isUtc, isTrue);
    expect(back.source, AutoSource.wifi);
    expect(back.kind, AutoKind.arrive);
  });

  test('the owner is kept in the queue but never sent (R136-F03)', () {
    final e = AutoEvent.fromJson({..._event().toJson(), 'owner': 'acme|7'});
    expect(e.owner, 'acme|7');
    expect(AutoEvent.fromJson(e.toJson()).owner, 'acme|7');
    expect(e.toBody().containsKey('owner'), isFalse);
    expect(_event().owner, isNull);
  });

  test(r'newUid matches ^a-[0-9a-f]{24}$', () {
    final re = RegExp(r'^a-[0-9a-f]{24}$');
    final uids = {for (var i = 0; i < 50; i++) AutoEvent.newUid()};
    expect(uids.length, 50);
    for (final u in uids) {
      expect(re.hasMatch(u), isTrue, reason: u);
    }
  });
}
