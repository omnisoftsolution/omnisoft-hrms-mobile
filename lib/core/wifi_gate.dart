import '../models/attendance_status.dart';
import '../models/wifi_info_result.dart';

/// Client-side fast-fail for the attendance Wi-Fi gate (spec
/// 2026-08-03 §5.2). Returns the server error code the punch would be
/// denied with, or null when the pre-check passes. UX only — the
/// server verdict stays authoritative. Exemptions mirror the server:
/// gate not configured, flexible-location employees, dev bypass.
String? wifiPreCheckErrorCode({
  required AttendanceStatus? status,
  required WifiInfoResult wifi,
  required bool devLocation,
}) {
  final s = status;
  if (devLocation || s == null || !s.wifiRequired || s.flexibleLocation) {
    return null;
  }
  if (!wifi.isReady) return 'wifi_required_missing';
  if (!s.expectedSsids.contains(wifi.ssid)) return 'wifi_not_recognized';
  return null;
}

/// State of the small Wi-Fi icon shown beside the GPS arrow in the GPS
/// Status card. Derived from the same inputs as [wifiPreCheckErrorCode]
/// so the icon can never disagree with the tap-time gate: `bad` iff the
/// pre-check would name a deny code, `hidden` for every exemption the
/// pre-check has (gate not configured, flexible location, dev bypass),
/// `pending` only before the first sample of an active gate.
enum WifiIndicator { hidden, pending, ok, bad }

WifiIndicator wifiIndicator({
  required AttendanceStatus? status,
  required WifiInfoResult? wifi,
  required bool devLocation,
}) {
  final s = status;
  if (devLocation || s == null || !s.wifiRequired || s.flexibleLocation) {
    return WifiIndicator.hidden;
  }
  if (wifi == null) return WifiIndicator.pending;
  return wifiPreCheckErrorCode(
              status: s, wifi: wifi, devLocation: devLocation) ==
          null
      ? WifiIndicator.ok
      : WifiIndicator.bad;
}
