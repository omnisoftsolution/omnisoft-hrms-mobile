import 'package:network_info_plus/network_info_plus.dart';

import '../models/wifi_info_result.dart';

/// Reads the connected Wi-Fi network's SSID/BSSID for the attendance
/// network gate (spec 2026-08-03). Mirrors LocationService: one public
/// method, never throws, single-flight, normalized values or null.
///
/// Platform notes:
/// - Android returns the SSID quote-wrapped ('"Office"') and the
///   literal `<unknown ssid>` / `02:00:00:00:00:00` sentinels when the
///   app lacks fine location or the Location toggle is off. We cannot
///   distinguish "not connected" from "unreadable" there — both map to
///   notConnected, and the user message covers both.
/// - iOS needs the Access Wi-Fi Information entitlement + precise
///   location; without them everything is null (→ notConnected). BSSID
///   may be null even when the SSID reads fine (iOS 26).
class WifiInfoService {
  static Future<WifiInfoResult>? _inFlight;

  Future<WifiInfoResult> getCurrent() async {
    final pending = _inFlight;
    if (pending != null) return pending;
    final fresh = _run();
    _inFlight = fresh;
    try {
      return await fresh;
    } finally {
      if (identical(_inFlight, fresh)) {
        _inFlight = null;
      }
    }
  }

  Future<WifiInfoResult> _run() async {
    try {
      final info = NetworkInfo();
      final ssid = normalizeSsid(await info.getWifiName());
      final bssid = normalizeBssid(await info.getWifiBSSID());
      if (ssid == null) return const WifiInfoResult.notConnected();
      return WifiInfoResult.ready(ssid: ssid, bssid: bssid);
    } catch (e) {
      return WifiInfoResult.unreadable(e.toString());
    }
  }

  /// '"Office"' → 'Office'; '`<unknown ssid>`'/empty → null.
  static String? normalizeSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty || s == '<unknown ssid>') return null;
    return s;
  }

  /// '1:2:3:4:5:6' → '01:02:03:04:05:06'; redaction sentinel and
  /// malformed MACs → null. Must stay in lockstep with the server's
  /// attendance_net.normalize_bssid.
  static String? normalizeBssid(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().toLowerCase().split(':');
    if (parts.length != 6) return null;
    final hexOctet = RegExp(r'^[0-9a-f]{1,2}$');
    if (!parts.every(hexOctet.hasMatch)) return null;
    final bssid = parts.map((p) => p.padLeft(2, '0')).join(':');
    if (bssid == '02:00:00:00:00:00') return null;
    return bssid;
  }
}
