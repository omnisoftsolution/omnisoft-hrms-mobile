import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/wifi_gate.dart';
import 'package:omni_hr/models/attendance_status.dart';
import 'package:omni_hr/models/wifi_info_result.dart';

AttendanceStatus _status({
  bool wifiRequired = true,
  List<String> ssids = const ['Office-WiFi'],
  bool flexible = false,
}) =>
    AttendanceStatus.fromJson({
      'checked_in': false,
      'hours_today': 0,
      'employee_id': 1,
      'auth_type': 'session',
      'flexible_location': flexible,
      'network_gate': {'wifi_required': wifiRequired, 'expected_ssids': ssids},
    });

void main() {
  group('wifiPreCheckErrorCode', () {
    test('null when gate not required', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(wifiRequired: false, ssids: const []),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: false),
          isNull);
    });

    test('null for flexible employees', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(flexible: true),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: false),
          isNull);
    });

    test('null under dev location bypass', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: true),
          isNull);
    });

    test('wifi_required_missing when not connected', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: false),
          'wifi_required_missing');
    });

    test('wifi_not_recognized when SSID not expected', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(),
              wifi: const WifiInfoResult.ready(ssid: 'CoffeeShop'),
              devLocation: false),
          'wifi_not_recognized');
    });

    test('null when SSID matches', () {
      expect(
          wifiPreCheckErrorCode(
              status: _status(),
              wifi: const WifiInfoResult.ready(ssid: 'Office-WiFi'),
              devLocation: false),
          isNull);
    });

    test('null when status not loaded yet', () {
      expect(
          wifiPreCheckErrorCode(
              status: null,
              wifi: const WifiInfoResult.notConnected(),
              devLocation: false),
          isNull);
    });
  });

  group('wifiIndicator', () {
    test('hidden when gate not required, status missing, flexible, or dev',
        () {
      expect(
          wifiIndicator(
              status: _status(wifiRequired: false, ssids: const []),
              wifi: null,
              devLocation: false),
          WifiIndicator.hidden);
      expect(wifiIndicator(status: null, wifi: null, devLocation: false),
          WifiIndicator.hidden);
      expect(
          wifiIndicator(
              status: _status(flexible: true), wifi: null, devLocation: false),
          WifiIndicator.hidden);
      expect(
          wifiIndicator(
              status: _status(),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: true),
          WifiIndicator.hidden);
    });

    test('pending before the first sample', () {
      expect(wifiIndicator(status: _status(), wifi: null, devLocation: false),
          WifiIndicator.pending);
    });

    test('ok on a recognized office SSID', () {
      expect(
          wifiIndicator(
              status: _status(),
              wifi: const WifiInfoResult.ready(ssid: 'Office-WiFi'),
              devLocation: false),
          WifiIndicator.ok);
    });

    test('bad when not connected or on an unrecognized network', () {
      expect(
          wifiIndicator(
              status: _status(),
              wifi: const WifiInfoResult.notConnected(),
              devLocation: false),
          WifiIndicator.bad);
      expect(
          wifiIndicator(
              status: _status(),
              wifi: const WifiInfoResult.ready(ssid: 'Neighbor'),
              devLocation: false),
          WifiIndicator.bad);
    });

    test('never disagrees with the tap-time pre-check', () {
      // ok  <=> pre-check passes; bad <=> pre-check names a deny code.
      for (final wifi in const [
        WifiInfoResult.notConnected(),
        WifiInfoResult.unreadable('permission denied'),
        WifiInfoResult.ready(ssid: 'Office-WiFi'),
        WifiInfoResult.ready(ssid: 'Neighbor'),
      ]) {
        final code = wifiPreCheckErrorCode(
            status: _status(), wifi: wifi, devLocation: false);
        final ind =
            wifiIndicator(status: _status(), wifi: wifi, devLocation: false);
        expect(ind == WifiIndicator.bad, code != null, reason: '$wifi');
      }
    });
  });
}
