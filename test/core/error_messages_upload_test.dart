import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/screens/face_scan/face_enrollment_screen.dart';
import 'package:omni_hr/services/face_recognition_engine.dart';
import 'package:omni_hr/services/face_recognition_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  String text(String code) => friendlyError(ApiException(code));

  // CX-6: server codes that reached the screen verbatim.
  test('leave, attachment, auth and face upload codes read as sentences', () {
    expect(
      text('leave_type_not_found'),
      'This leave type is no longer available. Pull down to refresh.',
    );
    const attach = "That file couldn't be attached. Try another file.";
    expect(text('invalid_attachment'), attach);
    expect(text('invalid_attachment_encoding'), attach);
    expect(text('attachment_too_large'), 'That file is too large. Pick a smaller one.');
    expect(
      text('auth_exception'),
      "We couldn't check your sign-in just now. Try again.",
    );
    const retake = "The photo didn't upload correctly. Please retake it.";
    expect(text('missing_face_image'), retake);
    expect(text('invalid_face_image_encoding'), retake);
    expect(
      text('face_image_too_large'),
      'The photo is too large. Please retake it.',
    );
    expect(
      text('face_reenrollment_not_allowed'),
      'Face re-enrollment is not allowed. Please contact HR.',
    );
  });

  group('face enrollment errors', () {
    test('server codes go through friendlyError', () {
      expect(
        enrollmentErrorText(ApiException('face_image_too_large')),
        'The photo is too large. Please retake it.',
      );
      expect(
        enrollmentErrorText(ApiException('face_reenrollment_not_allowed')),
        'Face re-enrollment is not allowed. Please contact HR.',
      );
    });

    test('local face-quality and liveness messages are kept', () {
      final quality = FaceQualityException(
        FaceQualityResult.fail(FaceQualityIssue.noFace),
      );
      expect(enrollmentErrorText(quality), 'No face detected. Please retake.');
      final live = FaceLivenessException(FaceLivenessResult(
        available: true,
        isLive: false,
        errorMessage: 'Please use a live photo.',
      ));
      expect(enrollmentErrorText(live), 'Please use a live photo.');
    });
  });
}
