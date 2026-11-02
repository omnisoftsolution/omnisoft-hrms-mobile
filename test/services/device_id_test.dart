import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceService.resetCacheForTest();
  });

  Future<String?> noVendorId() async => fail('must not read the OS id');

  group('resolveDeviceId', () {
    test('keeps the id an existing phone already stored', () async {
      // Phones from before 1.36 stored the firmware build number; they keep it,
      // so nobody has to go through the new-phone code again.
      SharedPreferences.setMockInitialValues(
          {DeviceService.prefsKey: 'android-BP4A.251205.006'});
      final prefs = await SharedPreferences.getInstance();

      final id = await DeviceService.resolveDeviceId(
          prefs: prefs, platform: 'android', vendorId: noVendorId);

      expect(id, 'android-BP4A.251205.006');
    });

    test('a new Android install gets a random id, not the firmware build', () async {
      final prefs = await SharedPreferences.getInstance();

      final id = await DeviceService.resolveDeviceId(
          prefs: prefs, platform: 'android', vendorId: noVendorId);

      expect(id, matches(RegExp(r'^android-[0-9a-f]{32}$')));
      expect(prefs.getString(DeviceService.prefsKey), id);
    });

    test('two new Android installs get different ids', () async {
      final a = await DeviceService.resolveDeviceId(
          prefs: await SharedPreferences.getInstance(),
          platform: 'android',
          vendorId: noVendorId);
      SharedPreferences.setMockInitialValues({});
      final b = await DeviceService.resolveDeviceId(
          prefs: await SharedPreferences.getInstance(),
          platform: 'android',
          vendorId: noVendorId);

      expect(a, isNot(b));
    });

    test('iOS still uses identifierForVendor', () async {
      final prefs = await SharedPreferences.getInstance();

      final id = await DeviceService.resolveDeviceId(
          prefs: prefs, platform: 'ios', vendorId: () async => 'ABC-123');

      expect(id, 'ios-ABC-123');
    });

    test('iOS without identifierForVendor falls back to a random id', () async {
      final prefs = await SharedPreferences.getInstance();

      final id = await DeviceService.resolveDeviceId(
          prefs: prefs, platform: 'ios', vendorId: () async => null);

      expect(id, matches(RegExp(r'^ios-[0-9a-f]{32}$')));
    });
  });
}
