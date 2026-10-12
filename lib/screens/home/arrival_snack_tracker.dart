import 'package:flutter/material.dart';

/// Which notice's arrival snackbar HomeShell has on screen, so a push tap
/// on that notice hides it (F1) and never hides another snackbar — a
/// reminder that replaced it, or a newer arrival.
class ArrivalSnackTracker {
  int? _shownId;
  int _seq = 0;

  /// The arrival snackbar for notice [id] is now on screen. Call the
  /// returned function when it closes; a late close of an older snackbar
  /// changes nothing.
  void Function() shown(int id) {
    final mine = ++_seq;
    _shownId = id;
    return () {
      if (_seq == mine) _shownId = null;
    };
  }

  /// Another snackbar (a reminder) replaced the arrival snackbar.
  void replaced() {
    _seq++;
    _shownId = null;
  }

  /// True, once, when the arrival snackbar on screen is for notice [id].
  bool takeIfShowing(int id) {
    if (_shownId != id) return false;
    _seq++;
    _shownId = null;
    return true;
  }
}

/// Shows [bar] as the arrival snackbar for notice [id] and records it in
/// [tracker]. Whatever [messenger] shows or has queued is cleared first,
/// so the arrival is the snackbar on screen (a queued one would otherwise
/// become current while the tracker says the arrival is — Codex r2 #3).
void showArrivalSnack(
  ScaffoldMessengerState messenger,
  ArrivalSnackTracker tracker,
  int id,
  SnackBar bar,
) {
  messenger.clearSnackBars();
  final closed = tracker.shown(id);
  messenger.showSnackBar(bar).closed.then((_) => closed());
}
