import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/error_messages.dart';
import '../../../core/theme.dart';
import '../../../models/face_capture_result.dart';
import '../../../services/attendance_action_controller.dart';
import '../../../widgets/big_check_button.dart';
import '../../../widgets/silent_face_capture.dart';

/// What [CheckInOutScreen] pops: the punch outcome, or null when nothing
/// happened (a cancelled capture) or the page already showed why it
/// failed.
class CheckInOutResult {
  const CheckInOutResult({this.outcome});

  final AttendanceActionOutcome? outcome;
}

/// The signature check-in / check-out page (1.30.1, layout C chosen on
/// 2026-10-08). My day's tile button opens it on the root navigator and it
/// runs by itself: a header (who, shift, time, late note), the pulsing
/// circle (`BigCheckButton`) while the location and Wi-Fi gates run, the
/// circular 3-2-1 camera (`InlineFaceCapture`), the scanning circle while
/// the punch is sent, then a green tick. Below the circle a checklist
/// ticks each step as [AttendanceActionController.perform] reports it; a
/// failed step turns red with the reason and a Close button. On success
/// it pops the outcome so My day shows the snackbar, UNDO and any question.
class CheckInOutScreen extends StatefulWidget {
  const CheckInOutScreen({
    super.key,
    required this.checkingOut,
    required this.run,
    this.employeeName = '',
    this.shiftLabel = '',
    this.headerNote = '',
    this.hoursToday = '',
    this.lastLabel = '',
    this.faceEnabled = true,
    this.geoEnabled = true,
    this.captureBuilder,
    this.minPulse = const Duration(milliseconds: 900),
    this.successHold = const Duration(milliseconds: 1100),
  });

  /// True when the punch is a check-out (labels only).
  final bool checkingOut;

  /// The punch (`AttendanceActionController.perform`): it calls the given
  /// capture when it needs the face and reports each checklist step.
  final Future<AttendanceActionOutcome?> Function(
    Future<FaceCaptureResult> Function() captureFace,
    PunchStepCallback onStep,
  )
  run;

  final String employeeName;

  /// "08:00 – 17:00", or '' when the day has no shift.
  final String shiftLabel;

  /// Amber note under the clock ("1h 53m late"), or ''.
  final String headerNote;

  /// "0h 00m"; the footer line is hidden when ''.
  final String hoursToday;

  /// "Last out 18:25", or ''.
  final String lastLabel;
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

/// The circle's inner diameter: the 1.28 home button's 200 + 30% (Willy,
/// 2026-10-08). The halo adds 48, so every phase is 308 wide.
const double _kCircle = 260;

enum _Phase { preparing, capturing, checking, done, failed }

enum _Row { pending, running, done, skipped, failed }

class _CheckInOutScreenState extends State<CheckInOutScreen> {
  _Phase _phase = _Phase.preparing;
  final Stopwatch _shown = Stopwatch()..start();
  Completer<FaceCaptureResult>? _capture;
  final Map<PunchStep, _Row> _rows = {
    for (final s in PunchStep.values) s: _Row.pending,
  };
  final Map<PunchStep, String> _details = {};
  String _doneAt = '';
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final AttendanceActionOutcome? outcome;
    try {
      outcome = await widget.run(_captureFace, _onStep);
    } catch (e) {
      _fail(friendlyError(e));
      return;
    }
    if (!mounted) return;
    final error = outcome?.error;
    if (error != null) {
      _fail(error);
      return;
    }
    if (outcome == null || !outcome.ok) {
      _close(CheckInOutResult(outcome: outcome));
      return;
    }
    setState(() {
      _phase = _Phase.done;
      _doneAt = DateFormat('HH:mm').format(DateTime.now());
      _rows[PunchStep.record] = _Row.done;
    });
    await Future<void>.delayed(widget.successHold);
    _close(CheckInOutResult(outcome: outcome));
  }

  void _onStep(PunchStep step, PunchStepState state, String detail) {
    if (!mounted) return;
    setState(() {
      _rows[step] = switch (state) {
        PunchStepState.running => _Row.running,
        PunchStepState.done => _Row.done,
        PunchStepState.skipped => _Row.skipped,
      };
      _details[step] = detail;
      if (step == PunchStep.record && state == PunchStepState.running) {
        _phase = _Phase.checking;
      }
    });
  }

  /// The running step (else the first unfinished one) turns red.
  void _fail(String message) {
    if (!mounted) return;
    final steps = PunchStep.values;
    final at = steps.firstWhere(
      (s) => _rows[s] == _Row.running,
      orElse: () => steps.firstWhere(
        (s) => _rows[s] == _Row.pending,
        orElse: () => PunchStep.record,
      ),
    );
    setState(() {
      _phase = _Phase.failed;
      _rows[at] = _Row.failed;
      _details[at] = message;
    });
  }

  Future<FaceCaptureResult> _captureFace() async {
    final left = widget.minPulse - _shown.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
    if (!mounted) return FaceCaptureResult.cancelled();
    final completer = Completer<FaceCaptureResult>();
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
            : InlineFaceCapture(size: _kCircle, onResult: _onCaptured);
      case _Phase.done:
        return _DoneCircle(label: _doneTitle);
      case _Phase.preparing:
      case _Phase.checking:
      case _Phase.failed:
        return BigCheckButton(
          size: _kCircle,
          checkedIn: widget.checkingOut,
          state: switch (_phase) {
            _Phase.checking => CheckButtonState.scanning,
            _Phase.failed => CheckButtonState.disabled,
            _ => CheckButtonState.ready,
          },
          onPressed: null,
          faceEnabled: widget.faceEnabled,
          geoEnabled: widget.geoEnabled,
        );
    }
  }

  String get _doneTitle =>
      '${widget.checkingOut ? 'Checked out' : 'Checked in'} $_doneAt';

  String _title(PunchStep step) => switch (step) {
    PunchStep.location => 'Location',
    PunchStep.wifi => 'Office Wi-Fi',
    PunchStep.face => 'Face',
    PunchStep.record =>
      _rows[step] == _Row.done
          ? _doneTitle
          : (widget.checkingOut
                ? 'Record the check-out'
                : 'Record the check-in'),
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final failed = _phase == _Phase.failed;
    final muted = TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant);
    // While the punch runs the camera's ✕ is the only way out.
    return PopScope(
      canPop: failed,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  name: widget.employeeName,
                  subtitle: [
                    DateFormat('EEE d MMM').format(now),
                    if (widget.shiftLabel.isNotEmpty)
                      'Shift ${widget.shiftLabel}',
                  ].join(' · '),
                  time: DateFormat('HH:mm').format(now),
                  note: widget.headerNote,
                ),
                Expanded(
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: _circle()),
                  ),
                ),
                _Card(
                  child: Column(
                    children: [
                      for (final s in PunchStep.values)
                        _StepRow(
                          key: ValueKey('step-${s.name}-${_rows[s]!.name}'),
                          title: _title(s),
                          detail: _details[s] ?? 'Waiting',
                          row: _rows[s]!,
                          last: s == PunchStep.record,
                        ),
                    ],
                  ),
                ),
                if (widget.hoursToday.isNotEmpty ||
                    widget.lastLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // "Hours today" takes all the room the last-punch label
                  // leaves; that label is sized to its text, capped at half
                  // the row. Both ellipsize only when they really do not
                  // fit (equal flex thirds cut "Hours today …" on 360 dp).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.hoursToday.isEmpty
                                  ? ''
                                  : 'Hours today ${widget.hoursToday}',
                              style: muted,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.lastLabel.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth / 2,
                              ),
                              child: Text(
                                widget.lastLabel,
                                style: muted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (failed) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => _close(const CheckInOutResult()),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D191C1E),
          blurRadius: 20,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

/// Who, which day and shift, the clock and the late note.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.subtitle,
    required this.time,
    required this.note,
  });

  final String name;
  final String subtitle;
  final String time;
  final String note;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppTheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D191C1E),
          blurRadius: 20,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFFDCEFF1),
          child: Text(
            _initials,
            style: const TextStyle(
              color: Color(0xFF004F55),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              time,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.onSurface,
              ),
            ),
            if (note.isNotEmpty)
              Text(
                note,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A5A00),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// One checklist row: mark, title, detail.
class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.title,
    required this.detail,
    required this.row,
    required this.last,
  });

  final String title;
  final String detail;
  final _Row row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Widget? mark) = switch (row) {
      _Row.done => (
        const Color(0xFFDCF2E3),
        const Color(0xFF1B7F3B),
        const Icon(Icons.check_rounded, size: 18, color: Color(0xFF1B7F3B)),
      ),
      _Row.skipped => (
        AppTheme.surfaceContainer,
        AppTheme.outline,
        Icon(Icons.remove_rounded, size: 18, color: AppTheme.outline),
      ),
      _Row.running => (
        const Color(0xFFDCEFF1),
        AppTheme.primary,
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      ),
      _Row.failed => (
        const Color(0xFFFFDAD6),
        AppTheme.error,
        const Icon(Icons.close_rounded, size: 18, color: AppTheme.error),
      ),
      _Row.pending => (AppTheme.surfaceContainer, AppTheme.outline, null),
    };
    final titleColor = switch (row) {
      _Row.running => AppTheme.primary,
      _Row.failed => AppTheme.error,
      _Row.pending || _Row.skipped => AppTheme.outline,
      _Row.done => AppTheme.onSurface,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppTheme.surfaceContainer)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: mark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: row == _Row.failed
                          ? AppTheme.error
                          : AppTheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (row == _Row.failed)
            Icon(Icons.error_outline, color: fg, size: 18),
        ],
      ),
    );
  }
}

/// The green tick after a punch went through — same footprint as
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
        width: _kCircle + 48,
        height: _kCircle + 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: green.withValues(alpha: 0.12),
        ),
        child: Container(
          width: _kCircle,
          height: _kCircle,
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
