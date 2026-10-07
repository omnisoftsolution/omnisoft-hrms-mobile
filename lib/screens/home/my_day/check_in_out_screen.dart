import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../models/face_capture_result.dart';
import '../../../services/attendance_action_controller.dart';
import '../../../widgets/big_check_button.dart';
import '../../../widgets/silent_face_capture.dart';

/// What [CheckInOutScreen] pops: the punch outcome (null = nothing
/// happened, e.g. a cancelled capture) or the error the run threw.
class CheckInOutResult {
  const CheckInOutResult({this.outcome, this.error});

  final AttendanceActionOutcome? outcome;
  final Object? error;
}

/// The signature check-in / check-out page (1.30.1). My day's tile button
/// opens it on the root navigator; it starts the punch by itself: the
/// pulsing circle (`BigCheckButton`) while the location and Wi-Fi gates
/// run, the circular 3-2-1 camera (`InlineFaceCapture`) for the face, the
/// scanning circle while the punch is sent, then a short green tick. It
/// pops a [CheckInOutResult]; My day shows the snackbar, UNDO and any
/// question afterwards.
class CheckInOutScreen extends StatefulWidget {
  const CheckInOutScreen({
    super.key,
    required this.checkingOut,
    required this.run,
    this.shiftLabel = '',
    this.placeLabel = '',
    this.faceEnabled = true,
    this.geoEnabled = true,
    this.captureBuilder,
    this.minPulse = const Duration(milliseconds: 900),
    this.successHold = const Duration(milliseconds: 1100),
  });

  /// True when the punch is a check-out (labels only).
  final bool checkingOut;

  /// The punch (`AttendanceActionController.perform`); it calls the
  /// given capture when it needs the face.
  final Future<AttendanceActionOutcome?> Function(
    Future<FaceCaptureResult> Function() captureFace,
  )
  run;

  /// "08:00 – 17:00", or '' when the day has no shift.
  final String shiftLabel;

  /// The live place line ("At the office · 24 m"), or ''.
  final String placeLabel;
  final bool faceEnabled;
  final bool geoEnabled;

  /// Test seam: replaces the circular camera.
  @visibleForTesting
  final Widget Function(ValueChanged<FaceCaptureResult> onResult)?
  captureBuilder;

  /// The pulsing circle shows at least this long before the camera.
  final Duration minPulse;

  /// How long the green tick stays before the page closes.
  final Duration successHold;

  @override
  State<CheckInOutScreen> createState() => _CheckInOutScreenState();
}

enum _Phase { preparing, capturing, checking, done }

class _CheckInOutScreenState extends State<CheckInOutScreen> {
  _Phase _phase = _Phase.preparing;
  final Stopwatch _shown = Stopwatch()..start();
  Completer<FaceCaptureResult>? _capture;
  String _doneLabel = '';
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final outcome = await widget.run(_captureFace);
      if (!mounted) return;
      if (outcome != null && outcome.ok) {
        setState(() {
          _phase = _Phase.done;
          final at = DateFormat('HH:mm').format(DateTime.now());
          _doneLabel = outcome.checkedIn ? 'Checked in $at' : 'Checked out $at';
        });
        await Future<void>.delayed(widget.successHold);
      }
      _close(CheckInOutResult(outcome: outcome));
    } catch (e) {
      _close(CheckInOutResult(error: e));
    }
  }

  Future<FaceCaptureResult> _captureFace() async {
    final left = widget.minPulse - _shown.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
    final completer = Completer<FaceCaptureResult>();
    if (!mounted) return FaceCaptureResult.cancelled();
    setState(() {
      _capture = completer;
      _phase = _Phase.capturing;
    });
    return completer.future;
  }

  void _onCaptured(FaceCaptureResult result) {
    final completer = _capture;
    _capture = null;
    if (mounted) setState(() => _phase = _Phase.checking);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _close(CheckInOutResult result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  Widget _circle() {
    switch (_phase) {
      case _Phase.capturing:
        final build = widget.captureBuilder;
        return build != null
            ? build(_onCaptured)
            : InlineFaceCapture(onResult: _onCaptured);
      case _Phase.done:
        return _DoneCircle(label: _doneLabel);
      case _Phase.preparing:
      case _Phase.checking:
        return BigCheckButton(
          checkedIn: widget.checkingOut,
          state: _phase == _Phase.checking
              ? CheckButtonState.scanning
              : CheckButtonState.ready,
          onPressed: null,
          faceEnabled: widget.faceEnabled,
          geoEnabled: widget.geoEnabled,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final muted = TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant);
    // The punch is in flight: the camera's ✕ is the only way out.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 32),
              Text(DateFormat('EEE d MMM').format(now), style: muted),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(now),
                style: GoogleFonts.inter(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
              if (widget.shiftLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Shift ${widget.shiftLabel}', style: muted),
              ],
              const Spacer(),
              _circle(),
              const Spacer(),
              if (widget.placeLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: AppTheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(widget.placeLabel, style: muted)),
                    ],
                  ),
                ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// The green tick after a punch went through — same 248dp footprint as
/// the button and the camera, so nothing jumps.
class _DoneCircle extends StatelessWidget {
  const _DoneCircle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1B7F3B);
    return TweenAnimationBuilder<double>(
      key: const ValueKey('check-done'),
      tween: Tween(begin: 0.8, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 248,
        height: 248,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: green.withValues(alpha: 0.12),
        ),
        child: Container(
          width: 200,
          height: 200,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: green),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_rounded, size: 72, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
