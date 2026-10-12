import 'package:flutter/material.dart';

/// The arrival snackbars HomeShell has handed to the messenger (one on
/// screen at most, others queued) and which of them is on screen, so a
/// push tap on a notice takes its arrival away (F1) and never hides
/// another snackbar — a reminder that replaced it, a newer arrival, or a
/// tab's confirmation it is queued behind. Every outstanding arrival is
/// tracked until it closes (Codex r4 #1).
class ArrivalSnackTracker {
  final Map<int, _Arrival> _live = {};

  /// The arrival snackbar for notice [id] was handed to the messenger.
  /// Call the returned function when it closes; a late close of an older
  /// arrival of the same notice changes nothing.
  void Function() shown(int id) {
    final arrival = _Arrival();
    _live[id] = arrival;
    return () {
      if (identical(_live[id], arrival)) _live.remove(id);
    };
  }

  /// The arrival for notice [id] is now the bar on screen. True when a tap
  /// asked for it to go while it was still queued: the caller hides it.
  bool visible(int id) {
    final arrival = _live[id];
    if (arrival == null) return false;
    for (final other in _live.values) {
      other.onScreen = identical(other, arrival);
    }
    return arrival.dismissOnShow;
  }

  /// A reminder replaced the bar on screen: an arrival that was on screen
  /// is gone; queued ones stay tracked.
  void replaced() => _live.removeWhere((_, arrival) => arrival.onScreen);

  /// A push tap on notice [id]. True, once, when its arrival is the bar on
  /// screen: the caller hides it. When it is still queued it is marked to
  /// go as soon as it shows, and nothing on screen is touched.
  bool takeIfShowing(int id) {
    final arrival = _live[id];
    if (arrival == null) return false;
    if (!arrival.onScreen) {
      arrival.dismissOnShow = true;
      return false;
    }
    _live.remove(id);
    return true;
  }
}

class _Arrival {
  bool onScreen = false; // its content was built: it is the bar shown
  bool dismissOnShow = false; // tapped while still queued
}

/// Shows the arrival snackbar for notice [id] built by [build] (which
/// wraps its content with the given function) and records it in
/// [tracker]. Only the bar on screen is replaced, as arrivals always did;
/// queued snackbars (a tab's confirmation with UNDO) are kept, and the
/// arrival reports when it really shows (Codex r3 #2, #3).
void showArrivalSnack(
  ScaffoldMessengerState messenger,
  ArrivalSnackTracker tracker,
  int id,
  SnackBar Function(Widget Function(Widget content) wrap) build,
) {
  messenger.removeCurrentSnackBar();
  final closed = tracker.shown(id);
  final bar = build(
    (content) => _OnScreen(
      onShown: () {
        if (tracker.visible(id)) messenger.hideCurrentSnackBar();
      },
      child: content,
    ),
  );
  messenger.showSnackBar(bar).closed.then((_) => closed());
}

/// Calls [onShown] once, after the first frame its snackbar is built in
/// (the messenger builds a snackbar only when it is the one on screen).
class _OnScreen extends StatefulWidget {
  const _OnScreen({required this.onShown, required this.child});

  final VoidCallback onShown;
  final Widget child;

  @override
  State<_OnScreen> createState() => _OnScreenState();
}

class _OnScreenState extends State<_OnScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
