import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns a stable per-device identifier the backend can record on
/// each attendance entry. Falls back to a generated UUID stored in
/// SharedPreferences when the OS-provided id isn't available.
class DeviceService {
  static const _prefKey = 'omni_hr_device_id';
  static String? _cached;

  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    String? id;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        // identifierForVendor changes when all this vendor's apps are
        // uninstalled, which is acceptable for a device identifier.
        id = ios.identifierForVendor;
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        id = android.id;
      }
    } catch (_) {
      id = null;
    }

    final platform = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'other';
    final finalId = (id != null && id.isNotEmpty)
        ? '$platform-$id'
        : '$platform-${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_prefKey, finalId);
    _cached = finalId;
    return finalId;
  }

  /// Human-readable label the connector shows in the device list,
  /// e.g. "iPhone · iPhone15,2" or "Android · Pixel 8". Falls back to
  /// the platform name alone when the model cannot be read.
  Future<String> getDeviceLabel() async {
    final platform = Platform.isIOS
        ? 'iPhone'
        : Platform.isAndroid
            ? 'Android'
            : Platform.operatingSystem;
    try {
      final info = DeviceInfoPlugin();
      String model = '';
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        model = ios.utsname.machine.isNotEmpty ? ios.utsname.machine : ios.name;
      } else if (Platform.isAndroid) {
        final android = await info.androidInfo;
        model = android.model;
      }
      return model.isNotEmpty ? '$platform · $model' : platform;
    } catch (_) {
      return platform;
    }
  }
}
