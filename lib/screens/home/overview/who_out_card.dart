import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/omni_colors.dart';
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

/// One person off over consecutive days of the next 7 days, with one
/// status (1.34.1): what a NEXT 7 DAYS line shows.
class Next7Range {
  const Next7Range({
    required this.person,
    required this.from,
    required this.to,
    required this.pending,
    this.until,
  });

  /// The person as the first day of the range lists them.
  final WhoOutToday person;

  /// First and last day the window lists the person in this run.
  final DateTime from;
  final DateTime to;
  final bool pending;

  /// The request's last day as the server sends it on the run's last day
  /// (`until`, connector 2.65.3; may be past the 7-day window). Null on an
  /// older connector.
  final DateTime? until;

  /// The day the line ends on: [until] when it is after [to] (the leave
  /// goes on past the window, or over days the window does not list),
  /// else [to].
  DateTime get end {
    final u = until;
    return u != null && u.isAfter(to) ? u : to;
  }

  /// "Mon 26" for one day, "Mon 26 – Thu 29" within a month, and with the
  /// months when they differ: "Mon 26 Oct – Tue 3 Nov".
  String get whenLabel {
    final last = end;
    if (from == last) return next7DayLabel(from);
    if (from.month != last.month || from.year != last.year) {
      return '${dayTitle(from)} – ${dayTitle(last)}';
    }
    return '${next7DayLabel(from)} – ${next7DayLabel(last)}';
  }

  /// "R&D · Mon 26 – Sun 1" (the department only when sent).
  String get detail => [
    if (person.department.isNotEmpty) person.department,
    whenLabel,
  ].join(' · ');

  /// "Vanessa Leonora · R&D · Mon 26 – Sun 1".
  String get line => '${person.name} · $detail';

  @override
  String toString() => '$line${pending ? ' (pending)' : ''}';
}

/// The NEXT 7 DAYS section as one line per person per run of consecutive
/// days (1.34.1; the server lists every day): a run ends at a gap (a day
/// the person is not listed, weekends included) or where the request's
/// status changes between pending and approved. With the request's `until`
/// (connector 2.65.3) a run ends on that day instead (past the window, or
/// over unlisted days such as a weekend), and a later run of the same
/// person and status that starts by then is the same leave and folds in.
/// Ordered by first day, then name. A person is matched by id; one without
/// an id (0) by name and department.
List<Next7Range> collapseNext7(List<WhoOutDay> days) {
  final sorted = [...days]
    ..sort(
      (a, b) =>
          DateUtils.dateOnly(a.date).compareTo(DateUtils.dateOnly(b.date)),
    );
  DateTime? untilOf(WhoOutToday p) =>
      p.until == null ? null : DateUtils.dateOnly(p.until!);
  final open = <String, Next7Range>{};
  final byKey = <String, List<Next7Range>>{};
  void close(String key, Next7Range run) =>
      (byKey[key] ??= <Next7Range>[]).add(run);
  for (final day in sorted) {
    final date = DateUtils.dateOnly(day.date);
    final seen = <String>{};
    for (final p in day.people) {
      final key = p.id > 0 ? 'id:${p.id}' : 'n:${p.name}|${p.department}';
      if (!seen.add(key)) continue; // listed twice on one day
      final pending = p.isPending;
      final run = open[key];
      final next = run == null ? null : DateUtils.addDaysToDate(run.to, 1);
      if (run != null && next == date && run.pending == pending) {
        open[key] = Next7Range(
          person: run.person,
          from: run.from,
          to: date,
          pending: pending,
          until: untilOf(p),
        );
      } else {
        if (run != null) close(key, run);
        open[key] = Next7Range(
          person: p,
          from: date,
          to: date,
          pending: pending,
          until: untilOf(p),
        );
      }
    }
  }
  open.forEach(close);
  // A run whose leave (until) reaches the next run of the same person and
  // status is one leave split by unlisted days: fold them.
  final out = <Next7Range>[];
  for (final runs in byKey.values) {
    Next7Range? cur;
    for (final r in runs) {
      final c = cur;
      final u = c?.until;
      if (c != null &&
          c.pending == r.pending &&
          u != null &&
          !r.from.isAfter(u)) {
        cur = Next7Range(
          person: c.person,
          from: c.from,
          to: r.to,
          pending: r.pending,
          until: r.until ?? u,
        );
      } else {
        if (c != null) out.add(c);
        cur = r;
      }
    }
    if (cur != null) out.add(cur);
  }
  out.sort((a, b) {
    final byDay = a.from.compareTo(b.from);
    if (byDay != 0) return byDay;
    final byName = a.person.name.compareTo(b.person.name);
    return byName != 0 ? byName : a.to.compareTo(b.to);
  });
  return out;
}

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
    final next7 = collapseNext7(whoOut.next7);
    final c = context.omni;
    final caption = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: c.textMuted,
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
              Expanded(
                child: Text(
                  OverviewCopy.whoOut,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textSub,
                  ),
                ),
              ),
              Text(
                OverviewCopy.everyoneIn(scopeLabel),
                style: TextStyle(fontSize: 12, color: c.textMuted),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    OverviewCopy.noOneOutToday,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSub,
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
                color: c.line.withValues(alpha: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(OverviewCopy.next7Caption, style: caption),
              ),
              if (next7.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text(
                    OverviewCopy.nothingNext7,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSub,
                    ),
                  ),
                ),
              for (var i = 0; i < next7.length; i++)
                Padding(
                  key: ValueKey('ov-next-$i'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: next7[i].person.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: ' · ${next7[i].detail}'),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: c.text,
                          ),
                        ),
                      ),
                      if (next7[i].pending) ...[
                        const SizedBox(width: 8),
                        const TeamPendingChip(),
                      ],
                    ],
                  ),
                ),
              // The server bounded the rows (who_out.truncated, K2): one
              // quiet line (A-L17).
              if (whoOut.truncated)
                Padding(
                  key: const ValueKey('ov-who-out-truncated'),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(
                    teamRowsNotShown,
                    style: TextStyle(
                      fontSize: 12,
                      color: TeamColors.of(context).muted,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: OutlinedButton(
                  key: const ValueKey('ov-see-outlook'),
                  onPressed: onSeeOutlook,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    side: BorderSide(color: c.accent, width: 1.5),
                    foregroundColor: c.accent,
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
    final c = context.omni;
    final t = TeamColors.of(context);
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSub,
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
                  color: t.leaveTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  OverviewCopy.partDay,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.leaveOn,
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
