import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/constants.dart';
import 'package:omni_hr/models/face_capture_result.dart';
import 'package:omni_hr/models/location_result.dart';
import 'package:omni_hr/models/wifi_info_result.dart';
import 'package:omni_hr/services/attendance_action_controller.dart';
import 'package:omni_hr/services/face_recognition_engine.dart';
import 'package:omni_hr/services/face_recognition_service.dart';
import 'package:omni_hr/models/attendance_status.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The production engine's real `compare()`, with the embeddings scripted:
/// the enrolled image always yields one; the live image yields [live]
/// (null = extraction failed: no face, INFER_FAIL, …).
class _Engine extends MLKitFaceRecognitionEngine {
  _Engine(this.live);

  final List<double>? live;

  @override
  Future<List<double>?> extractEmbedding(String imagePath) async =>
      imagePath == 'enrolled' ? const [1.0, 0.0] : live;
}

class _Api extends OmniMobileApi {
  _Api() : super(baseUrl: '', db: '', token: '');

  int checkIns = 0;

  @override
  Future<AttendanceStatus> getAttendanceStatus() async =>
      AttendanceStatus.fromJson({
        'checked_in': false,
        'hours_today': 0,
        'employee_id': 1,
        'auth_type': 'app',
      });

  @override
  Future<Map<String, dynamic>> checkIn({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
    bool isMocked = false,
    double? accuracy,
    String? wifiSsid,
    String? wifiBssid,
  }) async {
    checkIns++;
    return const {};
  }
}

/// engine.compare → FaceVerifyResult.fromCompare (the service's mapping)
/// → the controller's retry loop.
Future<({AttendanceActionOutcome? outcome, int captures, int checkIns})> _punch(
  List<double>? live,
) async {
  final engine = _Engine(live);
  final api = _Api();
  final controller = AttendanceActionController(
    session: SessionService(),
    apiBuilder: (_) => api,
    getLocation: () async => LocationResult(
      status: LocationStatus.ready,
      latitude: 1.3,
      longitude: 103.8,
      accuracy: 5,
    ),
    getWifi: () async => const WifiInfoResult.ready(ssid: 'office'),
    getDeviceId: () async => 'device-1',
    isEnrolled: () => true,
    verifyFace: (path) async =>
        FaceVerifyResult.fromCompare(await engine.compare('enrolled', path)),
    refreshEnrolled: () async {},
    devLocation: false,
    simulateFace: false,
  );
  await controller.refreshStatus();
  var captures = 0;
  final outcome = await controller.perform(
    captureFace: (_) async {
      captures++;
      return FaceCaptureResult.success('live-$captures');
    },
    enrol: () async {},
  );
  return (outcome: outcome, captures: captures, checkIns: api.checkIns);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('engine failure is an error, not a mismatch (1.34.1)', () {
    test(
      'a live image without an embedding: compare failed, no score',
      () async {
        final c = await _Engine(null).compare('enrolled', 'live');
        expect(c.ok, isFalse);
        expect(c.failed, isTrue);
        expect(c.score, isNull);
        final v = FaceVerifyResult.fromCompare(c);
        expect(v.ok, isFalse);
        expect(v.isError, isTrue);
      },
    );

    test('a completed comparison below the threshold is a mismatch', () async {
      // cosine 0 < faceMatchThreshold
      final c = await _Engine(const [0.0, 1.0]).compare('enrolled', 'live');
      expect(c.failed, isFalse);
      expect(c.score, lessThan(DevConstants.faceMatchThreshold));
      final v = FaceVerifyResult.fromCompare(c);
      expect(v.ok, isFalse);
      expect(v.isError, isFalse);
    });

    test('engine → service → controller: an extraction failure ends the '
        'punch after one capture, nothing sent', () async {
      final r = await _punch(null);
      expect(r.outcome?.error, isNotNull);
      expect(r.captures, 1);
      expect(r.checkIns, 0);
    });

    test('engine → service → controller: a real mismatch is retried up to '
        'the budget, nothing sent', () async {
      final r = await _punch(const [0.0, 1.0]);
      expect(r.outcome?.error, 'Face not recognized. Please try again.');
      expect(r.captures, AttendanceActionController.maxFaceAttempts);
      expect(r.checkIns, 0);
    });

    test('engine → service → controller: a match punches once', () async {
      final r = await _punch(const [1.0, 0.0]);
      expect(r.outcome?.ok, isTrue);
      expect(r.captures, 1);
      expect(r.checkIns, 1);
    });

    test('not implemented stays an error', () {
      final v = FaceVerifyResult.fromCompare(
        FaceCompareResult.notImplemented(),
      );
      expect(v.isError, isTrue);
    });
  });
}
