import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../models/team_overview.dart';
import '../../team/team_colors.dart';
import '../../team/team_format.dart';
import '../../team/team_widgets.dart';
import 'overview_copy.dart';

/// The second line of a "Today" row: "Fabric · Annual Leave · until Fri 23
/// Oct", "Management · On leave · today", "Marketing · morning only, back
/// 13:30", plus " · pending" for a pending request (D3). The type only when
/// the server sent it (D4).
String whoOutTodayLine(WhoOutToday p, {required DateTime today}) {
  final back = (p.backAt ?? '').trim();
  final String what;
  switch (p.part) {
    case 'morning':
      what = back.isEmpty ? 'morning only' : 'morning only, back $back';
    case 'afternoon':
      what = 'afternoon only';
    case 'hours':
      what = back.isEmpty ? 'part of the day' : 'part of the day, back $back';
    default:
      final type = (p.type ?? '').trim();
      final until = p.until;
      final when =
          until == null ||
              !DateUtils.dateOnly(until).isAfter(DateUtils.dateOnly(today))
          ? 'today'
          : 'until ${dayTitle(until)}';
      what = '${type.isEmpty ? 'On leave' : type} · $when';
  }
  return [
    if (p.department.isNotEmpty) p.department,
    what,
    if (p.state == 'pending') 'pending',
  ].join(' · ');
}

/// "Fri 23".
String next7DayLabel(DateTime d) => DateFormat('EEE d', 'en_US').format(d);

/// "Priya Nair (Marketing), Lina Koh (Fabric, pending), Daniel Tan (pending)".
String next7Names(List<WhoOutToday> people) => people
    .map((p) {
      final extra = [
        if (p.department.isNotEmpty) p.department,
        if (p.state == 'pending') 'pending',
      ];
      return extra.isEmpty ? p.name : '${p.name} (${extra.join(', ')})';
    })
    .join(', ');

/// Who's out: everyone in scope off today (part-day flagged), the next 7
/// days, and the way into the 30 / 60 / 90-day outlook. A today row opens
/// the person sheet only when [canOpenPerson] and the person is tracked.
class WhoOutCard extends StatelessWidget {
  const WhoOutCard({
    super.key,
    required this.whoOut,
    required this.scopeLabel,
    required this.today,
    required this.canOpenPerson,
    required this.onPerson,
    required this.onSeeOutlook,
  });

  final WhoOut whoOut;
  final String scopeLabel;
  final DateTime today;
  final bool canOpenPerson;
  final void Function(int employeeId) onPerson;
  final VoidCallback onSeeOutlook;

  @override
  Widget build(BuildContext context) {
    const caption = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: AppTheme.outline,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text(
                  OverviewCopy.whoOut,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                OverviewCopy.everyoneIn(scopeLabel),
                style: const TextStyle(fontSize: 12, color: AppTheme.outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  OverviewCopy.todayCount(whoOut.today.length),
                  style: caption,
                ),
              ),
              if (whoOut.today.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    OverviewCopy.noOneOutToday,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final p in whoOut.today)
                _TodayRow(
                  person: p,
                  line: whoOutTodayLine(p, today: today),
                  onTap: canOpenPerson && p.tracked
                      ? () => onPerson(p.id)
                      : null,
                ),
              Divider(
                height: 13,
                indent: 16,
                endIndent: 16,
                color: AppTheme.outlineVariant.withValues(alpha: 0.5),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(OverviewCopy.next7Caption, style: caption),
              ),
              if (whoOut.next7.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    OverviewCopy.nothingNext7,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var i = 0; i < whoOut.next7.length; i++)
                Padding(
                  key: ValueKey('ov-next-$i'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          next7DayLabel(whoOut.next7[i].date),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          next7Names(whoOut.next7[i].people),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // The server bounded the rows (who_out.truncated, K2): one
              // quiet line (A-L17).
              if (whoOut.truncated)
                const Padding(
                  key: ValueKey('ov-who-out-truncated'),
                  padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(
                    teamRowsNotShown,
                    style: TextStyle(fontSize: 12, color: TeamColors.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: OutlinedButton(
                  key: const ValueKey('ov-see-outlook'),
                  onPressed: onSeeOutlook,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    side: const BorderSide(color: AppTheme.primary, width: 1.5),
                    foregroundColor: AppTheme.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    OverviewCopy.seeOutlook,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.person, required this.line, this.onTap});

  final WhoOutToday person;
  final String line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('ov-out-${person.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            TeamAvatar(id: person.id, initials: person.initials, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (person.part != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: TeamColors.leaveTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  OverviewCopy.partDay,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TeamColors.leaveOn,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
