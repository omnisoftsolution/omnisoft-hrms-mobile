/// Result of the face capture flow.
///
/// faceVerified currently means "selfie was captured successfully" —
/// it does NOT yet mean a real face match has been performed.
///
/// TODO: replace with real face matching/liveness SDK. When that
/// happens, faceVerified should reflect actual match against the
/// employee's enrolled template.
class FaceCaptureResult {
  final bool success;
  final bool faceVerified;
  final String? imagePath;
  final String? errorMessage;

  /// Camera shots this capture used (1.34.1, P3): one per quality /
  /// liveness try inside the capture, the last one included. A punch
  /// counts them against its shared budget of
  /// `AttendanceActionController.maxFaceAttempts`.
  final int attempts;

  FaceCaptureResult({
    required this.success,
    required this.faceVerified,
    this.imagePath,
    this.errorMessage,
    this.attempts = 1,
  });

  factory FaceCaptureResult.success(String imagePath, {int attempts = 1}) =>
      FaceCaptureResult(
        success: true,
        faceVerified: true,
        imagePath: imagePath,
        attempts: attempts,
      );

  factory FaceCaptureResult.cancelled() =>
      FaceCaptureResult(success: false, faceVerified: false);

  factory FaceCaptureResult.error(String message, {int attempts = 1}) =>
      FaceCaptureResult(
        success: false,
        faceVerified: false,
        errorMessage: message,
        attempts: attempts,
      );
}
