import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
import '../../models/team_outlook.dart';
import 'team_colors.dart';
import 'team_format.dart';
import 'team_widgets.dart';

/// Who is off on one day of the outlook: the title (date · holiday ·
/// "N off") and one row per leave covering the day. The same content is the
/// inline card under the calendar ([inSheet] false) and the day sheet a tap
/// opens ([showTeamDaySheet], [inSheet] true).
class TeamDayDetail extends StatelessWidget {
  const TeamDayDetail({
    super.key,
    required this.outlook,
    required this.day,
    this.inSheet = false,
  });

  final TeamOutlook outlook;
  final DateTime day;
  final bool inSheet;

  /// The day's title as the mockup `selTitle`: date · holiday · "N off".
  static String titleOf(TeamOutlook o, DateTime day) {
    final entry = _entry(o, day);
    final off = entry?.off ?? 0;
    final holiday = entry?.holiday;
    return '${dayTitle(day)}'
        '${holiday != null && holiday.name.isNotEmpty ? ' · ${holiday.name}' : ''}'
        ' · $off off';
  }

  static TeamDay? _entry(TeamOutlook o, DateTime day) {
    TeamDay? entry;
    for (final d in o.days) {
      if (dayOnly(d.date) == dayOnly(day)) entry = d;
    }
    return entry;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final off = _entry(outlook, day)?.off ?? 0;
    // days[].off is the server's count; the rows are the leaves covering the
    // day, shown only when that count says someone is off.
    final rows = off > 0
        ? leavesOnByName(outlook, dayOnly(day))
        : const <TeamLeaveRow>[];
    final people = {for (final p in outlook.people) p.id: p};
    final rowPrefix = inSheet ? 'team-sheet-row' : 'team-row';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: inSheet
              ? const EdgeInsets.fromLTRB(20, 0, 20, 6)
              : const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            titleOf(outlook, day),
            key: inSheet ? const ValueKey('team-day-sheet-title') : null,
            style: inSheet
                ? TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  )
                : TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textSub,
                  ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: inSheet
                ? const EdgeInsets.fromLTRB(20, 4, 20, 8)
                : const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              // In the sheet the day was just tapped: no "tap" hint.
              inSheet ? 'No one off.' : 'No one off. Tap a shaded day.',
              style: TextStyle(
                fontSize: 13,
                color: TeamColors.of(context).muted,
              ),
            ),
          )
        else
          for (final r in rows)
            _TeamPersonRow(
              key: ValueKey('$rowPrefix-${r.id}'),
              row: r,
              person: people[r.employeeId],
              horizontal: inSheet ? 20 : 16,
            ),
      ],
    );
  }
}

class _TeamPersonRow extends StatelessWidget {
  const _TeamPersonRow({
    super.key,
    required this.row,
    required this.person,
    required this.horizontal,
  });

  final TeamLeaveRow row;
  final TeamPerson? person;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final r = row;
    final p = person;
    final type = r.type;
    final when =
        leaveWhenLabel(r) +
        (type != null && type.isNotEmpty ? ' · $type' : '');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 10),
      child: Row(
        children: [
          TeamAvatar(id: r.employeeId, initials: p?.initials ?? ''),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ),
                    if (p?.you ?? false) ...[
                      const SizedBox(width: 6),
                      const TeamYouChip(),
                    ],
                  ],
                ),
                Text(
                  when,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSub,
                  ),
                ),
              ],
            ),
          ),
          if (r.isPending) ...[
            const SizedBox(width: 8),
            const TeamPendingChip(),
          ],
        ],
      ),
    );
  }
}

/// The day sheet of the outlook (1.34.1): a tap on a calendar day opens who
/// is off that day here, instead of only updating the card below up to four
/// month cards (off screen).
///
/// Like My day's `showDaySheet`, it is **deliberately on the tab
/// navigator** (`useRootNavigator: false`): the outlook is pushed on the
/// LEAVE / Home tab navigator, so the sheet rises from the bottom bar and
/// stops there. It scrolls when many people are off.
Future<void> showTeamDaySheet(
  BuildContext context,
  TeamOutlook outlook,
  DateTime day,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('team-day-sheet'),
        padding: const EdgeInsets.only(bottom: 24),
        child: TeamDayDetail(outlook: outlook, day: day, inSheet: true),
      ),
    ),
  );
}
