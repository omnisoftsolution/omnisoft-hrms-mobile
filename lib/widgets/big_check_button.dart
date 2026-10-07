import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

enum CheckButtonState {
  ready,    // idle, ready to check in/out
  scanning, // user tapped, in progress
  disabled, // not allowed (e.g. outside geofence)
  enroll,   // face not enrolled — tap to start one-time setup
}

/// The hero attendance button on the home screen — a solid teal
/// circle with a feature-aware glyph (face / location / both), a
/// CHECK IN / CHECK OUT label, and a small status pill below the
/// label. Wrapped in a softer outer ring with a colored glow shadow
/// for depth.
///
/// The outer halo softly pulsates (alpha 0.10↔0.18, 1.5s loop) when
/// the button is ready or disabled — a gentle "live" hint. The pulse
/// pauses during the scanning state to avoid layering motion under
/// the inner spinner.
class BigCheckButton extends StatefulWidget {
  final bool checkedIn;
  final CheckButtonState state;
  final VoidCallback? onPressed;

  /// Whether the SaaS subscription enables face verification.
  final bool faceEnabled;

  /// Whether the SaaS subscription enables geolocation enforcement.
  final bool geoEnabled;

  /// Inner solid circle diameter. Outer halo is +24 on each side.
  final double size;

  const BigCheckButton({
    super.key,
    required this.checkedIn,
    required this.state,
    required this.onPressed,
    this.faceEnabled = true,
    this.geoEnabled = true,
    this.size = 200,
  });

  @override
  State<BigCheckButton> createState() => _BigCheckButtonState();
}

class _BigCheckButtonState extends State<BigCheckButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAlpha;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Pulse both alpha AND scale, driven by the same controller, so
    // the halo reads as a calm "breath". Alpha alone (the previous
    // shape) was too subtle to perceive at 0.10↔0.18 — bumped here.
    // Scale 1.00↔1.05 on the 248px halo = ~12px of breathing room.
    _pulseAlpha = Tween<double>(begin: 0.08, end: 0.28).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseScale = Tween<double>(begin: 1.00, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant BigCheckButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == CheckButtonState.scanning) {
      _pulseCtrl.stop();
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _fill {
    // In enroll mode the button isn't really a check-in/out — paint
    // it in the same primaryContainer teal as the "checked-out" idle
    // state so it doesn't suggest an active session.
    if (widget.state == CheckButtonState.enroll) {
      return AppTheme.primaryContainer;
    }
    return widget.checkedIn ? AppTheme.secondary : AppTheme.primaryContainer;
  }

  String get _stateLabel => switch (widget.state) {
        CheckButtonState.ready => 'READY',
        CheckButtonState.scanning => 'SCANNING…',
        CheckButtonState.disabled => 'NOT READY',
        CheckButtonState.enroll => 'SETUP NEEDED',
      };

  Color get _stateDot => switch (widget.state) {
        CheckButtonState.ready => const Color(0xFF22C55E),
        CheckButtonState.scanning => Colors.white,
        // Out-of-range / disabled → red so the user immediately sees
        // why they can't check in. Pairs with the "NOT READY" label.
        CheckButtonState.disabled => AppTheme.error,
        // Amber for one-time setup — not an error, just a step.
        CheckButtonState.enroll => const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context) {
    final outer = widget.size + 48;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer halo / ring — gently pulsates alpha + scale.
          // Listen to the controller directly so both derived tweens
          // sample on every tick.
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, _) => Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width: outer,
                height: outer,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _fill.withValues(alpha: _pulseAlpha.value),
                ),
              ),
            ),
          ),
          // Inner solid circle with glow + tap target
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: widget.state == CheckButtonState.scanning
                  ? null
                  : [
                      BoxShadow(
                        color: _fill.withValues(alpha: 0.30),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: Material(
              color: _fill,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.state == CheckButtonState.scanning
                    ? null
                    : widget.onPressed,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.state == CheckButtonState.scanning)
                        const SizedBox(
                          height: 56,
                          width: 56,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      else if (widget.state == CheckButtonState.enroll)
                        const Icon(
                          Icons.face_retouching_natural_rounded,
                          size: 64,
                          color: Colors.white,
                        )
                      else
                        _CheckGlyph(
                          faceEnabled: widget.faceEnabled,
                          geoEnabled: widget.geoEnabled,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        widget.state == CheckButtonState.enroll
                            ? 'ENROLL FACE'
                            : (widget.checkedIn ? 'CHECK OUT' : 'CHECK IN'),
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatePill(label: _stateLabel, dotColor: _stateDot),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glyph picked based on enabled feature flags:
///   face + geo  → face icon with a small location-pin badge in the
///                 lower-right corner, on a circular white backdrop
///   face only   → face icon
///   geo only    → location pin
///   neither     → login arrow (trust-based clock-in)
class _CheckGlyph extends StatelessWidget {
  final bool faceEnabled;
  final bool geoEnabled;
  const _CheckGlyph({required this.faceEnabled, required this.geoEnabled});

  @override
  Widget build(BuildContext context) {
    if (faceEnabled && geoEnabled) {
      return SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(
                Icons.face_rounded,
                size: 64,
                color: Colors.white,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (faceEnabled) {
      return const Icon(
        Icons.face_rounded,
        size: 64,
        color: Colors.white,
      );
    }
    if (geoEnabled) {
      return const Icon(
        Icons.location_on_rounded,
        size: 64,
        color: Colors.white,
      );
    }
    return const Icon(
      Icons.login_rounded,
      size: 64,
      color: Colors.white,
    );
  }
}

class _StatePill extends StatelessWidget {
  final String label;
  final Color dotColor;
  const _StatePill({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
