import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns a stable per-install identifier the backend can record on
/// each attendance entry, stored once in SharedPreferences.
class DeviceService {
  /// Read by the automatic check-in background wake, which must use the id
  /// already stored (never mint a new one there).
  static const prefsKey = 'omni_hr_device_id';
  static const _prefKey = prefsKey;
  static String? _cached;

  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    final platform = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'other';
    _cached = await resolveDeviceId(
      prefs: await SharedPreferences.getInstance(),
      platform: platform,
      vendorId: () async =>
          // identifierForVendor changes when all this vendor's apps are
          // uninstalled, which is acceptable for a device identifier.
          Platform.isIOS ? (await DeviceInfoPlugin().iosInfo).identifierForVendor : null,
    );
    return _cached!;
  }

  /// The stored id wins, so a phone keeps the id the server already knows.
  /// Otherwise iOS uses identifierForVendor; Android (and iOS without one)
  /// gets a random id per install. Android's `androidInfo.id` is not used: it
  /// is Build.ID, the same for every phone on the same firmware.
  @visibleForTesting
  static Future<String> resolveDeviceId({
    required SharedPreferences prefs,
    required String platform,
    required Future<String?> Function() vendorId,
  }) async {
    final stored = prefs.getString(_prefKey);
    if (stored != null && stored.isNotEmpty) return stored;

    String? id;
    if (platform == 'ios') {
      try {
        id = await vendorId();
      } catch (_) {
        id = null;
      }
    }
    final finalId = '$platform-${(id != null && id.isNotEmpty) ? id : _randomInstallId()}';
    await prefs.setString(_prefKey, finalId);
    return finalId;
  }

  static String _randomInstallId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  @visibleForTesting
  static void resetCacheForTest() => _cached = null;

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
