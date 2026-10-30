import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/auto_attendance_config.dart';

Map<String, dynamic> _block({
  String trigger = 'location',
  Object? office,
}) =>
    {
      'trigger': trigger,
      'dwell_min': 5,
      'exit_min': 10,
      'office': office ??
          {
            'name': 'NOVAWORKS HQ',
            'latitude': 1.2894,
            'longitude': 103.847,
            'area_m': 150,
          },
      'wifi_required': false,
    };

void main() {
  test('fromJson parses the contract block', () {
    final c = AutoAttendanceConfig.fromJson(_block())!;
    expect(c.trigger, AutoTrigger.location);
    expect(c.dwellMin, 5);
    expect(c.exitMin, 10);
    expect(c.office.name, 'NOVAWORKS HQ');
    expect(c.office.latitude, 1.2894);
    expect(c.office.longitude, 103.847);
    expect(c.office.areaM, 150);
    expect(c.wifiRequired, isFalse);
  });

  test('fromJson returns null for null, {}, missing office, area_m 0', () {
    expect(AutoAttendanceConfig.fromJson(null), isNull);
    expect(AutoAttendanceConfig.fromJson('nope'), isNull);
    expect(AutoAttendanceConfig.fromJson(<String, dynamic>{}), isNull);
    expect(AutoAttendanceConfig.fromJson({'trigger': 'location'}), isNull);
    expect(
        AutoAttendanceConfig.fromJson(_block(office: {
          'name': 'X',
          'latitude': 1.0,
          'longitude': 2.0,
          'area_m': 0,
        })),
        isNull);
    expect(
        AutoAttendanceConfig.fromJson(_block(office: {
          'name': 'X',
          'latitude': double.nan,
          'longitude': 2.0,
          'area_m': 100,
        })),
        isNull);
    expect(
        AutoAttendanceConfig.fromJson(_block(office: {
          'name': 'X',
          'latitude': 1.0,
          'longitude': double.infinity,
          'area_m': 100,
        })),
        isNull);
    expect(
        AutoAttendanceConfig.fromJson(_block(office: {
          'name': 'X',
          'latitude': 1.0,
          'longitude': 2.0,
          'area_m': -5,
        })),
        isNull);
  });

  test('unknown trigger falls back to locationWifi', () {
    expect(AutoAttendanceConfig.fromJson(_block(trigger: 'bluetooth'))!.trigger,
        AutoTrigger.locationWifi);
    expect(
        AutoAttendanceConfig.fromJson(_block(trigger: 'location_wifi'))!
            .trigger,
        AutoTrigger.locationWifi);
  });

  test('toJson round-trips fromJson', () {
    final c = AutoAttendanceConfig.fromJson(_block())!;
    final again = AutoAttendanceConfig.fromJson(c.toJson())!;
    expect(again.toJson(), c.toJson());
    expect(again.signature, c.signature);
    final wifi = AutoAttendanceConfig.fromJson(
        _block(trigger: 'location_wifi')..['wifi_required'] = true)!;
    expect(AutoAttendanceConfig.fromJson(wifi.toJson())!.toJson(), wifi.toJson());
  });

  test('signature is lat,lng to 6 decimals and the radius', () {
    expect(AutoAttendanceConfig.fromJson(_block())!.signature,
        '1.289400,103.847000,150');
  });
}
