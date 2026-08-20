import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/wifi_info_service.dart';

void main() {
  group('WifiInfoService.normalizeSsid', () {
    test('strips Android double quotes', () {
      expect(WifiInfoService.normalizeSsid('"Office"'), 'Office');
      expect(WifiInfoService.normalizeSsid('Office'), 'Office');
    });
    test('sentinels and empties become null', () {
      expect(WifiInfoService.normalizeSsid('<unknown ssid>'), isNull);
      expect(WifiInfoService.normalizeSsid(''), isNull);
      expect(WifiInfoService.normalizeSsid('""'), isNull);
      expect(WifiInfoService.normalizeSsid(null), isNull);
    });
  });

  group('WifiInfoService.normalizeBssid', () {
    test('pads iOS short octets and lowercases', () {
      expect(WifiInfoService.normalizeBssid('1:2:3:4:5:6'),
          '01:02:03:04:05:06');
      expect(WifiInfoService.normalizeBssid('A4:12:32:0B:1C:9D'),
          'a4:12:32:0b:1c:9d');
    });
    test('redaction sentinel and garbage become null', () {
      expect(WifiInfoService.normalizeBssid('02:00:00:00:00:00'), isNull);
      expect(WifiInfoService.normalizeBssid('2:0:0:0:0:0'), isNull);
      expect(WifiInfoService.normalizeBssid('not-a-mac'), isNull);
      expect(WifiInfoService.normalizeBssid('aa:bb:cc:dd:ee'), isNull);
      expect(WifiInfoService.normalizeBssid(null), isNull);
    });
  });
}
