/// Result of a GPS request. Captured at the start of an attendance
/// check-in/out. Either holds coords + accuracy or an error code that
/// the UI maps to a friendly message.
enum LocationStatus {
  ready, // success — latitude/longitude/accuracy populated
  permissionDenied, // user denied this session
  permissionDeniedForever, // user denied + don't-ask-again
  serviceDisabled, // OS location services off
  timedOut, // could not get a fix in time
  unknown, // any other failure
}

class LocationResult {
  final LocationStatus status;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? errorMessage;
  final bool isDevFallback;
  // Android-only: iOS always returns false (Phase 2b/App Attest covers iOS).
  final bool isMocked;

  LocationResult({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.errorMessage,
    this.isDevFallback = false,
    this.isMocked = false,
  });

  bool get isReady => status == LocationStatus.ready;

  factory LocationResult.ready({
    required double latitude,
    required double longitude,
    double? accuracy,
    bool isDevFallback = false,
    bool isMocked = false,
  }) =>
      LocationResult(
        status: LocationStatus.ready,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        isDevFallback: isDevFallback,
        isMocked: isMocked,
      );

  factory LocationResult.failure(LocationStatus status, String message) =>
      LocationResult(status: status, errorMessage: message);

  String get friendlyMessage {
    switch (status) {
      case LocationStatus.ready:
        return 'Location acquired';
      case LocationStatus.permissionDenied:
        return 'Location permission was denied. Please grant access to check in.';
      case LocationStatus.permissionDeniedForever:
        return 'Location permission is blocked. Enable it in Settings.';
      case LocationStatus.serviceDisabled:
        return 'Location services are turned off on this device.';
      case LocationStatus.timedOut:
        return 'Could not get your location. Please move outdoors and try again.';
      case LocationStatus.unknown:
        return errorMessage ?? 'Could not get your location.';
    }
  }
}
