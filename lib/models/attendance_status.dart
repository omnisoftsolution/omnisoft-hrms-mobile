class AttendanceStatus {
  final bool checkedIn;
  final String? currentCheckInTime;
  final String? lastCheckInTime;
  final double hoursToday;
  final int employeeId;
  final String authType;

  /// Configured office geofence (when set on the employee's Work
  /// Address). Used by the home screen to render an idle "Office · 12m"
  /// chip. All four are null when no geofence is configured.
  final double? officeLatitude;
  final double? officeLongitude;
  final double? officeRadiusMeters;
  final String? geofenceSource;

  /// True when HR marked this employee as flexible work location — the
  /// server accepts punches outside the office geofence (logging the
  /// coordinates), so the client must not fast-fail or grey the button.
  final bool flexibleLocation;

  /// Attendance network gate (spec 2026-08-03): when [wifiRequired],
  /// the client pre-checks the connected SSID against [expectedSsids]
  /// before face capture. Server verdict stays authoritative.
  final bool wifiRequired;
  final List<String> expectedSsids;

  AttendanceStatus({
    required this.checkedIn,
    this.currentCheckInTime,
    this.lastCheckInTime,
    required this.hoursToday,
    required this.employeeId,
    required this.authType,
    this.officeLatitude,
    this.officeLongitude,
    this.officeRadiusMeters,
    this.geofenceSource,
    this.flexibleLocation = false,
    this.wifiRequired = false,
    this.expectedSsids = const [],
  });

  bool get hasGeofence =>
      officeLatitude != null && officeLongitude != null;

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    final gate = json['network_gate'];
    final gateMap =
        gate is Map<String, dynamic> ? gate : const <String, dynamic>{};

    return AttendanceStatus(
      checkedIn: json['checked_in'] == true,
      currentCheckInTime: json['current_check_in_time']?.toString(),
      lastCheckInTime: json['last_check_in_time']?.toString(),
      hoursToday: (json['hours_today'] ?? 0).toDouble(),
      employeeId: json['employee_id'] ?? 0,
      authType: json['auth_type'] ?? '',
      officeLatitude: (json['office_latitude'] as num?)?.toDouble(),
      officeLongitude: (json['office_longitude'] as num?)?.toDouble(),
      officeRadiusMeters:
          (json['office_radius_meters'] as num?)?.toDouble(),
      geofenceSource: json['geofence_source']?.toString(),
      flexibleLocation: json['flexible_location'] == true,
      wifiRequired: gateMap['wifi_required'] == true,
      expectedSsids: (gateMap['expected_ssids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
