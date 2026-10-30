import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../models/wifi_info_result.dart';
import '../wifi_info_service.dart';

/// What the phone saw at one moment: one location fix and the connected
/// Wi-Fi. Any part that could not be read is null.
class AutoSample {
  const AutoSample({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.isMocked = false,
    this.ssid,
    this.bssid,
  });

  /// Nothing could be read.
  static const empty = AutoSample();

  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final bool isMocked;
  final String? ssid;
  final String? bssid;
}

/// One high-accuracy fix (bounded by [fixLimit], 8 s) and the Wi-Fi
/// (bounded by [wifiLimit], 3 s, read at the same time). Never asks for a
/// permission (it runs in a background wake) and never throws: a failed
/// part comes back as nulls. [fix] and [wifi] are test seams.
Future<AutoSample> sampleNow({
  Future<Position> Function()? fix,
  Future<WifiInfoResult> Function()? wifi,
  Duration fixLimit = const Duration(seconds: 8),
  Duration wifiLimit = const Duration(seconds: 3),
}) async {
  final wifiF = _bounded(wifi ?? WifiInfoService().getCurrent, wifiLimit);
  final position = await _bounded(
    fix ?? () => _highAccuracyFix(fixLimit),
    fixLimit,
  );
  final w = await wifiF;
  final ready = w != null && w.isReady;
  return AutoSample(
    latitude: position?.latitude,
    longitude: position?.longitude,
    accuracy: position?.accuracy,
    isMocked: position?.isMocked ?? false,
    ssid: ready ? w.ssid : null,
    bssid: ready ? w.bssid : null,
  );
}

Future<Position> _highAccuracyFix(Duration limit) =>
    Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: limit,
      ),
    );

/// [read] or null when it throws or does not answer within [limit].
Future<T?> _bounded<T>(Future<T> Function() read, Duration limit) async {
  try {
    return await read().timeout(limit);
  } catch (_) {
    return null;
  }
}
