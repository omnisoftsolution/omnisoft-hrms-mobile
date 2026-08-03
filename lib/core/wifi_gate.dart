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
