import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/omni_colors.dart';
import '../../models/team_outlook.dart';
import '../../services/session_service.dart';
import '../team/team_colors.dart';

/// The LEAVE tab's way into the team outlook (mockup `Main.dc.html`): a
/// white card with a 2 pt leave-tint ring, "Team leave" with a NEW chip
/// until the first open, who is out this week, up to two initials faces
/// and a chevron. Shown only while `SessionService.teamLeaveEnabled`
/// (the caller decides).
class TeamLeaveTile extends StatefulWidget {
  const TeamLeaveTile({
    super.key,
    required this.summary,
    required this.emptyReason,
    required this.onTap,
  });

  /// The 30-day outlook's `summary` (A-L1); null until an answer (or a
  /// cached one) arrived.
  final TeamSummary? summary;

  /// The outlook's `empty_reason` (`off`, `no_department`, `no_approver`,
  /// `no_people`), or null.
  final String? emptyReason;

  final VoidCallback onTap;

  /// Prefs flag set on the first open; the NEW chip shows until then.
  /// Per company and employee, so another person on the phone still sees
  /// it. It survives sign-out on purpose (it is not session data).
  static String seenKey(SessionService s) =>
      'team_leave_seen|${s.clientDb}|${s.employeeId}';

  /// "2 out this week · Marketing", "No one out this week · Marketing",
  /// "No team to show yet"; null while nothing has loaded.
  static String? subtitleFor(TeamSummary? summary, String? emptyReason) {
    if (emptyReason != null) return 'No team to show yet';
    if (summary == null) return null;
    final n = summary.thisWeekOff;
    final head = n <= 0 ? 'No one out this week' : '$n out this week';
    final label = summary.label.trim();
    return label.isEmpty ? head : '$head · $label';
  }

  @override
  State<TeamLeaveTile> createState() => _TeamLeaveTileState();
}

class _TeamLeaveTileState extends State<TeamLeaveTile> {
  /// False until prefs say the tile was never opened: a user who already
  /// opened it never sees NEW flash.
  bool _isNew = false;
  late final String _seenKey;

  @override
  void initState() {
    super.initState();
    _seenKey = TeamLeaveTile.seenKey(context.read<SessionService>());
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_seenKey) ?? false;
      if (mounted && !seen) setState(() => _isNew = true);
    } catch (_) {
      // No prefs: no NEW chip. Never block the tile.
    }
  }

  Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  void _tap() {
    if (_isNew) {
      setState(() => _isNew = false);
      unawaited(_markSeen());
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final subtitle = TeamLeaveTile.subtitleFor(summary, widget.emptyReason);
    final faces = widget.emptyReason == null && summary != null
        ? summary.faces.take(2).toList()
        : const <TeamFace>[];
    final label = ['Team leave', if (_isNew) 'new', ?subtitle].join(', ');
    final c = context.omni;
    final t = TeamColors.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: _tap,
      excludeSemantics: true,
      child: Card(
        key: const ValueKey('team-leave-tile'),
        margin: EdgeInsets.zero,
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.leaveTint, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.leaveTint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.groups_outlined,
                    size: 20,
                    color: t.leaveOn,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Team leave',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                          ),
                          if (_isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey('team-leave-new'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.accentTint,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: t.onAccentTint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textSub,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (faces.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _Faces(faces: faces),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: c.textSub,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to two 26 pt initials circles, each overlapping the previous by 8 pt
/// (A-L6: no photos are fetched).
class _Faces extends StatelessWidget {
  const _Faces({required this.faces});

  final List<TeamFace> faces;

  static const double _size = 26;
  static const double _step = _size - 8;

  @override
  Widget build(BuildContext context) {
    final t = TeamColors.of(context);
    return SizedBox(
      width: _size + _step * (faces.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < faces.length; i++)
            Positioned(
              left: _step * i,
              top: 0,
              child: Container(
                key: ValueKey('team-leave-face-${faces[i].id}'),
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.avatar(faces[i].id),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.omni.card,
                    width: 2,
                  ),
                ),
                child: Text(
                  faces[i].initials,
                  style: TextStyle(
                    color: t.onAvatar,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
