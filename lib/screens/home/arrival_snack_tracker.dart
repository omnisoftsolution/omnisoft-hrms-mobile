import 'package:flutter/material.dart';

/// Which notice's arrival snackbar HomeShell has handed to the messenger,
/// and whether it is on screen yet, so a push tap on that notice takes it
/// away (F1) and never hides another snackbar — a reminder that replaced
/// it, a newer arrival, or a tab's confirmation it is queued behind.
class ArrivalSnackTracker {
  int? _pendingId; // handed to the messenger, maybe queued
  bool _onScreen = false; // its content was built: it is the bar shown
  bool _dismissOnShow = false; // tapped while still queued
  int _seq = 0;

  void _clear() {
    _pendingId = null;
    _onScreen = false;
    _dismissOnShow = false;
  }

  /// The arrival snackbar for notice [id] was handed to the messenger. Call
  /// the returned function when it closes; a late close of an older one
  /// changes nothing.
  void Function() shown(int id) {
    final mine = ++_seq;
    _clear();
    _pendingId = id;
    return () {
      if (_seq == mine) _clear();
    };
  }

  /// The arrival for notice [id] is now the bar on screen. True when a tap
  /// asked for it to go while it was still queued: the caller hides it.
  bool visible(int id) {
    if (_pendingId != id) return false;
    _onScreen = true;
    return _dismissOnShow;
  }

  /// A reminder replaced the bar on screen; an arrival that was on screen
  /// is gone (one still queued stays tracked).
  void replaced() {
    if (_onScreen) {
      _seq++;
      _clear();
    }
  }

  /// A push tap on notice [id]. True, once, when its arrival is the bar on
  /// screen: the caller hides it. When it is still queued it is marked to
  /// go as soon as it shows, and nothing on screen is touched.
  bool takeIfShowing(int id) {
    if (_pendingId != id) return false;
    if (!_onScreen) {
      _dismissOnShow = true;
      return false;
    }
    _seq++;
    _clear();
    return true;
  }
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
