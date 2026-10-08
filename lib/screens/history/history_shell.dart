import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session_service.dart';
import '../../widgets/omni_app_bar.dart';
import '../attendance_history/attendance_history_screen.dart';
import '../leave_history/leave_history_screen.dart';

enum _HistoryTab { leave, attendance }

class HistoryShell extends StatefulWidget {
  const HistoryShell({super.key});

  @override
  State<HistoryShell> createState() => HistoryShellState();
}

class HistoryShellState extends State<HistoryShell> {
  _HistoryTab _tab = _HistoryTab.leave;

  final _leaveKey = GlobalKey<LeaveHistoryScreenState>();
  final _attendanceKey = GlobalKey<AttendanceHistoryScreenState>();

  /// Called by HomeShell when the user taps the History bottom-nav icon.
  /// Refreshes the currently visible sub-tab so re-tapping always pulls
  /// fresh data, matching the behavior the leave screen had on its own.
  Future<void> refresh() async {
    if (_tab == _HistoryTab.leave) {
      await _leaveKey.currentState?.refresh();
    } else {
      await _attendanceKey.currentState?.refresh();
    }
  }

  /// A leave notification (approved / refused / first approval) came in
  /// while History is on screen: reload the leave list without a
  /// spinner, so a card that changed state does not keep stale Edit /
  /// Cancel buttons.
  Future<void> reloadLeaveQuietly() async {
    await _leaveKey.currentState?.refresh(quiet: true);
  }

  /// Reached via the bell → notification tap chain. Switches the
  /// segmented control to Leave (in case the user was on Attendance)
  /// and asks LeaveHistoryScreen to scroll to + highlight the matching
  /// card.
  Future<void> openLeaveAndHighlight(int leaveId) async {
    setState(() => _tab = _HistoryTab.leave);
    // Wait one frame so the IndexedStack has the leave child visible
    // before we ask its state to scroll.
    await Future.delayed(Duration.zero);
    await _leaveKey.currentState?.scrollToAndHighlight(leaveId);
  }

  @override
  Widget build(BuildContext context) {
    final timeOffOn = context.watch<SessionService>().featureTimeOff;
    // When the SaaS subscription doesn't include Time Off there's
    // nothing to show under the Leave segment, so collapse to a
    // single-tab view (Attendance only) and force the active segment.
    final showSegmented = timeOffOn;
    if (!timeOffOn && _tab == _HistoryTab.leave) {
      // Defensive: pin to Attendance so the IndexedStack doesn't try
      // to render the now-hidden Leave child as the active one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab != _HistoryTab.attendance) {
          setState(() => _tab = _HistoryTab.attendance);
        }
      });
    }
    return Scaffold(
      appBar: const OmniAppBar(title: 'History'),
      body: Column(
        children: [
          if (showSegmented)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_HistoryTab>(
                  segments: const [
                    ButtonSegment(
                      value: _HistoryTab.leave,
                      label: Text('Leave'),
                      icon: Icon(Icons.event_busy_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: _HistoryTab.attendance,
                      label: Text('Attendance'),
                      icon: Icon(Icons.fingerprint_rounded, size: 18),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) {
                    setState(() => _tab = s.first);
                    // Back on Leave: the list may be stale (decided
                    // while the user looked at Attendance).
                    if (s.first == _HistoryTab.leave) {
                      _leaveKey.currentState?.refresh(quiet: true);
                    }
                  },
                ),
              ),
            ),
          Expanded(
            // IndexedStack keeps both screens alive — switching is instant
            // and pull-to-refresh state is preserved per tab.
            child: IndexedStack(
              index: _tab.index,
              children: [
                LeaveHistoryScreen(key: _leaveKey),
                AttendanceHistoryScreen(key: _attendanceKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
