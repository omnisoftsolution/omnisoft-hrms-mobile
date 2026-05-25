import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// Reuses the iOS Swift method-channel that already exists for face
// embedding (see ios/Runner/FaceEmbedderPlugin.swift). Same channel,
// new method 'detectSpoof'. Android continues using tflite_flutter
// directly because the dlsym dead-strip problem is iOS-only.
const _kFaceEmbedChannel = MethodChannel('omnihr/face_embed');

/// Two-model anti-spoof ensemble — MiniVision / Silent-Face-Anti-
/// Spoofing port from a prior Kotlin app.
///
/// Both models are tiny 80×80 patch classifiers trained on faces
/// cropped at two different expansion factors:
///   - scale 2.7: tight crop around the face (sees face texture)
///   - scale 4.0: wider crop including some background (sees the
///                edges of a phone screen / paper print / monitor
///                bezel that surround a spoofed face)
///
/// Each model outputs a 3-class softmax (label index 1 = live).
/// The two softmaxes are summed element-wise and argmax-ed; if the
/// winning index is 1, the capture is treated as a live face.
///
/// This is **passive** — no challenge instruction shown to the user.
/// The detection runs invisibly after the standard ML Kit quality
/// gate. Performance: ~150 ms total on a modern phone (CPU). On
/// older iPhones (iPhone 8/X-era) closer to ~300 ms — still well
/// under the human perception of "slow."
///
/// What it catches:
///   - Printed photo of an employee
///   - Phone-screen replay of an employee
///   - Photo on a tablet / monitor
///
/// What it does NOT catch:
///   - 3D silicone / printed masks (out of scope for an HR app)
///   - High-quality video replay on the EXACT same camera with no
///     bezel visible (degraded effectiveness — that's why we still
///     want depth/challenge layers for true KYC, but for HR
///     attendance this is the realistic threat model)
class FaceSpoofDetector {
  static const _model1Asset = 'assets/models/spoof_model_scale_2_7.tflite';
  static const _model2Asset = 'assets/models/spoof_model_scale_4_0.tflite';
  static const double _scale1 = 2.7;
  static const double _scale2 = 4.0;
  static const int _inputSize = 80;
  static const int _outputDim = 3;
  // Class index in the model's 3-way softmax that represents a live
  // face (vs print spoof / replay spoof). From the MiniVision
  // training: 0 = fake_print, 1 = real, 2 = fake_replay (the Kotlin
  // reference checks `label != 1` for spoof).
  static const int _liveClassIndex = 1;

  Interpreter? _interp1;
  Interpreter? _interp2;
  bool _loadTried = false;
  String? _loadError;
  // iOS-specific: errors from _detectViaNativePlugin (Swift method
  // channel). Captured so they surface in [loadError] and ultimately
  // in the on-device debug dialog — without this, iOS failures show
  // up as "Liveness unavailable: (none)" with no actionable detail.
  String? _iosError;

  /// Returns null when the spoof models couldn't be loaded (assets
  /// missing, TFLite init failed, etc.). Service layer treats null as
  /// "liveness check unavailable" — see [DevConstants.requireLivenessCheck]
  /// for whether that hard-blocks the capture.
  Future<bool> _ensureLoaded() async {
    if (_interp1 != null && _interp2 != null) return true;
    if (_loadTried) return false;
    _loadTried = true;
    try {
      final options = InterpreterOptions()..threads = 2;
      _interp1 = await Interpreter.fromAsset(_model1Asset, options: options);
      _interp2 = await Interpreter.fromAsset(_model2Asset, options: options);
      debugPrint(
          'FaceSpoofDetector models loaded ($_model1Asset + $_model2Asset)');
      return true;
    } catch (e) {
      _loadError = 'Spoof models failed to load: $e';
      debugPrint('$_loadError — liveness check disabled');
      _interp1?.close();
      _interp2?.close();
      _interp1 = null;
      _interp2 = null;
      return false;
    }
  }

  /// Runs the two-model ensemble against [imagePath], cropping the
  /// face out of the full frame using [faceBox] (ML Kit's detected
  /// bounding box in the image's pixel coordinates).
  ///
  /// Returns null on any failure (missing models, decode failure,
  /// inference error). Caller decides how to interpret null per
  /// [DevConstants.requireLivenessCheck].
  Future<FaceSpoofResult?> detect({
    required String imagePath,
    required double boxLeft,
    required double boxTop,
    required double boxWidth,
    required double boxHeight,
  }) async {
    // iOS: route to Swift method channel (TFLite C symbols are
    // dead-stripped by iOS 26's release linker — see the embedder
    // plugin's header comment for the full backstory).
    if (Platform.isIOS) {
      return _detectViaNativePlugin(
        imagePath: imagePath,
        boxLeft: boxLeft,
        boxTop: boxTop,
        boxWidth: boxWidth,
        boxHeight: boxHeight,
      );
    }

    if (!await _ensureLoaded()) return null;

    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('FaceSpoofDetector: could not decode $imagePath');
        return null;
      }

      final stopwatch = Stopwatch()..start();

      final crop1 = _cropForScale(
        decoded, boxLeft, boxTop, boxWidth, boxHeight, _scale1);
      final crop2 = _cropForScale(
        decoded, boxLeft, boxTop, boxWidth, boxHeight, _scale2);

      final input1 = _buildInputTensor(crop1);
      final input2 = _buildInputTensor(crop2);

      final out1 = List.generate(1, (_) => List.filled(_outputDim, 0.0));
      final out2 = List.generate(1, (_) => List.filled(_outputDim, 0.0));

      _interp1!.run(input1, out1);
      _interp2!.run(input2, out2);

      stopwatch.stop();

      final result = _combineOutputs(
        out1[0].cast<double>(),
        out2[0].cast<double>(),
        stopwatch.elapsedMilliseconds,
      );
      debugPrint('FaceSpoofDetector android result: '
          'isLive=${result.isLive} score=${result.score.toStringAsFixed(3)} '
          'elapsedMs=${result.elapsedMs}');
      return result;
    } catch (e) {
      debugPrint('FaceSpoofDetector inference failed: $e');
      return null;
    }
  }

  /// iOS path — same contract, same model files (referenced from the
  /// Flutter asset bundle by the Swift plugin). Failure mode: null.
  Future<FaceSpoofResult?> _detectViaNativePlugin({
    required String imagePath,
    required double boxLeft,
    required double boxTop,
    required double boxWidth,
    required double boxHeight,
  }) async {
    try {
      final res = await _kFaceEmbedChannel.invokeMethod<Map<Object?, Object?>>(
        'detectSpoof',
        {
          'imagePath': imagePath,
          'left': boxLeft,
          'top': boxTop,
          'width': boxWidth,
          'height': boxHeight,
        },
      );
      if (res == null) {
        _iosError = 'iOS native: Swift returned nil (no result, no error)';
        debugPrint('FaceSpoofDetector $_iosError');
        return null;
      }
      final isLive = (res['isLive'] as bool?) ?? false;
      final score = ((res['score'] as num?) ?? 0).toDouble();
      final elapsedMs = ((res['elapsedMs'] as num?) ?? 0).toInt();
      final argmax = ((res['argmax'] as num?) ?? -1).toInt();
      final s1 = (res['softmax1'] as List?)
              ?.cast<num>()
              .map((e) => e.toDouble())
              .toList() ??
          const <double>[];
      final s2 = (res['softmax2'] as List?)
              ?.cast<num>()
              .map((e) => e.toDouble())
              .toList() ??
          const <double>[];
      debugPrint('FaceSpoofDetector ios result: '
          'isLive=$isLive score=${score.toStringAsFixed(3)} '
          'elapsedMs=$elapsedMs argmax=$argmax '
          's1=$s1 s2=$s2');
      return FaceSpoofResult(
        isLive: isLive,
        score: score,
        elapsedMs: elapsedMs,
        argmax: argmax,
        softmax1: s1,
        softmax2: s2,
      );
    } on PlatformException catch (e) {
      _iosError = 'iOS native ${e.code}: ${e.message ?? "(no detail)"}';
      debugPrint('FaceSpoofDetector $_iosError');
      return null;
    } catch (e) {
      _iosError = 'iOS native call failed: $e';
      debugPrint('FaceSpoofDetector $_iosError');
      return null;
    }
  }

  /// Crop the input image to a square centered on the face bounding
  /// box, expanded by [scale]. Mirrors the Kotlin reference's
  /// `getScaledBox`: the scale is clamped by the image dimensions to
  /// avoid going off-edge, then the rectangle is shifted back inside
  /// the image bounds if it overhangs. Output is resized to
  /// [_inputSize]×[_inputSize].
  img.Image _cropForScale(
    img.Image src,
    double bx,
    double by,
    double bw,
    double bh,
    double scale,
  ) {
    final srcW = src.width.toDouble();
    final srcH = src.height.toDouble();
    final effectiveScale = math.min(
      math.min((srcH - 1.0) / bh, (srcW - 1.0) / bw),
      scale,
    );
    final newW = bw * effectiveScale;
    final newH = bh * effectiveScale;
    final cx = bw / 2.0 + bx;
    final cy = bh / 2.0 + by;
    double x0 = cx - newW / 2.0;
    double y0 = cy - newH / 2.0;
    double x1 = cx + newW / 2.0;
    double y1 = cy + newH / 2.0;
    if (x0 < 0) {
      x1 -= x0;
      x0 = 0;
    }
    if (y0 < 0) {
      y1 -= y0;
      y0 = 0;
    }
    if (x1 > srcW - 1) {
      x0 -= (x1 - (srcW - 1));
      x1 = srcW - 1;
    }
    if (y1 > srcH - 1) {
      y0 -= (y1 - (srcH - 1));
      y1 = srcH - 1;
    }
    final ix = x0.round().clamp(0, src.width - 1);
    final iy = y0.round().clamp(0, src.height - 1);
    final iw = (x1 - x0).round().clamp(1, src.width - ix);
    final ih = (y1 - y0).round().clamp(1, src.height - iy);

    final cropped = img.copyCrop(src, x: ix, y: iy, width: iw, height: ih);
    return img.copyResize(cropped, width: _inputSize, height: _inputSize);
  }

  /// Build the 80×80×3 float32 input tensor. Pixel values stay in
  /// [0, 255] (no normalization — the reference Kotlin uses
  /// ImageProcessor with CastOp(FLOAT32) only, no NormalizeOp).
  /// Channels are swapped R↔B because the upstream model was trained
  /// on OpenCV-loaded images (BGR) but our img.Image is RGB.
  List<List<List<List<double>>>> _buildInputTensor(img.Image src) {
    return List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final p = src.getPixel(x, y);
            // R↔B swap → BGR ordering for the model.
            return [p.b.toDouble(), p.g.toDouble(), p.r.toDouble()];
          },
        ),
      ),
    );
  }

  /// Softmax each model's output, sum element-wise, argmax. Mirrors
  /// the Kotlin reference exactly. Score is the winning index's
  /// summed probability / 2 (since both softmaxes sum to 1).
  FaceSpoofResult _combineOutputs(
    List<double> out1,
    List<double> out2,
    int elapsedMs,
  ) {
    final s1 = _softmax(out1);
    final s2 = _softmax(out2);
    final summed =
        List<double>.generate(_outputDim, (i) => s1[i] + s2[i]);
    var maxIdx = 0;
    for (var i = 1; i < _outputDim; i++) {
      if (summed[i] > summed[maxIdx]) maxIdx = i;
    }
    return FaceSpoofResult(
      isLive: maxIdx == _liveClassIndex,
      score: summed[maxIdx] / 2.0,
      elapsedMs: elapsedMs,
      argmax: maxIdx,
      softmax1: s1,
      softmax2: s2,
    );
  }

  List<double> _softmax(List<double> x) {
    // Numerically-stable softmax: subtract max before exp() so big
    // logits don't overflow.
    final mx = x.reduce(math.max);
    final exps = x.map((v) => math.exp(v - mx)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }

  /// Returns whichever error was captured on the last failed
  /// detect — either the Android load error (set inside
  /// [_ensureLoaded]) or the iOS native call error (set inside
  /// [_detectViaNativePlugin]). Null when nothing has failed yet
  /// or the most recent call succeeded.
  String? get loadError => _loadError ?? _iosError;

  Future<void> dispose() async {
    _interp1?.close();
    _interp2?.close();
    _interp1 = null;
    _interp2 = null;
    _loadTried = false;
    _loadError = null;
    _iosError = null;
  }
}

class FaceSpoofResult {
  /// True when the ensemble's argmax landed on the live class.
  final bool isLive;

  /// Winning class's summed probability (max ~1.0). Higher = more
  /// confident in the predicted class, whether live or spoof.
  final double score;

  /// Inference latency for both models combined, including
  /// preprocessing.
  final int elapsedMs;

  /// Winning class index from the summed-softmax argmax. Diagnostic
  /// only — `isLive` already encodes this against [_liveClassIndex].
  final int argmax;

  /// Raw softmax output of model 1 (scale 2.7). Length [_outputDim]
  /// (= 3). Diagnostic only — surfaced in capture-screen debug
  /// overlay so we can see which class index actually corresponds to
  /// "live" empirically.
  final List<double> softmax1;

  /// Raw softmax output of model 2 (scale 4.0). Length [_outputDim].
  final List<double> softmax2;

  FaceSpoofResult({
    required this.isLive,
    required this.score,
    required this.elapsedMs,
    this.argmax = -1,
    this.softmax1 = const <double>[],
    this.softmax2 = const <double>[],
  });

  bool get isSpoof => !isLive;

  /// User-facing message shown when [isSpoof]. Avoids accusatory
  /// language — most failures are lighting / glare false positives,
  /// not actual spoof attempts.
  String get friendlyMessage =>
      'Live photo check failed. Make sure you’re showing your real face '
      '(not a photo or a screen) and try again.';
}
