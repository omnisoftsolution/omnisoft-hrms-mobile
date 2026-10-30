/// What decides an automatic check-in: the office region alone, or the
/// region plus the office Wi-Fi. Wire values `location` / `location_wifi`.
enum AutoTrigger {
  locationWifi('location_wifi'),
  location('location');

  const AutoTrigger(this.wire);

  /// The value the connector sends and the app stores.
  final String wire;

  /// An unknown or missing value reads as [locationWifi], the stricter one.
  static AutoTrigger parse(Object? value) =>
      value == 'location' ? location : locationWifi;
}

/// The office region of an `auto_attendance` block.
class AutoOffice {
  const AutoOffice({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.areaM,
  });

  final String name;
  final double latitude;
  final double longitude;

  /// Radius of the region in metres; always > 0.
  final int areaM;

  Map<String, dynamic> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'area_m': areaM,
      };
}

/// The `employee.auto_attendance` block of a /login or /me body (connector
/// 2.66.0+). An absent block means automatic attendance is off for this
/// employee. Stored as JSON under `employee_auto_attendance`, so
/// [toJson] must round-trip [fromJson]: a background isolate reads it back.
class AutoAttendanceConfig {
  const AutoAttendanceConfig({
    required this.trigger,
    required this.dwellMin,
    required this.exitMin,
    required this.office,
    required this.wifiRequired,
  });

  final AutoTrigger trigger;

  /// Minutes inside the region before an arrival counts (Android dwell).
  final int dwellMin;

  /// Minutes outside the region before a departure counts.
  final int exitMin;

  final AutoOffice office;

  /// The check-in waits for the office Wi-Fi.
  final bool wifiRequired;

  /// The block, or null when [json] is not a usable block: not a map, no
  /// office, a coordinate that is missing or not finite, or `area_m <= 0`.
  static AutoAttendanceConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final office = json['office'];
    if (office is! Map) return null;
    final lat = office['latitude'];
    final lng = office['longitude'];
    final area = office['area_m'];
    if (lat is! num || lng is! num || area is! num) return null;
    if (!lat.isFinite || !lng.isFinite || !area.isFinite) return null;
    final areaM = area.toInt();
    if (areaM <= 0) return null;
    final trigger = AutoTrigger.parse(json['trigger']);
    final wifi = json['wifi_required'];
    return AutoAttendanceConfig(
      trigger: trigger,
      dwellMin: _minutes(json['dwell_min'], 5),
      exitMin: _minutes(json['exit_min'], 10),
      office: AutoOffice(
        name: office['name']?.toString() ?? '',
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        areaM: areaM,
      ),
      wifiRequired: wifi is bool ? wifi : trigger == AutoTrigger.locationWifi,
    );
  }

  static int _minutes(Object? v, int fallback) =>
      v is num && v.isFinite ? v.toInt() : fallback;

  Map<String, dynamic> toJson() => {
        'trigger': trigger.wire,
        'dwell_min': dwellMin,
        'exit_min': exitMin,
        'office': office.toJson(),
        'wifi_required': wifiRequired,
      };

  /// Identifies the region: a change in centre or radius re-arms it.
  String get signature =>
      '${office.latitude.toStringAsFixed(6)},'
      '${office.longitude.toStringAsFixed(6)},${office.areaM}';
}
