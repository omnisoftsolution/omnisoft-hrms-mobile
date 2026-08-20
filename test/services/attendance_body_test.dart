import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  group('buildAttendanceBody', () {
    test('includes is_mocked (always) and location_accuracy when present', () {
      final body = buildAttendanceBody(
          latitude: 1.3,
          longitude: 103.8,
          faceVerified: true,
          deviceId: 'DEV1',
          isMocked: true,
          accuracy: 12.5);
      expect(body['latitude'], 1.3);
      expect(body['longitude'], 103.8);
      expect(body['is_mocked'], isTrue);
      expect(body['location_accuracy'], 12.5);
      expect(body['device_id'], 'DEV1');
      expect(body.containsKey('_dev_location'), isFalse);
    });

    test('omits location_accuracy when null, still sends is_mocked=false', () {
      final body = buildAttendanceBody(
          latitude: 1.3, longitude: 103.8, isMocked: false, accuracy: null);
      expect(body.containsKey('location_accuracy'), isFalse);
      expect(body['is_mocked'], isFalse);
    });

    test('omits coords when null (geo off)', () {
      final body = buildAttendanceBody(isMocked: false);
      expect(body.containsKey('latitude'), isFalse);
      expect(body.containsKey('longitude'), isFalse);
      expect(body['is_mocked'], isFalse);
    });

    test('adds _dev_location only when devLocation true', () {
      final body = buildAttendanceBody(
          latitude: 1.3, longitude: 103.8, devLocation: true);
      expect(body['_dev_location'], isTrue);
    });

    test('includes wifi fields when present, omits when null', () {
      final body = buildAttendanceBody(
          latitude: 1.3,
          longitude: 103.8,
          isMocked: false,
          wifiSsid: 'Office-WiFi',
          wifiBssid: '01:02:03:04:05:06');
      expect(body['wifi_ssid'], 'Office-WiFi');
      expect(body['wifi_bssid'], '01:02:03:04:05:06');

      final without = buildAttendanceBody(isMocked: false);
      expect(without.containsKey('wifi_ssid'), isFalse);
      expect(without.containsKey('wifi_bssid'), isFalse);
    });
  });
}
