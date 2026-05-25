import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MethodChannel, PlatformException;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants.dart';
import 'face_spoof_detector.dart';

// iOS-only: TFLite via Swift method channel.
//
// tflite_flutter's dart:ffi + dlsym path is dead on iOS 26
// release builds (linker strips the C symbols). Instead we call
// into a native Swift plugin at ios/Runner/FaceEmbedderPlugin.swift
// that uses the TensorFlowLiteSwift Swift API directly. The plugin
// is registered from AppDelegate.swift, which makes its method
// handler — and therefore the Swift Interpreter usage inside — a
// live root the linker can't strip. The TFLite C symbols survive.
//
// Android continues using the Dart-side tflite_flutter path
// because it works fine (no static-framework dead-strip issue).
const _kFaceEmbedChannel = MethodChannel('omnihr/face_embed');

// =====================================================================
// Engine interface
// =====================================================================

/// Pluggable on-device face engine. Two implementations live below:
///
///   SimulatedFaceRecognitionEngine — dev-only, always-passes path
///       behind DevConstants.simulateFaceRecognition. Quality checks
///       still run so the user sees real "no face / multiple faces"
///       errors during development.
///
///   MLKitFaceRecognitionEngine — production scaffold.
///       Quality (face count, size, eyes-open) uses Google ML Kit
///       Face Detection — REAL on-device, no licensing concerns.
///       Identity matching (extractEmbedding / compare) is intentionally
///       NOT IMPLEMENTED here: ML Kit detects faces but does not produce
///       embeddings. A separate task adds a TFLite face embedding model
///       (e.g. MobileFaceNet) plus the alignment preprocessing pipeline.
///       Until then, compare() returns implemented=false and the service
///       layer fails closed in production.
///
/// Why ML Kit alone isn't recognition:
///   ML Kit Face Detection returns bounding boxes + landmarks +
///   classifications (smiling probability, eye-open probability). It
///   does NOT return a person identity vector. Two photos of two
///   different people both produce a "face detected" — that is not
///   matching. We use ML Kit only for quality gating.
abstract class FaceRecognitionEngine {
  String get name;
  bool get isProduction;

  Future<void> initialize();

  /// Quality validation only. Real on whatever engine is active.
  Future<FaceQualityResult> checkQuality(String imagePath);

  /// Passive on-device liveness / anti-spoof check. Runs a two-model
  /// TFLite ensemble over the detected face region to flag printed
  /// photos and phone-screen replays. See [FaceSpoofDetector] for
  /// the model contract.
  ///
  /// Returns a [FaceLivenessResult] — the `available` flag is false
  /// when the spoof models couldn't be loaded (e.g. assets missing
  /// in this build). Caller decides whether to hard-block on
  /// unavailable; see [DevConstants.requireLivenessCheck].
  Future<FaceLivenessResult> checkLiveness(String imagePath);

  /// Returns a unit-length embedding vector for the face in [imagePath],
  /// or null when the engine doesn't implement embeddings yet.
  Future<List<double>?> extractEmbedding(String imagePath);

  /// Compare two face images. Returns implemented=false when the
  /// engine does not yet do identity matching.
  Future<FaceCompareResult> compare(
    String enrolledImagePath,
    String liveImagePath,
  );

  Future<void> dispose();
}

// =====================================================================
// Result types
// =====================================================================

enum FaceQualityIssue {
  noFace,
  multipleFaces,
  faceTooSmall,
  eyesClosed,
  imageReadFailed,
}

class FaceQualityResult {
  final bool ok;
  final FaceQualityIssue? issue;
  final double? boundingBoxFraction;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  FaceQualityResult({
    required this.ok,
    this.issue,
    this.boundingBoxFraction,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
  });

  factory FaceQualityResult.ok({
    double? boxFraction,
    double? leftEye,
    double? rightEye,
  }) =>
      FaceQualityResult(
        ok: true,
        boundingBoxFraction: boxFraction,
        leftEyeOpenProbability: leftEye,
        rightEyeOpenProbability: rightEye,
      );

  factory FaceQualityResult.fail(FaceQualityIssue issue) =>
      FaceQualityResult(ok: false, issue: issue);

  String get friendlyMessage {
    switch (issue) {
      case FaceQualityIssue.noFace:
        return 'No face detected. Please retake.';
      case FaceQualityIssue.multipleFaces:
        return 'Multiple faces detected. Please retake alone.';
      case FaceQualityIssue.faceTooSmall:
        return 'Move closer to the camera.';
      case FaceQualityIssue.eyesClosed:
        return 'Please look at the camera with eyes open.';
      case FaceQualityIssue.imageReadFailed:
        return 'Could not read the captured image.';
      case null:
        return 'Quality check passed.';
    }
  }
}

/// Outcome of a passive liveness check on a single image.
///
/// `available` distinguishes "model said spoof" from "we couldn't
/// run the check at all" (assets missing, native call failed, etc.).
/// The capture screen + service layer use this to decide whether to
/// hard-block — see [DevConstants.requireLivenessCheck].
class FaceLivenessResult {
  final bool available;
  final bool isLive;
  final double? score;
  final int? elapsedMs;
  final String? errorMessage;

  /// Diagnostic-only: winning class index from the spoof ensemble's
  /// summed-softmax argmax. -1 when the check didn't run.
  final int argmax;

  /// Diagnostic-only: raw softmax outputs of the two spoof models.
  /// Surfaced in the capture screen's debug overlay so we can see
  /// what the model actually predicts and figure out the correct
  /// label mapping (`_liveClassIndex` is assumed = 1 from the Kotlin
  /// reference but might be different for these model files).
  final List<double> softmax1;
  final List<double> softmax2;

  FaceLivenessResult({
    required this.available,
    required this.isLive,
    this.score,
    this.elapsedMs,
    this.errorMessage,
    this.argmax = -1,
    this.softmax1 = const <double>[],
    this.softmax2 = const <double>[],
  });

  factory FaceLivenessResult.live(
    double score,
    int elapsedMs, {
    int argmax = -1,
    List<double> softmax1 = const <double>[],
    List<double> softmax2 = const <double>[],
  }) =>
      FaceLivenessResult(
        available: true,
        isLive: true,
        score: score,
        elapsedMs: elapsedMs,
        argmax: argmax,
        softmax1: softmax1,
        softmax2: softmax2,
      );

  factory FaceLivenessResult.spoof(
    double score,
    int elapsedMs, {
    int argmax = -1,
    List<double> softmax1 = const <double>[],
    List<double> softmax2 = const <double>[],
  }) =>
      FaceLivenessResult(
        available: true,
        isLive: false,
        score: score,
        elapsedMs: elapsedMs,
        argmax: argmax,
        softmax1: softmax1,
        softmax2: softmax2,
        errorMessage:
            'Live photo check failed. Make sure you’re showing your real '
            'face (not a photo or a screen) and try again.',
      );

  factory FaceLivenessResult.unavailable([String? reason]) =>
      FaceLivenessResult(
        available: false,
        isLive: false,
        errorMessage: reason,
      );

  /// Compact one-line debug string of the raw model output. Empty
  /// when no diagnostics are populated (e.g. simulated engine or
  /// unavailable). Format:
  ///   argmax=1 score=0.92 ms=187 m1=[0.10,0.79,0.11] m2=[0.05,0.91,0.04]
  String get debugSummary {
    if (softmax1.isEmpty && softmax2.isEmpty) return '';
    String fmt(List<double> v) =>
        '[${v.map((d) => d.toStringAsFixed(2)).join(",")}]';
    return 'argmax=$argmax '
        'score=${score?.toStringAsFixed(2) ?? "?"} '
        'ms=${elapsedMs ?? "?"} '
        'm1=${fmt(softmax1)} '
        'm2=${fmt(softmax2)}';
  }
}

class FaceCompareResult {
  /// True only when identity matching ran AND passed the threshold.
  final bool ok;

  /// False when the engine doesn't implement identity matching yet.
  /// In that case the service layer fails closed in production.
  final bool implemented;

  /// Cosine similarity in [0..1] when implemented. Higher = more
  /// similar. Compare against DevConstants.faceMatchThreshold.
  final double? score;

  /// Why compare failed — only set when ok=false. Passed back to UI.
  final String? reason;

  FaceCompareResult({
    required this.ok,
    required this.implemented,
    this.score,
    this.reason,
  });

  factory FaceCompareResult.match(double score) =>
      FaceCompareResult(ok: true, implemented: true, score: score);

  factory FaceCompareResult.mismatch(double score) => FaceCompareResult(
        ok: false,
        implemented: true,
        score: score,
        reason: 'Face not recognized. Please try again.',
      );

  factory FaceCompareResult.notImplemented() => FaceCompareResult(
        ok: false,
        implemented: false,
        reason:
            'On-device identity matching is not yet wired up. Disable '
            'simulateFaceRecognition only after the TFLite face '
            'embedding model is integrated.',
      );
}

// =====================================================================
// Simulated engine — dev-only
// =====================================================================

class SimulatedFaceRecognitionEngine implements FaceRecognitionEngine {
  @override
  String get name => 'simulated';
  @override
  bool get isProduction => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<FaceQualityResult> checkQuality(String imagePath) async {
    // Even in simulate mode we still want SOME sanity, so we read the
    // file and confirm it exists.
    final f = File(imagePath);
    if (!await f.exists()) {
      return FaceQualityResult.fail(FaceQualityIssue.imageReadFailed);
    }
    return FaceQualityResult.ok();
  }

  @override
  Future<FaceLivenessResult> checkLiveness(String imagePath) async {
    // Dev mode bypasses the spoof check the same way it bypasses
    // identity matching — otherwise simulator testing breaks.
    return FaceLivenessResult.live(1.0, 0);
  }

  @override
  Future<List<double>?> extractEmbedding(String imagePath) async => null;

  @override
  Future<FaceCompareResult> compare(
    String enrolledImagePath,
    String liveImagePath,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return FaceCompareResult.match(1.0);
  }

  @override
  Future<void> dispose() async {}
}

// =====================================================================
// Production scaffold — ML Kit quality + fail-closed identity matching
// =====================================================================

/// Pixel normalization for the bundled face-embedding model.
/// Read from the interpreter's input shape — different models expect
/// different preprocessing, picking the wrong one silently produces
/// garbage embeddings.
enum _Normalization {
  /// MobileFaceNet, ArcFace etc. — (p - 127.5) / 128 → range [-1, 1]
  minusOneToOne,
  /// FaceNet (David Sandberg / deepface) — per-image mean/std
  /// standardization (a.k.a. "prewhitening").
  perImageStandardization,
}

class MLKitFaceRecognitionEngine implements FaceRecognitionEngine {
  static const _modelAsset = 'assets/models/mobilefacenet.tflite';

  late FaceDetector _detector;
  Interpreter? _embedder;
  // Detected at model load.
  int _inputSize = 112;
  _Normalization _norm = _Normalization.minusOneToOne;
  bool _initialized = false;
  bool _embedderTried = false; // avoid spamming load attempts
  // Passive anti-spoof ensemble — lazily loads the two TFLite models
  // on first checkLiveness call. iOS routes through the same Swift
  // method channel as the embedder; Android uses tflite_flutter
  // directly.
  final FaceSpoofDetector _spoofDetector = FaceSpoofDetector();
  // Captured during _ensureEmbedder when the load fails — surfaced to
  // the UI via compare()'s reason field so testers (especially on iOS
  // where the issue first surfaced) see what actually went wrong
  // instead of "not yet wired up".
  String? _embedderLoadError;
  // Last per-image extraction failure reason (no face, decode fail, etc.)
  // — also surfaced to compare()'s reason field.
  String? _lastExtractError;

  @override
  String get name => 'mlkit_face_quality';
  @override
  bool get isProduction => true;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // smiling / eyes-open probabilities
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    _initialized = true;
  }

  /// Lazily load the embedding model. Returns null when missing — the
  /// caller fails closed cleanly, no crash. Captures the load error in
  /// _embedderLoadError so compare() can surface it to the UI.
  Future<Interpreter?> _ensureEmbedder() async {
    if (_embedder != null) return _embedder;
    if (_embedderTried) return null;
    _embedderTried = true;
    try {
      // Force pure CPU inference. On iOS, the default options try to
      // enable the CoreML / Metal delegate; if the model contains ops
      // the delegate doesn't support, the whole load fails. CPU
      // inference works for every model variant we ship.
      final options = InterpreterOptions()..threads = 2;
      _embedder =
          await Interpreter.fromAsset(_modelAsset, options: options);
      final inShape = _embedder!.getInputTensor(0).shape;
      final outShape = _embedder!.getOutputTensor(0).shape;
      // Expect [1, H, W, 3] — pull H (= W for the supported models).
      _inputSize = inShape.length >= 3 ? inShape[1] : 112;
      // Heuristic: 160x160 → FaceNet (per-image standardization);
      // 112x112 → MobileFaceNet/ArcFace ([-1, 1]). If a future model
      // breaks this rule, override via DevConstants.
      _norm = _inputSize >= 160
          ? _Normalization.perImageStandardization
          : _Normalization.minusOneToOne;
      debugPrint('Face embedder loaded — input=$inShape output=$outShape '
          'inputSize=$_inputSize norm=${_norm.name}');
      _embedderLoadError = null;
      return _embedder;
    } catch (e) {
      final msg = 'Face match model failed to load: $e';
      _embedderLoadError = msg;
      debugPrint('$msg — falling back to fail-closed identity match');
      return null;
    }
  }

  @override
  Future<FaceQualityResult> checkQuality(String imagePath) async {
    await initialize();
    final f = File(imagePath);
    if (!await f.exists()) {
      return FaceQualityResult.fail(FaceQualityIssue.imageReadFailed);
    }

    // iOS saves camera JPEGs in sensor-native orientation with EXIF metadata
    // describing the rotation. ML Kit's InputImage.fromFilePath on iOS does
    // not reliably honor that EXIF — feeding the file directly produces a
    // 90°-rotated frame and ML Kit reports zero faces. Bake the rotation
    // into pixels first, then point ML Kit at the normalized file.
    final normalizedPath = await _normalizeOrientation(imagePath);
    final input = InputImage.fromFilePath(normalizedPath);
    final faces = await _detector.processImage(input);

    if (faces.isEmpty) {
      debugPrint('ML Kit faces=0 result=noFace path=$normalizedPath');
      return FaceQualityResult.fail(FaceQualityIssue.noFace);
    }
    if (faces.length > 1) {
      debugPrint(
          'ML Kit faces=${faces.length} result=multipleFaces');
      return FaceQualityResult.fail(FaceQualityIssue.multipleFaces);
    }

    final face = faces.first;
    // Bounding box width as a fraction of the image short side. We
    // don't have the image dimensions from ML Kit directly; pull them
    // from the (normalized) file so the box-coords match.
    final bytes = await File(normalizedPath).readAsBytes();
    final shortSide = await _imageShortSide(bytes);
    double? boxFraction;
    if (shortSide != null && shortSide > 0) {
      final w = face.boundingBox.width.abs();
      boxFraction = w / shortSide;
      if (boxFraction < DevConstants.faceMinSizeFraction) {
        debugPrint(
            'ML Kit faces=1 box=${boxFraction.toStringAsFixed(2)} '
            'result=faceTooSmall');
        return FaceQualityResult.fail(FaceQualityIssue.faceTooSmall);
      }
    }

    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    if (leftOpen != null && rightOpen != null) {
      // Average eye-open probability — more robust than AND/OR since
      // both eyes are usually affected similarly by squint / lashes.
      // <0.5 means "more likely closed than open".
      final avgOpen = (leftOpen + rightOpen) / 2.0;
      if (avgOpen < 0.5) {
        debugPrint(
          'ML Kit faces=1 box=${boxFraction?.toStringAsFixed(2)} '
          'leftEye=${leftOpen.toStringAsFixed(2)} '
          'rightEye=${rightOpen.toStringAsFixed(2)} result=eyesClosed',
        );
        return FaceQualityResult.fail(FaceQualityIssue.eyesClosed);
      }
    }

    debugPrint(
      'ML Kit faces=1 box=${boxFraction?.toStringAsFixed(2)} '
      'leftEye=${leftOpen?.toStringAsFixed(2) ?? "null"} '
      'rightEye=${rightOpen?.toStringAsFixed(2) ?? "null"} result=ok',
    );
    return FaceQualityResult.ok(
      boxFraction: boxFraction,
      leftEye: leftOpen,
      rightEye: rightOpen,
    );
  }

  @override
  Future<FaceLivenessResult> checkLiveness(String imagePath) async {
    await initialize();
    final f = File(imagePath);
    if (!await f.exists()) {
      return FaceLivenessResult.unavailable('Image not found.');
    }

    // Run on the orientation-normalized image so the bounding box we
    // pass to the spoof detector lines up with the pixels it sees —
    // same posture as extractEmbedding above.
    final normalizedPath = await _normalizeOrientation(imagePath);
    final input = InputImage.fromFilePath(normalizedPath);
    final faces = await _detector.processImage(input);
    if (faces.isEmpty || faces.length > 1) {
      // The quality gate is the right place to surface no-face /
      // multi-face errors. If we got here something is off — return
      // unavailable so the caller doesn't hard-block on a likely
      // false positive.
      return FaceLivenessResult.unavailable(
          'Could not isolate a single face for the liveness check.');
    }
    final box = faces.first.boundingBox;

    final result = await _spoofDetector.detect(
      imagePath: normalizedPath,
      boxLeft: box.left,
      boxTop: box.top,
      boxWidth: box.width,
      boxHeight: box.height,
    );
    if (result == null) {
      return FaceLivenessResult.unavailable(_spoofDetector.loadError);
    }
    return result.isLive
        ? FaceLivenessResult.live(
            result.score,
            result.elapsedMs,
            argmax: result.argmax,
            softmax1: result.softmax1,
            softmax2: result.softmax2,
          )
        : FaceLivenessResult.spoof(
            result.score,
            result.elapsedMs,
            argmax: result.argmax,
            softmax1: result.softmax1,
            softmax2: result.softmax2,
          );
  }

  @override
  Future<List<double>?> extractEmbedding(String imagePath) async {
    await initialize();
    _lastExtractError = null;

    // On iOS the dart:ffi + dlsym path is dead — route to the
    // native Swift plugin instead. Same MobileFaceNet model, same
    // preprocessing, same embedding shape. Android falls through
    // to the existing tflite_flutter path below.
    if (Platform.isIOS) {
      return _extractEmbeddingViaNativePlugin(imagePath);
    }

    final embedder = await _ensureEmbedder();
    if (embedder == null) {
      // _ensureEmbedder already populated _embedderLoadError; compare()
      // surfaces it. Return null without overwriting.
      return null;
    }

    // Detect the face so we can crop tightly. Embedding quality
    // collapses if we feed the whole frame (background dominates).
    // Use orientation-normalized image so ML Kit's bounding box aligns
    // with the pixels we crop in img.copyCrop below.
    final normalizedPath = await _normalizeOrientation(imagePath);
    final input = InputImage.fromFilePath(normalizedPath);
    final faces = await _detector.processImage(input);
    if (faces.isEmpty) {
      _lastExtractError =
          'No face detected in the captured image. Make sure '
          'your face is centered and well lit.';
      return null;
    }
    if (faces.length > 1) {
      _lastExtractError =
          'Multiple faces detected. Please retake the photo alone.';
      return null;
    }

    final raw = await File(normalizedPath).readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      _lastExtractError = 'Could not decode the captured image.';
      return null;
    }

    // ML Kit's bounding box is in the original image's coordinate
    // space. Inflate by 20% so we keep some hair / chin context
    // (face-recognition models like MobileFaceNet are trained on
    // slightly-padded crops, not tight chin-to-eyebrow boxes).
    final box = faces.first.boundingBox;
    final pad = 0.2;
    final cx = box.center.dx;
    final cy = box.center.dy;
    final half = math.max(box.width, box.height) * (0.5 + pad);
    final x = (cx - half).round().clamp(0, decoded.width - 1);
    final y = (cy - half).round().clamp(0, decoded.height - 1);
    final w = (half * 2).round().clamp(1, decoded.width - x);
    final h = (half * 2).round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final resized = img.copyResize(cropped,
        width: _inputSize, height: _inputSize);

    // Build the input tensor with the right normalization for the
    // loaded model (auto-detected from input size in _ensureEmbedder).
    List<List<List<List<double>>>> inTensor;
    if (_norm == _Normalization.perImageStandardization) {
      // FaceNet pre-whitening: subtract mean / divide by std (with
      // floor of 1/sqrt(N) per Sandberg's reference impl).
      final pixels = <double>[];
      for (var yy = 0; yy < _inputSize; yy++) {
        for (var xx = 0; xx < _inputSize; xx++) {
          final p = resized.getPixel(xx, yy);
          pixels.add(p.r.toDouble());
          pixels.add(p.g.toDouble());
          pixels.add(p.b.toDouble());
        }
      }
      final n = pixels.length;
      final mean = pixels.fold<double>(0, (s, v) => s + v) / n;
      var sqDev = 0.0;
      for (final v in pixels) {
        sqDev += (v - mean) * (v - mean);
      }
      final std = math.sqrt(sqDev / n);
      final stdAdj = math.max(std, 1.0 / math.sqrt(n.toDouble()));
      inTensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (yy) => List.generate(
            _inputSize,
            (xx) {
              final p = resized.getPixel(xx, yy);
              return [
                (p.r - mean) / stdAdj,
                (p.g - mean) / stdAdj,
                (p.b - mean) / stdAdj,
              ];
            },
          ),
        ),
      );
    } else {
      // MobileFaceNet / ArcFace: scale to [-1, 1].
      inTensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (yy) => List.generate(
            _inputSize,
            (xx) {
              final p = resized.getPixel(xx, yy);
              return [
                (p.r - 127.5) / 128.0,
                (p.g - 127.5) / 128.0,
                (p.b - 127.5) / 128.0,
              ];
            },
          ),
        ),
      );
    }

    // Output shape varies by model variant (128/192/512). Read it
    // from the loaded interpreter rather than hard-coding.
    final outShape = embedder.getOutputTensor(0).shape;
    final outDim = outShape.reduce((a, b) => a * b);
    final outTensor = List.generate(
      outShape[0],
      (_) => List.filled(outDim ~/ outShape[0], 0.0),
    );

    embedder.run(inTensor, outTensor);

    // L2-normalize so cosine similarity is just a dot product.
    final flat = (outTensor[0] as List).cast<double>();
    final norm = math.sqrt(flat.fold<double>(0, (s, v) => s + v * v));
    if (norm == 0) return null;
    return flat.map((v) => v / norm).toList(growable: false);
  }

  /// iOS-only path. Routes embedding extraction through the native
  /// Swift plugin (`ios/Runner/FaceEmbedderPlugin.swift`) because
  /// dart:ffi's dlsym-against-static-framework approach is dead on
  /// iOS 26 release builds. Same MobileFaceNet model, same
  /// preprocessing math, same output shape — Android-side and
  /// iOS-side embeddings remain comparable.
  Future<List<double>?> _extractEmbeddingViaNativePlugin(
      String imagePath) async {
    // Orientation normalization stays in Dart so the bounding-box
    // coordinates we pass to Swift line up with the pixels Swift
    // sees in the same file.
    final normalizedPath = await _normalizeOrientation(imagePath);
    final faces = await _detector.processImage(
        InputImage.fromFilePath(normalizedPath));
    if (faces.isEmpty) {
      _lastExtractError =
          'No face detected in the captured image. Make sure '
          'your face is centered and well lit.';
      return null;
    }
    if (faces.length > 1) {
      _lastExtractError =
          'Multiple faces detected. Please retake the photo alone.';
      return null;
    }
    final box = faces.first.boundingBox;

    try {
      final result = await _kFaceEmbedChannel.invokeMethod<List<Object?>>(
        'extractEmbedding',
        {
          'imagePath': normalizedPath,
          'left': box.left,
          'top': box.top,
          'width': box.width,
          'height': box.height,
        },
      );
      if (result == null) {
        _lastExtractError = 'Native face embedder returned null.';
        return null;
      }
      return result.cast<num>().map((e) => e.toDouble()).toList();
    } on PlatformException catch (e) {
      // Swift side surfaces error codes like MODEL_LOAD_FAIL,
      // DECODE_FAIL, INFER_FAIL, ZERO_EMBEDDING. Stash the message
      // so compare()'s reason field gets it instead of a generic
      // "not implemented" string.
      _lastExtractError =
          'iOS face embedder failed (${e.code}): ${e.message ?? "no detail"}';
      debugPrint(_lastExtractError);
      return null;
    } catch (e) {
      _lastExtractError = 'iOS face embedder failed: $e';
      debugPrint(_lastExtractError);
      return null;
    }
  }

  @override
  Future<FaceCompareResult> compare(
    String enrolledImagePath,
    String liveImagePath,
  ) async {
    final enrolled = await extractEmbedding(enrolledImagePath);
    if (enrolled == null) {
      // Surface whatever the engine actually hit. Order matters: model
      // load failures dominate over per-image failures.
      final reason = _embedderLoadError ??
          (_lastExtractError != null
              ? 'Enrolled face could not be processed: $_lastExtractError '
                  'Try re-enrolling from Profile.'
              : null);
      return FaceCompareResult(
        ok: false,
        implemented: false,
        reason: reason ??
            'Face match unavailable. Please re-enroll your face from '
                'Profile, or contact support if the issue persists.',
      );
    }
    final live = await extractEmbedding(liveImagePath);
    if (live == null) {
      // Live image has no face / multiple faces — quality gate
      // should have caught this, but be defensive. Surface the actual
      // reason so the user knows what to fix.
      return FaceCompareResult(
        ok: false,
        implemented: true,
        score: 0.0,
        reason: _lastExtractError ??
            'Face not recognized. Please try again.',
      );
    }

    // Cosine similarity = dot product on unit vectors.
    var dot = 0.0;
    for (var i = 0; i < enrolled.length && i < live.length; i++) {
      dot += enrolled[i] * live[i];
    }
    final score = dot.clamp(-1.0, 1.0);
    debugPrint('MobileFaceNet cosine=${score.toStringAsFixed(3)} '
        'threshold=${DevConstants.faceMatchThreshold}');
    if (score >= DevConstants.faceMatchThreshold) {
      return FaceCompareResult.match(score);
    }
    return FaceCompareResult.mismatch(score);
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      await _detector.close();
      _initialized = false;
    }
    _embedder?.close();
    _embedder = null;
    _embedderTried = false;
    _embedderLoadError = null;
    _lastExtractError = null;
    await _spoofDetector.dispose();
  }
}

/// Read [imagePath], apply EXIF orientation to the pixel buffer, and
/// write the result to a sibling `<basename>_oriented.jpg`. Returns the
/// new path. If decoding fails or no rotation is needed, returns the
/// original path. iOS-only concern in practice — Android's camera
/// plugin already bakes orientation into the JPEG.
Future<String> _normalizeOrientation(String imagePath) async {
  try {
    final f = File(imagePath);
    final bytes = await f.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return imagePath;
    final baked = img.bakeOrientation(decoded);
    final outPath = '${imagePath}_oriented.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(baked, quality: 92));
    debugPrint(
        'Face image normalized: ${decoded.width}x${decoded.height} → '
        '${baked.width}x${baked.height}  out=$outPath');
    return outPath;
  } catch (e) {
    debugPrint('_normalizeOrientation failed for $imagePath: $e — '
        'using original');
    return imagePath;
  }
}

/// Best-effort decode the image's short side from raw bytes for
/// proportional bounding-box checks. Avoids pulling in a heavy image
/// decoding dep — relies on Flutter's built-in instantiateImageCodec.
Future<int?> _imageShortSide(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    return w < h ? w : h;
  } catch (_) {
    return null;
  }
}
