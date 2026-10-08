import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The LEAVE destination's icon: a count badge while requests wait for
/// this user, and one short wiggle when the count goes up (spec
/// 2026-10-07 §4.5). Never loops; silent on the Leave tab itself and
/// under the phone's reduced-motion setting.
class LeaveTabIcon extends StatefulWidget {
  const LeaveTabIcon({
    super.key,
    required this.count,
    required this.selected,
    required this.icon,
  });

  final int count;
  final bool selected;
  final Widget icon;

  @override
  State<LeaveTabIcon> createState() => LeaveTabIconState();
}

class LeaveTabIconState extends State<LeaveTabIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Degrees: a shake that settles (−14, +12, −9, +6, −3, 0).
  late final Animation<double> _degrees = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -14), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -14, end: 12), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 12, end: -9), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -9, end: 6), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 6, end: -3), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -3, end: 0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @visibleForTesting
  bool get wiggling => _controller.isAnimating;

  @override
  void didUpdateWidget(LeaveTabIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final arrived = widget.count > oldWidget.count;
    if (arrived &&
        !widget.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: widget.count > 0,
      backgroundColor: AppTheme.error,
      label: Text('${widget.count}'),
      child: AnimatedBuilder(
        animation: _degrees,
        child: widget.icon,
        builder: (_, child) => Transform.rotate(
          angle: _degrees.value * math.pi / 180,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}
