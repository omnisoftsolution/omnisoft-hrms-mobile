import 'package:package_info_plus/package_info_plus.dart';

/// App-level defaults. Originally "DevConstants" — a few entries
/// here are now production defaults (saasUrl) while others are
/// genuinely DEV-only (useDevLocation, simulateFaceRecognition).
class DevConstants {
  /// Empty by default. The hint on the input field tells the user
  /// to get the code from their HR administrator.
  static const String defaultCompanyCode = '';

  /// Production default: the Omnisoft-hosted SaaS. Dev can override
  /// at run time via:
  ///   flutter run --dart-define=SAAS_URL=http://192.168.1.17:8069
  static const String defaultSaasUrl = String.fromEnvironment(
    'SAAS_URL',
    defaultValue: 'https://hrmsmanager.omnisoftsolution.com',
  );

  /// Empty by default. The input field's hint tells the user the
  /// expected format. Devs who want a quick prefill during hot-
  /// reload sessions can edit this locally without committing.
  static const String defaultLogin = '';

  static const double fallbackLatitude = 1.2780;
  static const double fallbackLongitude = 103.8450;

  /// DEV ONLY — when true, always use fallback coordinates
  /// instead of real GPS. Set to false for production builds.
  static const bool useDevLocation = false;

  /// DEV ONLY — when false, the receipt attachment requirement on
  /// expense submission is bypassed: the form marks the receipt as
  /// optional, the Submit button enables without a photo, and the
  /// connector accepts the request via the `_dev_skip_receipt: true`
  /// body flag. Same posture as useDevLocation. Set back to true for
  /// production builds.
  static const bool requireReceiptOnExpense = true;

  /// When true, the expense create screen exposes a "Scan receipt"
  /// button (Qwen2.5-VL via self-hosted Ollama on the LAN). Set to
  /// false to hide the button if the OCR backend is unavailable.
  static const bool enableOcrScan = true;

  /// When true, FaceRecognitionService.verifyFace returns success
  /// after a brief delay instead of running real on-device identity
  /// matching. The UI surfaces a "DEV MODE: face recognition
  /// simulated" banner whenever this is on so we never silently
  /// fake production logic.
  ///
  /// Both platforms now run real MobileFaceNet inference:
  ///   - Android: via tflite_flutter (dart:ffi → JNI to
  ///     libtensorflowlite_jni.so).
  ///   - iOS: via a native Swift method-channel plugin
  ///     (ios/Runner/FaceEmbedderPlugin.swift). Bypasses dart:ffi
  ///     because the iOS 26 release-build linker dead-strips the
  ///     TFLite C symbols that ffi looks up via dlsym. The Swift
  ///     plugin uses TensorFlowLiteSwift's Interpreter directly —
  ///     a real Swift-to-C call that the linker can see and keep.
  static bool get simulateFaceRecognition => _simulateFaceRecognitionRaw;

  /// Source-controlled override. Flip to true to disable real face
  /// matching across the board (useful for an emulator that lacks
  /// a working camera). The "DEV MODE" banner is always shown when
  /// this is true so the bypass can never go unnoticed.
  static const bool _simulateFaceRecognitionRaw = false;

  /// Cosine-similarity threshold for treating two face embeddings as
  /// the same person. Sensible defaults for MobileFaceNet sit
  /// between 0.65 and 0.75; tune once a real embedding model is wired
  /// up. Has no effect while a real embedding engine isn't loaded.
  static const double faceMatchThreshold = 0.70;

  /// When true, captures that fail the on-device passive liveness /
  /// anti-spoof check are rejected (the user stays on the camera with
  /// a non-accusatory retry hint, and any non-camera path throws
  /// FaceLivenessException at the service layer).
  ///
  /// When false (default — shadow-mode rollout), the check still runs
  /// and is logged via debugPrint, but the result does NOT block
  /// submission. Use shadow-mode for the first TestFlight build with
  /// the spoof models to verify false-positive rates against real
  /// employees before enforcing.
  ///
  /// Flip to true once the spoof models are bundled AND we've
  /// validated against at least a few testers that real faces don't
  /// false-trigger in typical office lighting.
  static const bool requireLivenessCheck = true;

  /// When true, after every capture the app surfaces an AlertDialog
  /// with the raw spoof-model outputs (argmax, score, both softmaxes)
  /// before navigating away. Lets a tester read+screenshot the numbers
  /// without having to be tethered to a debug console.
  ///
  /// On a TestFlight/internal build only — flip to false before any
  /// customer-facing release. Once we've validated the label mapping
  /// and threshold for real-world inputs, this whole block can be
  /// deleted along with the diagnostic fields on FaceLivenessResult.
  static const bool showLivenessDiagnostic = false;

  /// Minimum side length (px) of the detected face's bounding box,
  /// relative to the shorter side of the captured image. Rejects
  /// selfies where the face is too small / far for a confident match.
  static const double faceMinSizeFraction = 0.20;
}

class AppConstants {
  static const String appName = 'Omni HR';
  static const String apiVersion = 'v1';

  /// Live app version, populated at startup from pubspec.yaml via
  /// package_info_plus. pubspec.yaml is the single source of truth —
  /// DO NOT hardcode here.
  static String _appVersion = '0.0.0';
  static String get appVersion => _appVersion;

  /// Call once from main() before runApp(). Reads the version baked
  /// into the build at compile-time, so subsequent reads are instant
  /// and synchronous.
  static Future<void> initAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      // Stay on the '0.0.0' sentinel — better than crashing startup
      // over a cosmetic field. The sentinel is recognisable in logs.
    }
  }
}
