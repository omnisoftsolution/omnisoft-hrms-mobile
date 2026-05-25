import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/face_capture_result.dart';
import '../../services/face_recognition_engine.dart' show FaceLivenessResult;
import '../../services/face_recognition_service.dart';

/// Real camera capture screen.
///
/// Returns a FaceCaptureResult to the caller. `success` is true when
/// the captured frame passes ML Kit's quality gate (one face, big
/// enough, eyes open). The user sees a single screen — no separate
/// Retake/Confirm step. If the quality gate fails, we snap back to
/// the live camera view with the failure reason shown inline so the
/// user can immediately retry without an extra tap.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _capturing = false;
  String? _error;
  // Inline message shown above the camera preview when the previous
  // capture attempt failed the quality gate. Distinct from _error,
  // which is reserved for fatal camera-init failures.
  String? _qualityHint;
  // Diagnostic-only: most recent liveness result. Surfaces the raw
  // softmax outputs + argmax in a tiny overlay near the top of the
  // capture screen. Lets us tell whether the spoof model is
  // misclassifying (model issue) vs whether the label index is wrong
  // (interpretation issue) by just reading numbers off the screen.
  // Remove the overlay block in build() once the v49 diagnostic
  // cycle is complete.
  FaceLivenessResult? _lastLiveness;

  @override
  void initState() {
    super.initState();
    if (DevConstants.simulateFaceRecognition) {
      // iOS simulator has no camera at all. When dev simulate-face
      // is on, skip capture entirely and return a placeholder path.
      // FaceRecognitionService.verifyFace also short-circuits when
      // simulating so the path is never actually read.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(
          FaceCaptureResult.success('/dev/null/simulated.jpg'),
        );
      });
      return;
    }
    _initFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No cameras available on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(() => _error = _humanizeCameraError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _humanizeCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera permission was denied. Enable it in Settings to take a selfie.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      case 'AudioAccessDenied':
        return 'Microphone permission was denied.';
      default:
        return e.description ?? e.code;
    }
  }

  /// Capture + auto-confirm pipeline.
  ///
  /// 1. takePicture()
  /// 2. run ML Kit quality gate
  /// 3a. quality ok → pop with success (no separate review screen)
  /// 3b. quality fails → show the failure reason inline above the
  ///     live preview; user can immediately retake by tapping again
  ///
  /// Eliminates the old Retake/Confirm two-screen flow. Quality
  /// failures stay in-place rather than bouncing through a review
  /// screen.
  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() {
      _capturing = true;
      _qualityHint = null;
    });
    // Older iPhones (8, X, 10) flash the camera preview WHITE during
    // takePicture()'s native AVCapturePhotoOutput moment — looks
    // jarring (peer feedback: "somewhat blinding"). We render an
    // opaque dark scrim in build() whenever _capturing is true.
    // Wait one frame so the scrim is painted BEFORE the native
    // capture begins, otherwise the white flash leaks through on
    // slow CPUs between the setState scheduling and the native call.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      final svc = context.read<FaceRecognitionService>();
      final quality = await svc.checkQuality(file.path);
      if (!mounted) return;
      if (!quality.ok) {
        // Quality failed — surface why and stay on the camera so the
        // user can retake immediately.
        setState(() {
          _qualityHint = quality.friendlyMessage;
          _capturing = false;
        });
        return;
      }

      // Passive anti-spoof check. Always runs (so shadow-mode
      // produces logs we can use to tune the false-positive rate
      // against real employees), but only BLOCKS when
      // DevConstants.requireLivenessCheck is on. The check is
      // invisible to the user — they see the same "Checking…" scrim
      // they already see during the quality gate.
      final liveness = await svc.checkLiveness(file.path);
      if (!mounted) return;
      // Cache the latest liveness for the diagnostic overlay.
      _lastLiveness = liveness;

      // Diagnostic dialog (v50): block navigation until the tester
      // reads + dismisses. Lets us pull the raw softmax numbers
      // without a debug console attached. Gated on a constant — flip
      // off before any customer-facing release.
      if (DevConstants.showLivenessDiagnostic) {
        await _showLivenessDiagnosticDialog(liveness);
        if (!mounted) return;
      }

      if (DevConstants.requireLivenessCheck &&
          liveness.available &&
          !liveness.isLive) {
        setState(() {
          _qualityHint = liveness.errorMessage ??
              'Live photo check failed. Please try again.';
          _capturing = false;
        });
        return;
      }

      Navigator.of(context).pop(FaceCaptureResult.success(file.path));
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _error = _humanizeCameraError(e);
          _capturing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _qualityHint = 'Capture failed: $e';
          _capturing = false;
        });
      }
    }
  }

  void _cancel() {
    Navigator.of(context).pop(FaceCaptureResult.cancelled());
  }

  /// v50 diagnostic: show the raw spoof-model outputs before
  /// continuing. SelectableText so the tester can long-press → copy
  /// (or just screenshot) the numbers and send them back. Returns
  /// only after the user dismisses the dialog.
  Future<void> _showLivenessDiagnosticDialog(FaceLivenessResult l) async {
    final body = l.available
        ? 'isLive=${l.isLive}\n${l.debugSummary}'
        : 'Liveness unavailable\nerror: ${l.errorMessage ?? "(none)"}';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Liveness debug'),
        content: SelectableText(
          body,
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DevConstants.simulateFaceRecognition) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null ? _buildError() : _buildCamera(),
      ),
    );
  }

  Widget _buildError() {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _cancel,
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
        _buildCloseButton(),
      ],
    );
  }

  Widget _buildCamera() {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: CameraPreview(controller)),
            // Capturing scrim — full-screen opaque dark overlay
            // that masks the iOS camera-preview white flash on
            // older iPhones during takePicture(). See _capture()
            // for the matching endOfFrame await that guarantees
            // this scrim paints before the native call fires.
            if (_capturing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3),
                        const SizedBox(height: 16),
                        const Text(
                          'Checking…',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Oval guide overlay.
            Center(
              child: Container(
                width: 260,
                height: 340,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 3),
                  borderRadius: BorderRadius.circular(180),
                ),
              ),
            ),
            // Top instruction / inline quality hint.
            Positioned(
              top: 24,
              left: 16,
              right: 16,
              child: Center(
                child: _qualityHint == null
                    ? const Text(
                        'Position your face inside the frame',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _qualityHint!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
            // Shutter — larger, higher-contrast version of the
            // previous tiny button. Solid white inner ring + dark
            // shadow makes it unambiguous against any background.
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _capturing
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: AppTheme.primary,
                                strokeWidth: 3,
                              ),
                            )
                          : Icon(
                              Icons.camera_alt,
                              color: AppTheme.primary,
                              size: 40,
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _capturing ? 'Checking…' : 'Tap to capture',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _buildCloseButton(),
            // ===== DIAGNOSTIC OVERLAY (v49) =====
            // Shows the raw softmax outputs from both spoof models +
            // the argmax. Used to verify whether the live-class
            // index is actually 1 (Kotlin reference assumption) or
            // something else for these specific model files. Remove
            // this block once we know the right interpretation.
            if (_lastLiveness != null) _buildSpoofDebugOverlay(),
            // ===== END DIAGNOSTIC OVERLAY =====
          ],
        );
      },
    );
  }

  Widget _buildSpoofDebugOverlay() {
    final l = _lastLiveness!;
    final summary = l.available
        ? l.debugSummary
        : 'unavailable: ${l.errorMessage ?? "?"}';
    return Positioned(
      top: 60,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: l.isLive
                ? Colors.greenAccent.withValues(alpha: 0.7)
                : Colors.redAccent.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        child: Text(
          'DEBUG isLive=${l.isLive}\n$summary',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontFamily: 'Courier',
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Positioned(
      top: 12,
      left: 12,
      child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white, size: 28),
        onPressed: _cancel,
      ),
    );
  }
}
