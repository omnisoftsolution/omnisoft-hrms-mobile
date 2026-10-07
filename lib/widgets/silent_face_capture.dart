import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/face_capture_result.dart';
import '../services/face_recognition_service.dart';

/// Inline circular face-capture widget — designed to drop in where
/// `BigCheckButton` lives during a check-in / check-out.
///
/// Same outer footprint as `BigCheckButton` (200dp inner + 48dp halo
/// = 248dp), so the home screen layout doesn't shift when this widget
/// swaps in.
///
/// Calls [onResult] exactly once on:
///   - success (capture passed both quality + liveness)
///   - user-cancel (✕)
///   - hard timeout or camera failure
///
/// The parent owns the swap — typically a state flag flipped back to
/// `false` inside the `onResult` handler so the widget unmounts.
class InlineFaceCapture extends StatefulWidget {
  /// Inner preview diameter — matches `BigCheckButton.size`.
  final double size;

  /// Outer halo thickness (total padding around the inner circle) —
  /// matches `BigCheckButton`'s `size + 48` outer dimension.
  final double haloPadding;

  /// Fires exactly once with the capture outcome.
  final ValueChanged<FaceCaptureResult> onResult;

  const InlineFaceCapture({
    super.key,
    this.size = 200,
    this.haloPadding = 48,
    required this.onResult,
  });

  @override
  State<InlineFaceCapture> createState() => _InlineFaceCaptureState();
}

enum _Phase { initializing, countdown, capturing, retrying }

class _InlineFaceCaptureState extends State<InlineFaceCapture> {
  CameraController? _controller;
  _Phase _phase = _Phase.initializing;
  String _status = 'Opening camera...';
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _hardTimeoutTimer;
  bool _resolved = false;
  int _failedAttempts = 0;
  late final FaceRecognitionService _service;

  // Total wall-clock safety net before we give up. Sized to comfortably
  // cover 3 normal-path attempts (3s countdown + ~1s capture + 1.2s
  // retry-pause each) plus camera init slack. Catches genuinely-stuck
  // cases like a camera that never initialises.
  static const Duration _hardTimeout = Duration(seconds: 18);

  // Cap on quality / liveness retries inside a single session — each
  // failure re-arms the countdown. Three lets a user adjust framing
  // without being trapped in a battery-draining loop if they walk away.
  static const int _maxFailedAttempts = 3;

  @override
  void initState() {
    super.initState();
    _service = context.read<FaceRecognitionService>();
    if (DevConstants.simulateFaceRecognition) {
      // Simulator: no camera. `FaceRecognitionService.verifyFace` also
      // short-circuits in this mode so the fake path is never read.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolve(FaceCaptureResult.success('/dev/null/simulated.jpg'));
      });
      return;
    }
    _hardTimeoutTimer = Timer(_hardTimeout, _onHardTimeout);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _failHard('No cameras available on this device.');
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
      setState(() {
        _controller = controller;
        _phase = _Phase.countdown;
        _status = 'Position your face';
      });
      _startCountdown();
    } on CameraException catch (e) {
      _failHard(_humanizeCameraError(e));
    } catch (e) {
      _failHard(e.toString());
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 1000), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _capture();
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _phase == _Phase.capturing) return;
    setState(() {
      _phase = _Phase.capturing;
      _status = 'Hold still...';
    });
    // One frame settling so the capture scrim paints BEFORE the
    // native takePicture call — matches FaceCaptureScreen's workaround
    // for the iPhone-8/X "white flash" during the AVCapturePhotoOutput
    // moment.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      setState(() => _status = 'Checking...');
      final quality = await _service.checkQuality(file.path);
      if (!mounted) return;
      if (!quality.ok) {
        _onAttemptFailed(quality.friendlyMessage);
        return;
      }
      final liveness = await _service.checkLiveness(file.path);
      if (!mounted) return;
      if (DevConstants.requireLivenessCheck &&
          liveness.available &&
          !liveness.isLive) {
        _onAttemptFailed(liveness.errorMessage ??
            'Live photo check failed. Try again in better light.');
        return;
      }
      _resolve(FaceCaptureResult.success(file.path));
    } on CameraException catch (e) {
      _failHard(_humanizeCameraError(e));
    } catch (e) {
      _onAttemptFailed('Capture failed. Please try again.');
    }
  }

  void _onAttemptFailed(String message) {
    _failedAttempts += 1;
    if (_failedAttempts >= _maxFailedAttempts) {
      _resolve(FaceCaptureResult.error(message));
      return;
    }
    setState(() {
      _phase = _Phase.retrying;
      _status = message;
    });
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || _resolved) return;
      setState(() {
        _phase = _Phase.countdown;
        _status = 'Position your face';
      });
      _startCountdown();
    });
  }

  void _onHardTimeout() {
    if (_resolved) return;
    _resolve(FaceCaptureResult.error(
      "Couldn't get a clear shot. Try positioning manually.",
    ));
  }

  void _failHard(String message) {
    _resolve(FaceCaptureResult.error(message));
  }

  void _resolve(FaceCaptureResult result) {
    if (_resolved) return;
    _resolved = true;
    _countdownTimer?.cancel();
    _hardTimeoutTimer?.cancel();
    widget.onResult(result);
  }

  void _cancel() {
    _resolve(FaceCaptureResult.cancelled());
  }

  String _humanizeCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera permission was denied. Enable it in Settings.';
      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';
      default:
        return e.description ?? e.code;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _hardTimeoutTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = widget.size + widget.haloPadding;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer halo — soft teal glow to match the button's
          // primaryContainer fill colour at idle. No pulsing while
          // capture is in progress (scanning state on BigCheckButton
          // also pauses its pulse).
          Container(
            width: outer,
            height: outer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryContainer.withValues(alpha: 0.18),
            ),
          ),
          // Inner circle: camera preview clipped to circle.
          ClipOval(
            child: Container(
              width: widget.size,
              height: widget.size,
              color: Colors.black,
              child: _buildPreviewBody(),
            ),
          ),
          // White ring matching BigCheckButton's 4dp outline. Drawn
          // separately so it sits ON TOP of the clipped preview.
          IgnorePointer(
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
          ),
          // Big centered countdown digit during the position phase.
          // Sits above the preview so the user gets a clear
          // "fire-in-N" signal. Drops the moment we shift to capture.
          if (_phase == _Phase.countdown && _controller != null)
            IgnorePointer(
              child: Text(
                '$_countdown',
                style: GoogleFonts.inter(
                  fontSize: 88,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      blurRadius: 16,
                      color: Colors.black54,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          // ✕ in the halo region so it doesn't obscure the preview.
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                onPressed: _cancel,
                tooltip: 'Cancel',
              ),
            ),
          ),
          // Status pill at the bottom of the inner circle — same
          // location and shape as BigCheckButton's state pill.
          Positioned(
            // outer/2 - inner/2 + 16 = haloPadding/2 + 16 from outer
            // bottom. = 24 + 16 = 40.
            bottom: widget.haloPadding / 2 + 16,
            child: _buildStatusPill(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBody() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            color: AppTheme.primaryContainer,
            strokeWidth: 2,
          ),
        ),
      );
    }
    // Unmirrored preview — shows the user as others see them, which
    // also matches the captured JPEG that gets compared against the
    // enrolled face (captures are not mirrored by takePicture).
    Widget preview = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.previewSize?.height ?? 1,
        height: c.value.previewSize?.width ?? 1,
        child: CameraPreview(c),
      ),
    );
    if (_phase == _Phase.capturing) {
      // Capture scrim: hides the iOS white flash on older iPhones and
      // also serves as the "thinking..." surface for the quality +
      // liveness pipeline.
      preview = Stack(
        fit: StackFit.expand,
        children: [
          preview,
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.55),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return preview;
  }

  Widget _buildStatusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _phase == _Phase.retrying
            ? AppTheme.error.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(100),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.size - 32),
        child: Text(
          _status,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
