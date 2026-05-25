import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import 'face_recognition_engine.dart';
import 'omni_mobile_api.dart';
import 'session_service.dart';

/// On-device face verification.
///
/// The reference (enrolled) face is fetched from Odoo once and cached
/// locally as a JPEG so verification can run without network. Live
/// selfies captured at check-in/out are compared against this cached
/// reference.
///
/// TODO: replace simulate path with a real on-device face matching /
/// liveness SDK. While `DevConstants.simulateFaceRecognition` is
/// true, `verifyFace` returns success after a brief delay and the UI
/// MUST display a "DEV MODE: face recognition simulated" banner —
/// never silently fake this in production.
class FaceRecognitionService extends ChangeNotifier {
  static const _cachedFilename = 'enrolled_face.jpg';

  /// Quality gating ALWAYS uses ML Kit so devs can test the real
  /// "no face / multiple faces / too small / eyes closed" rejections
  /// even with simulateFaceRecognition=true.
  final FaceRecognitionEngine _qualityEngine = MLKitFaceRecognitionEngine();

  /// Identity compare engine — simulated in dev, fail-closed in prod.
  late final FaceRecognitionEngine _compareEngine =
      DevConstants.simulateFaceRecognition
          ? SimulatedFaceRecognitionEngine()
          : MLKitFaceRecognitionEngine();

  bool _enginesReady = false;
  Future<void> _ensureEnginesReady() async {
    if (_enginesReady) return;
    await _qualityEngine.initialize();
    if (!identical(_qualityEngine, _compareEngine)) {
      await _compareEngine.initialize();
    }
    _enginesReady = true;
  }

  bool? _enrolled;
  bool _reenrollAllowed = false;
  DateTime? _lastEnrolledAt;
  String? _localFacePath;
  bool _loading = false;

  @override
  void dispose() {
    _qualityEngine.dispose();
    if (!identical(_qualityEngine, _compareEngine)) {
      _compareEngine.dispose();
    }
    super.dispose();
  }

  /// True if we know there's an enrolled face server-side. null until
  /// `refreshEnrolledStatus` runs at least once.
  bool? get isEnrolled => _enrolled;
  bool get isReenrollAllowed => _reenrollAllowed;
  DateTime? get lastEnrolledAt => _lastEnrolledAt;
  String? get localFacePath => _localFacePath;
  bool get loading => _loading;
  bool get isSimulated => DevConstants.simulateFaceRecognition;

  /// Run ML Kit quality validation on a freshly-captured image.
  /// Used by FaceCaptureScreen to auto-confirm a good capture (kills
  /// the Retake/Confirm step) and auto-retry a bad one. Delegates to
  /// the quality engine that's always real (ML Kit), regardless of
  /// whether simulate mode is on for the identity-match step.
  Future<FaceQualityResult> checkQuality(String imagePath) async {
    await _ensureEnginesReady();
    return _qualityEngine.checkQuality(imagePath);
  }

  /// Passive anti-spoof / liveness check. Same engine instance as
  /// checkQuality (ML Kit + two TFLite spoof models). Used by
  /// FaceCaptureScreen between the quality gate and pop-with-success
  /// so the user gets immediate feedback when a printed photo / phone
  /// screen is detected.
  ///
  /// See [DevConstants.requireLivenessCheck] — when false, the result
  /// is informational only (callers should NOT block submission). When
  /// true, callers should block on `available && !isLive`.
  Future<FaceLivenessResult> checkLiveness(String imagePath) async {
    await _ensureEnginesReady();
    return _qualityEngine.checkLiveness(imagePath);
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cachedFilename');
  }

  /// Fetch enrollment state from the server. Caches the bytes locally
  /// when an image is present. Safe to call repeatedly.
  Future<void> refreshEnrolledStatus(SessionService session) async {
    if (_loading || !session.isLoggedIn) return;
    _loading = true;
    try {
      final api = _api(session);
      final res = await api.getEnrolledFace();
      final faceB64 = (res['face_image_base64'] ?? '').toString();
      if (faceB64.isNotEmpty) {
        final bytes = base64Decode(faceB64);
        final file = await _cacheFile();
        await file.writeAsBytes(bytes, flush: true);
        _localFacePath = file.path;
        _enrolled = true;
      } else {
        await _wipeLocalCache();
        _enrolled = false;
      }
      _reenrollAllowed = res['face_reenroll_allowed'] == true;
      final lastStr = (res['last_enrolled_at'] ?? '').toString();
      _lastEnrolledAt = lastStr.isNotEmpty
          ? DateTime.tryParse('${lastStr.replaceFirst(' ', 'T')}Z')
          : null;
      notifyListeners();
    } catch (_) {
      // Leave previous state; UI can still try verify against cache.
    } finally {
      _loading = false;
    }
  }

  /// Upload a captured selfie to Odoo as the enrolled reference.
  /// Caches it locally on success. Throws when the image fails the
  /// face-quality gate (no face / multiple faces / too small / eyes
  /// closed) or the passive liveness gate (printed photo / phone
  /// screen replay), when liveness enforcement is on.
  Future<void> enrollFace(SessionService session, String imagePath) async {
    await _ensureEnginesReady();
    final quality = await _qualityEngine.checkQuality(imagePath);
    if (!quality.ok) {
      throw FaceQualityException(quality);
    }
    // Defense-in-depth — the capture screen also runs this check, but
    // re-running here means non-camera enrollment paths (e.g. a
    // future admin-side upload) still get gated.
    if (DevConstants.requireLivenessCheck) {
      final liveness = await _qualityEngine.checkLiveness(imagePath);
      if (liveness.available && !liveness.isLive) {
        throw FaceLivenessException(liveness);
      }
    }
    final api = _api(session);
    final bytes = await File(imagePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final filename = imagePath.split('/').last;
    await api.enrollFace(faceImageBase64: b64, filename: filename);
    final file = await _cacheFile();
    await file.writeAsBytes(bytes, flush: true);
    _localFacePath = file.path;
    _enrolled = true;
    // Server consumed the one-shot permission on success; mirror that
    // locally so the UI re-locks immediately.
    _reenrollAllowed = false;
    _lastEnrolledAt = DateTime.now();
    notifyListeners();
  }

  /// Wipe both server and local copies.
  Future<void> clearEnrolledFace(SessionService session) async {
    final api = _api(session);
    await api.clearEnrolledFace();
    await _wipeLocalCache();
    _enrolled = false;
    _reenrollAllowed = false;
    _lastEnrolledAt = null;
    notifyListeners();
  }

  /// Wipe only the local cache (server enrollment stays intact). Used
  /// from the Profile screen "Clear local face cache" action.
  Future<void> clearLocalCache() async {
    await _wipeLocalCache();
    notifyListeners();
  }

  Future<void> _wipeLocalCache() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _localFacePath = null;
  }

  /// Run quality validation + identity matching on a freshly-captured
  /// selfie against the enrolled reference. Returns a [FaceVerifyResult]:
  ///
  ///   ok=true                        — passed both quality + match
  ///   ok=false, isError=true         — quality failed (no face / multi /
  ///                                    too small / eyes closed) OR
  ///                                    matching not yet implemented
  ///   ok=false, isError=false, score — quality passed, matching ran but
  ///                                    score was below threshold
  Future<FaceVerifyResult> verifyFace(String liveImagePath) async {
    // Dev short-circuit: when simulateFaceRecognition is on we skip
    // ALL gates (enrollment, ML Kit quality, identity match). The
    // simulator has no camera so the capture screen passes us a
    // fake path; trying to read it via ML Kit would error out and
    // block check-in/out testing.
    if (DevConstants.simulateFaceRecognition) {
      return FaceVerifyResult.success(score: null, simulated: true);
    }

    if (_enrolled != true || _localFacePath == null) {
      return FaceVerifyResult.notEnrolled();
    }

    await _ensureEnginesReady();

    // Quality gate. Always real (ML Kit) in production, so devs can
    // test "no face / multiple faces / too small / eyes closed"
    // rejections without disabling simulation.
    final quality = await _qualityEngine.checkQuality(liveImagePath);
    if (!quality.ok) {
      return FaceVerifyResult.qualityFail(quality);
    }

    // Passive liveness gate — catches printed photos / phone-screen
    // replays. The capture screen also runs this check (immediate UX
    // feedback), but re-running here closes the loop for any future
    // non-camera path. Only blocks when the flag is on AND the model
    // is available — shadow-mode rollout stays informational.
    if (DevConstants.requireLivenessCheck) {
      final liveness = await _qualityEngine.checkLiveness(liveImagePath);
      if (liveness.available && !liveness.isLive) {
        return FaceVerifyResult.livenessFail(liveness);
      }
    }

    final compare =
        await _compareEngine.compare(_localFacePath!, liveImagePath);
    final FaceVerifyResult result;
    if (!compare.implemented) {
      result = FaceVerifyResult.error(compare.reason ??
          'On-device identity matching is not yet wired up.');
    } else if (!compare.ok) {
      result = FaceVerifyResult.mismatch(compare.score ?? 0,
          reason: compare.reason);
    } else {
      result = FaceVerifyResult.success(
        score: compare.score,
        simulated: !_compareEngine.isProduction,
      );
    }
    debugPrint(
      'verifyFace result ok=${result.ok} '
      'score=${result.score?.toStringAsFixed(2) ?? "n/a"} '
      'simulated=${result.simulated} '
      'error=${result.errorMessage ?? "-"}',
    );
    return result;
  }

  OmniMobileApi _api(SessionService s) => OmniMobileApi(
        baseUrl: s.clientUrl,
        db: s.clientDb,
        token: s.token,
      );
}

class FaceVerifyResult {
  final bool ok;
  final bool isError;
  final bool simulated;
  final double? score;
  final String? errorMessage;
  final FaceQualityResult? qualityResult;

  FaceVerifyResult({
    required this.ok,
    this.isError = false,
    this.simulated = false,
    this.score,
    this.errorMessage,
    this.qualityResult,
  });

  factory FaceVerifyResult.success({double? score, bool simulated = false}) =>
      FaceVerifyResult(ok: true, score: score, simulated: simulated);

  factory FaceVerifyResult.mismatch(double score, {String? reason}) =>
      FaceVerifyResult(
        ok: false,
        score: score,
        errorMessage: reason ?? 'Face not recognized. Please try again.',
      );

  factory FaceVerifyResult.qualityFail(FaceQualityResult q) =>
      FaceVerifyResult(
        ok: false,
        isError: true,
        qualityResult: q,
        errorMessage: q.friendlyMessage,
      );

  factory FaceVerifyResult.livenessFail(FaceLivenessResult l) =>
      FaceVerifyResult(
        ok: false,
        isError: true,
        errorMessage: l.errorMessage ??
            'Live photo check failed. Try again in better light.',
      );

  factory FaceVerifyResult.notEnrolled() => FaceVerifyResult(
        ok: false,
        isError: true,
        errorMessage: 'No enrolled face yet. Enroll one in Profile.',
      );

  factory FaceVerifyResult.error(String message) => FaceVerifyResult(
        ok: false,
        isError: true,
        errorMessage: message,
      );
}

/// Thrown by enrollFace when the captured selfie doesn't pass the
/// on-device quality gate (no face / multiple faces / too small / eyes
/// closed). UI layer should catch and surface q.friendlyMessage.
class FaceQualityException implements Exception {
  final FaceQualityResult result;
  FaceQualityException(this.result);
  @override
  String toString() => result.friendlyMessage;
}

/// Thrown by enrollFace when the captured selfie fails the passive
/// anti-spoof check (printed photo / phone-screen replay) while
/// liveness enforcement is on. UI layer catches and surfaces the
/// non-accusatory friendly message.
class FaceLivenessException implements Exception {
  final FaceLivenessResult result;
  FaceLivenessException(this.result);
  @override
  String toString() =>
      result.errorMessage ?? 'Live photo verification failed.';
}
