import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'team_colors.dart';

/// Initials circle with the employee-id hue (A-L6). No photos are fetched
/// for the team screens. Decorative: the name next to it is what a screen
/// reader reads.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({
    super.key,
    required this.id,
    required this.initials,
    this.size = 32,
  });

  final int id;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TeamColors.avatar(id),
        ),
        child: Text(
          initials,
          style: TextStyle(
            color: TeamColors.onC3,
            fontSize: size * 0.375,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The small teal "You" chip after the viewer's own name.
class TeamYouChip extends StatelessWidget {
  const TeamYouChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: TeamColors.accentTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'You',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: TeamColors.onAccentTint,
        ),
      ),
    );
  }
}

/// The dashed "Pending" chip of a leave request not approved yet (D3).
class TeamPendingChip extends StatelessWidget {
  const TeamPendingChip({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedPillPainter(TeamColors.leave),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          'Pending',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: TeamColors.leave,
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  const _DashedPillPainter(this.color);

  final Color color;

  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(0.75);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + _dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A rounded filter chip (view and department choices).
class TeamFilterChip extends StatelessWidget {
  const TeamFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected ? TeamColors.accentTint : TeamColors.chipBorder,
        width: 1.5,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? TeamColors.accentTint : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? TeamColors.onAccentTint
                    : AppTheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
