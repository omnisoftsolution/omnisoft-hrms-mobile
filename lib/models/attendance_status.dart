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
  });

  bool get hasGeofence =>
      officeLatitude != null && officeLongitude != null;

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
