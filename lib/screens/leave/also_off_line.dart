import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/team_outlook.dart';
import '../../services/omni_mobile_api.dart';
import '../team/team_colors.dart';
import '../team/team_format.dart';

/// What the apply sheet pops when "See team leave" is tapped. The Leave
/// tab turns it into a push of the outlook on its own Navigator (the
/// sheet lives on the root Navigator). A leave id is always > 0 and DONE
/// pops null, so this never collides.
const int seeTeamLeaveResult = -1;

/// One line of the "Also off" box: the name, then T5's [leaveWhenLabel]
/// (one date wording app-wide; overlap rows send no `number_of_days`, so
/// no day count), then " · pending" (D3): "Rachel Wong · Thu 12 Nov",
/// "Jason Lee · Thu 12 Nov (afternoon) · pending",
/// "Kelvin Goh · Tue 3 Nov, 09:30 – 17:00". The overlap answer never
/// carries the leave type (contract), so none is shown.
String alsoOffText(TeamLeaveRow r) {
  final when = leaveWhenLabel(r);
  final name = r.name.trim();
  final head = name.isEmpty ? when : '$name · $when';
  return r.state == 'pending' ? '$head · pending' : head;
}

/// The apply sheet's informational box (mockup `Main.dc.html`). Never a
/// warning colour and never tied to the submit button (standing rule:
/// leave never blocks work).
class AlsoOffLine extends StatelessWidget {
  const AlsoOffLine({
    super.key,
    required this.overlap,
    required this.onSeeTeamLeave,
  });

  final TeamOverlap overlap;
  final VoidCallback onSeeTeamLeave;

  static const title = 'Also off on these dates';
  static const reassurance =
      'Just so you know — this never stops you applying.';

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: TeamColors.leaveOn,
    );
    return Container(
      key: const ValueKey('also-off-line'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: TeamColors.leaveTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, size: 18, color: TeamColors.leaveOn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TeamColors.leaveOn,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final person in overlap.people)
            Text(alsoOffText(person), style: body),
          if (overlap.more > 0) Text('+${overlap.more} more', style: body),
          Text(
            reassurance,
            style: body.copyWith(
              color: TeamColors.leaveOn.withValues(alpha: 0.8),
            ),
          ),
          TextButton(
            key: const ValueKey('also-off-see-team'),
            onPressed: onSeeTeamLeave,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 40),
              foregroundColor: TeamColors.leaveOn,
            ),
            child: const Text(
              'See team leave',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The apply sheet's "Also off" lookup: asks [fetch] [delay] after the
/// last date change, drops answers for dates the user has since changed
/// (a sequence counter, as `_fetchPreview` does), hides on any error and
/// stops asking once an older connector answered with a missing route.
class TeamOverlapLookup {
  TeamOverlapLookup({
    required this.fetch,
    required this.onChanged,
    this.delay = const Duration(milliseconds: 400),
  });

  final Future<TeamOverlap> Function(DateTime from, DateTime to) fetch;

  /// Called when an answer (or a failure) changed [value].
  final VoidCallback onChanged;
  final Duration delay;

  TeamOverlap? _value;
  Timer? _timer;
  int _seq = 0;
  String _askedFor = '';
  DateTime? _from;
  DateTime? _to;
  bool _unavailable = false;
  bool _disposed = false;

  /// The current answer; null while waiting, after an error, or before
  /// the first answer.
  TeamOverlap? get value => _value;

  /// Whether there is anyone to show.
  bool get visible => _value?.people.isNotEmpty ?? false;

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Call after the dates changed, inside the caller's setState (the old
  /// answer is cleared without [onChanged]; the caller's rebuild hides
  /// it). The same dates as last time are not asked again, unless that
  /// last ask failed.
  void schedule(DateTime from, DateTime to) {
    if (_disposed || _unavailable) return;
    final key = '${_day(from)}|${_day(to)}';
    if (key == _askedFor) return;
    _askedFor = key;
    _from = from;
    _to = to;
    _timer?.cancel();
    final seq = ++_seq;
    _value = null;
    _timer = Timer(delay, () => _run(seq, from, to));
  }

  /// The shown answer no longer holds (A-L22: the team binding it was
  /// asked under moved). It goes at once, without [onChanged] (the caller
  /// rebuilds), and an answer still on the wire is dropped. With
  /// [askAgain] the last dates are asked again after [delay].
  void invalidate({bool askAgain = true}) {
    if (_disposed) return;
    _timer?.cancel();
    _seq++;
    _value = null;
    _askedFor = '';
    final from = _from;
    final to = _to;
    if (askAgain && from != null && to != null) schedule(from, to);
  }

  Future<void> _run(int seq, DateTime from, DateTime to) async {
    try {
      final answer = await fetch(from, to);
      if (_disposed || seq != _seq) return;
      _value = answer;
    } catch (e) {
      // Informational only: any failure hides the line.
      debugPrint('leave/team_overlap unavailable: $e');
      if (_disposed || seq != _seq) return;
      _value = null;
      // Forget the dates, so the same dates are asked again on the next
      // schedule (a network blip must not leave the line empty for good).
      _askedFor = '';
      if (isMissingRoute(e)) _unavailable = true;
    }
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
