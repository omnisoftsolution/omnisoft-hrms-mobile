import 'package:flutter/material.dart';

import '../../../core/omni_colors.dart';
import '../../../models/team_overview.dart';
import '../../team/team_colors.dart';
import 'overview_copy.dart';

/// The tone of a bucket in palette [t]: Task 5's [TeamColors.bucket] for
/// the Today keys; Yesterday's `left_early`, `absent` and `off` borrow Late,
/// No check-in and Off today (mockup `yTiles`).
MyDayTone overviewTone(TeamColors t, String id) => t.bucket(switch (id) {
  'left_early' => 'late',
  'absent' => 'no_check_in',
  'off' => 'off_today',
  _ => id,
});

/// One count tile: its bucket id (for the tone and the tap), label, count.
class OverviewCell {
  const OverviewCell(this.id, this.label, this.count);

  final String id;
  final String label;
  final int count;
}

List<OverviewCell> todayCells(OverviewCounts c) => [
  for (final b in overviewBucketOrder)
    OverviewCell(b, overviewBucketLabel(b), c.countOf(b)),
];

const _yesterdayLabels = {
  'on_time': OverviewCopy.yOnTime,
  'late': OverviewCopy.yLate,
  'left_early': OverviewCopy.yLeftEarly,
  'absent': OverviewCopy.yAbsent,
  'on_leave': OverviewCopy.yOnLeave,
  'off': OverviewCopy.yOff,
};

List<OverviewCell> yesterdayCells(ReviewedDay r) => [
  for (final id in ReviewedDay.buckets)
    OverviewCell(id, _yesterdayLabels[id] ?? id, r.countOf(id)),
];

/// Today's teal tile: "{checked_in} checked in", "of {expected} expected ·
/// {label} today", the mutually exclusive bar of on time / late / not in
/// yet / no check-in with its legend, and the live line.
class OverviewTodayTile extends StatelessWidget {
  const OverviewTodayTile({
    super.key,
    required this.counts,
    required this.scopeLabel,
    required this.asOf,
    required this.live,
  });

  final OverviewCounts counts;
  final String scopeLabel;
  final String asOf;
  final bool live;

  static const barBuckets = ['on_time', 'late', 'not_in_yet', 'no_check_in'];

  @override
  Widget build(BuildContext context) {
    final t = TeamColors.of(context);
    final segments = <(String, int)>[
      for (final id in barBuckets)
        if (counts.countOf(id) > 0) (id, counts.countOf(id)),
    ];
    return Container(
      key: const ValueKey('ov-today-tile'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.overviewTile,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.tileBadge,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.groups_outlined,
                  color: t.onTile,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      OverviewCopy.checkedIn(counts.totalCheckedIn),
                      style: TextStyle(
                        color: t.onTile,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      OverviewCopy.ofExpectedToday(
                        counts.totalExpected,
                        scopeLabel,
                      ),
                      style: TextStyle(
                        color: t.onTileSoft,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: t.tileLine),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 12,
                child: ColoredBox(
                  color: t.tileTrack,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (id, n) in segments)
                        Expanded(
                          key: ValueKey('ov-bar-$id'),
                          flex: n,
                          child: ColoredBox(color: overviewTone(t, id).fill),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final (id, n) in segments)
                Row(
                  key: ValueKey('ov-legend-$id'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: overviewTone(t, id).fill,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${overviewBucketLabel(id)} $n',
                      style: TextStyle(
                        color: t.onTileSoft,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (live) ...[
            const SizedBox(height: 8),
            Text(
              OverviewCopy.liveLine(asOf, counts.totalTracked),
              style: TextStyle(
                color: t.onTileFaint,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yesterday's blue tile: "{worked} worked", the expected line with the
/// date, and the A-L7 copy (provisional or final).
class OverviewYesterdayTile extends StatelessWidget {
  const OverviewYesterdayTile({
    super.key,
    required this.reviewed,
    required this.scopeLabel,
  });

  final ReviewedDay reviewed;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    final t = TeamColors.of(context);
    return Container(
      key: const ValueKey('ov-yesterday-tile'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.overviewTileYesterday,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            OverviewCopy.worked(reviewed.totalWorked),
            style: TextStyle(
              color: t.onTile,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            OverviewCopy.ofExpectedOn(
              reviewed.totalExpected,
              reviewed.date,
              scopeLabel,
            ),
            style: TextStyle(color: t.onTileSoft, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: t.tileLine),
          const SizedBox(height: 10),
          Text(
            reviewed.provisional
                ? OverviewCopy.reviewedProvisional
                : OverviewCopy.reviewedFinal,
            style: TextStyle(color: t.onTileFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The 3 × 2 count tiles. [onTap] null = not tappable (counts only, or
/// Yesterday).
class OverviewCountGrid extends StatelessWidget {
  const OverviewCountGrid({super.key, required this.cells, this.onTap});

  final List<OverviewCell> cells;
  final void Function(String bucket)? onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < cells.length; start += 3) {
      if (start > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = start; i < start + 3; i++) ...[
              if (i > start) const SizedBox(width: 8),
              Expanded(
                child: i < cells.length
                    ? _CountTile(cell: cells[i], onTap: onTap)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.cell, this.onTap});

  final OverviewCell cell;
  final void Function(String bucket)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final tap = onTap;
    final VoidCallback? handler = tap == null ? null : () => tap(cell.id);
    return Semantics(
      button: handler != null,
      label: OverviewCopy.tileSemantics(cell.label, cell.count),
      onTap: handler,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('ov-tile-${cell.id}'),
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: handler,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: overviewTone(
                            TeamColors.of(context),
                            cell.id,
                          ).dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${cell.count}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cell.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
