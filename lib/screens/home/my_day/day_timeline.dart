import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

enum TimelineKind { anchor, punch, lunch, now }

enum RailStyle { solid, dashed, dotted, none }

class TimelineEvent {
  // Not const: the default rail colour reads a field of a const object,
  // which is not a constant expression.
  TimelineEvent({
    required this.at,
    required this.title,
    required this.sub,
    required this.kind,
    required this.tone,
    this.badge = '',
    this.rail = RailStyle.dotted,
    Color? railColor,
    this.current = false,
    this.upcoming = false,
  }) : railColor = railColor ?? MyDayColors.waiting.dot;

  /// UTC "yyyy-MM-dd HH:mm:ss".
  final String at;
  final String title;
  final String sub;
  final String badge;
  final TimelineKind kind;
  final MyDayTone tone;

  /// The rail segment drawn under this row, towards the next one.
  final RailStyle rail;
  final Color railColor;

  /// The latest event of an open day (gets a halo).
  final bool current;
  final bool upcoming;

  TimelineEvent copyWith({RailStyle? rail, Color? railColor}) => TimelineEvent(
    at: at,
    title: title,
    sub: sub,
    badge: badge,
    kind: kind,
    tone: tone,
    rail: rail ?? this.rail,
    railColor: railColor ?? this.railColor,
    current: current,
    upcoming: upcoming,
  );
}

const _grey = MyDayColors.waiting;

String _odooUtc(DateTime utc) => DateFormat('yyyy-MM-dd HH:mm:ss').format(utc);

bool _overlaps(String aStart, String aEnd, String bStart, String bEnd) =>
    aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;

/// The rows of the timeline in time order (spec 2026-10-06 §4.4). Pure,
/// so the tests check the data and not the paint. [now] only matters for
/// the open-break badge and whether the shift end has passed.
@visibleForTesting
List<TimelineEvent> buildTimeline(MyDay day, {DateTime? now}) {
  final shift = day.shift;
  final punches = day.punches;
  if (shift == null && punches.isEmpty) return const [];
  final nowUtc = (now ?? DateTime.now()).toUtc();
  final display = displayOf(day);
  final open = day.state == 'checked_in' || day.state == 'on_break';
  final events = <TimelineEvent>[];
  final punchKinds = Map<TimelineEvent, String>.identity();

  if (shift != null) {
    final missing = display == MyDayDisplay.missing;
    events.add(
      TimelineEvent(
        at: shift.start,
        title: 'Shift starts',
        sub: missing
            ? 'No kiosk check-in yet'
            : (punches.isEmpty ? 'Check in at the kiosk' : shift.blocksLabel),
        kind: TimelineKind.anchor,
        tone: missing
            ? MyDayColors.missing
            : (punches.isEmpty ? _grey : MyDayColors.work),
        badge: missing ? 'Missing' : '',
        upcoming: punches.isEmpty && !missing,
      ),
    );
    if (missing) {
      // The Now row sits at the real moment (never before the shift start,
      // so it keeps its place right after the start anchor).
      final nowAt = _odooUtc(nowUtc);
      events.add(
        TimelineEvent(
          at: nowAt.compareTo(shift.start) < 0 ? shift.start : nowAt,
          title: 'Now',
          sub: 'If you are at work, check in at the kiosk',
          kind: TimelineKind.now,
          tone: MyDayColors.missing,
          current: true,
        ),
      );
    }
  }

  final firstCheckIn = punches.indexWhere((p) => p.kind == 'check_in');
  for (var i = 0; i < punches.length; i++) {
    final p = punches[i];
    final last = i == punches.length - 1;
    var tone = p.kind == 'break_start' ? MyDayColors.brk : MyDayColors.work;
    var badge = '';
    // Lateness belongs to the first check-in of the day only; a return
    // after an early check-out is just work.
    if (p.kind == 'check_in' && i == firstCheckIn) {
      if (day.lateMinutes > 0) {
        tone = MyDayColors.late;
        badge = '${minutesLabel(day.lateMinutes)} late';
      } else if (shift != null && day.hasMinutes) {
        // A 2.51.0 connector sends no minute counters: zero there is
        // unknown, so say nothing rather than "On time".
        badge = 'On time';
      }
    }
    if (p.kind == 'check_out' && last) {
      if (day.earlyMinutes > 0) {
        tone = MyDayColors.late;
        badge = '${minutesLabel(day.earlyMinutes)} early';
      } else if (day.overtimeMinutes > 0) {
        tone = MyDayColors.overtime;
        badge = '${minutesLabel(day.overtimeMinutes)} overtime';
      }
    }
    if (p.kind == 'break_start' && last && day.state == 'on_break') {
      final started = DateTimeUtils.parseOdooUtc(p.at);
      final minutes = started == null
          ? 0
          : nowUtc.difference(started).inMinutes;
      badge = '${minutesLabel(minutes < 0 ? 0 : minutes)} so far';
    }
    final event = TimelineEvent(
      at: p.at,
      title: p.label,
      sub: p.placeLabel,
      kind: TimelineKind.punch,
      tone: tone,
      badge: badge,
      current: last && open,
    );
    punchKinds[event] = p.kind;
    events.add(event);
  }

  // The scheduled lunch, unless a punched break overlaps it (also an open
  // one that started inside it) or the day is over for someone who punches
  // breaks.
  final lunch = day.lunch;
  if (lunch != null) {
    var punchedOver = false;
    for (var i = 0; i + 1 < punches.length; i++) {
      if (punches[i].kind == 'break_start' &&
          _overlaps(punches[i].at, punches[i + 1].at, lunch.start, lunch.end)) {
        punchedOver = true;
      }
    }
    // An open break counts when it started inside the window or up to
    // five minutes before it (a lunch break taken a little early).
    if (punches.isNotEmpty && punches.last.kind == 'break_start') {
      final at = DateTimeUtils.parseOdooUtc(punches.last.at);
      final from = DateTimeUtils.parseOdooUtc(lunch.start);
      final to = DateTimeUtils.parseOdooUtc(lunch.end);
      if (at != null &&
          from != null &&
          to != null &&
          !at.isBefore(from.subtract(const Duration(minutes: 5))) &&
          !at.isAfter(to)) {
        punchedOver = true;
      }
    }
    final dayOver = day.state == 'checked_out' && !day.breakExempt;
    if (!punchedOver && !dayOver) {
      events.add(
        TimelineEvent(
          at: lunch.start,
          title: 'Lunch',
          sub: '${lunch.label} · from your work schedule',
          kind: TimelineKind.lunch,
          tone: _grey,
          upcoming: true,
        ),
      );
    }
  }

  if (shift != null) {
    final shiftEnd = DateTimeUtils.parseOdooUtc(shift.end);
    // A missing day never finished: the end stays upcoming even once the
    // shift end has gone by.
    final passed =
        display != MyDayDisplay.missing &&
        ((day.state == 'checked_out' && day.earlyMinutes == 0) ||
            (shiftEnd != null && !nowUtc.isBefore(shiftEnd)));
    final beforeEnd = shiftEnd == null || nowUtc.isBefore(shiftEnd);
    events.add(
      TimelineEvent(
        at: shift.end,
        title: 'Shift ends',
        sub: display == MyDayDisplay.early && beforeEnd
            ? 'Coming back? This counts as a break.'
            : (passed && !open ? shift.label : 'Check out at the kiosk'),
        kind: TimelineKind.anchor,
        tone: passed ? MyDayColors.work : _grey,
        upcoming: !passed,
      ),
    );
  }

  // Stable sort by time (UTC strings sort as text), then anchors before
  // everything else (a check-out exactly at the shift end reads "Shift
  // ends" then "Check out"), then insertion order. The "Now" row carries
  // the shift start so it keeps its place right after the start anchor.
  int rank(TimelineEvent e) => e.kind == TimelineKind.anchor ? 0 : 1;
  final order = List<int>.generate(events.length, (i) => i)
    ..sort((a, b) {
      final byTime = events[a].at.compareTo(events[b].at);
      if (byTime != 0) return byTime;
      final byRank = rank(events[a]).compareTo(rank(events[b]));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  final sorted = [for (final i in order) events[i]];
  return _withRails(day, sorted, punchKinds);
}

enum _Phase { beforeIn, working, onBreak, afterOut }

/// One pass over the sorted rows: the rail under a row shows what is
/// happening between it and the next row, not what kind of row it is.
List<TimelineEvent> _withRails(
  MyDay day,
  List<TimelineEvent> rows,
  Map<TimelineEvent, String> punchKinds,
) {
  final shift = day.shift;
  final open = day.state == 'checked_in' || day.state == 'on_break';
  final missing = displayOf(day) == MyDayDisplay.missing;
  final hasPunch = day.punches.isNotEmpty;
  // Everything from the current event on (the latest punch of an open day,
  // or the "Now" row of a missing one) is still to come.
  final currentIdx = rows.indexWhere((e) => e.current);
  final futureFrom = (open || missing) ? currentIdx : -1;
  final out = <TimelineEvent>[];
  var phase = _Phase.beforeIn;
  for (var i = 0; i < rows.length; i++) {
    final e = rows[i];
    final kind = punchKinds[e];
    if (kind == 'check_in' || kind == 'break_end') phase = _Phase.working;
    if (kind == 'break_start') phase = _Phase.onBreak;
    if (kind == 'check_out') phase = _Phase.afterOut;
    RailStyle rail;
    Color color;
    if (i == rows.length - 1) {
      rail = RailStyle.none;
      color = Colors.transparent;
    } else if (futureFrom >= 0 && i >= futureFrom) {
      rail = RailStyle.dotted;
      color = _grey.dot;
    } else {
      switch (phase) {
        case _Phase.working:
          final overtime =
              shift != null &&
              day.overtimeMinutes > 0 &&
              e.at.compareTo(shift.end) >= 0;
          rail = RailStyle.solid;
          color = overtime ? MyDayColors.overtime.dot : MyDayColors.work.dot;
        case _Phase.onBreak:
          rail = RailStyle.dashed;
          color = MyDayColors.brk.dot;
        case _Phase.beforeIn:
          if (missing) {
            rail = RailStyle.dashed;
            color = MyDayColors.missing.dot;
          } else if (day.lateMinutes > 0) {
            rail = RailStyle.dashed;
            color = MyDayColors.late.dot;
          } else if (hasPunch) {
            rail = RailStyle.solid;
            color = MyDayColors.work.dot;
          } else {
            rail = RailStyle.dotted;
            color = _grey.dot;
          }
        case _Phase.afterOut:
          if (day.earlyMinutes > 0) {
            rail = RailStyle.dashed;
            color = MyDayColors.late.dot;
          } else {
            rail = RailStyle.dotted;
            color = _grey.dot;
          }
      }
    }
    out.add(e.copyWith(rail: rail, railColor: color));
  }
  return out;
}

/// Today as a timeline with a drawn rail (spec 2026-10-06 §4.4).
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.day, this.now});

  final MyDay day;

  /// Injected clock for tests; defaults to the real time.
  final DateTime? now;

  static const emptyText = 'No attendance recorded today.';

  @override
  Widget build(BuildContext context) {
    final events = buildTimeline(day, now: now);
    final text = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText,
          style: text.bodyMedium?.copyWith(color: AppTheme.outline),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) _row(text, i, events[i]),
      ],
    );
  }

  IconData _icon(TimelineEvent e) {
    switch (e.kind) {
      case TimelineKind.anchor:
        return Icons.flag_outlined;
      case TimelineKind.punch:
        return Icons.tablet_android_outlined;
      case TimelineKind.lunch:
        return Icons.coffee_outlined;
      case TimelineKind.now:
        return Icons.schedule_outlined;
    }
  }

  Widget _row(TextTheme text, int index, TimelineEvent e) {
    final filled = e.kind == TimelineKind.punch && !e.upcoming;
    final ringColor = e.upcoming ? _grey.dot : e.tone.dot;
    final tinted =
        e.tone != MyDayColors.work && e.tone != MyDayColors.brk && !e.upcoming;
    final titleColor = e.upcoming
        ? AppTheme.onSurfaceVariant
        : AppTheme.onSurface;
    final timeText = e.kind == TimelineKind.now
        ? 'now'
        : DateTimeUtils.formatLocalTime(e.at);
    return Padding(
      key: ValueKey('timeline-$index-${e.kind.name}'),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 52,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 52),
                  child: Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: tinted ? e.tone.tint : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeText,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(
                        color: tinted ? e.tone.onTint : titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? e.tone.dot : Colors.white,
                      border: Border.all(color: ringColor, width: 2),
                      boxShadow: e.current
                          ? [BoxShadow(color: e.tone.tint, spreadRadius: 4)]
                          : null,
                    ),
                    child: Icon(
                      _icon(e),
                      size: 14,
                      color: filled ? Colors.white : ringColor,
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: _RailPainter(e.rail, e.railColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  e.kind == TimelineKind.anchor ? 0 : 12,
                  3,
                  0,
                  18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7,
                      runSpacing: 4,
                      children: [
                        Text(
                          e.title,
                          style:
                              (e.kind == TimelineKind.anchor
                                      ? text.titleMedium
                                      : text.bodyLarge)
                                  ?.copyWith(
                                    color: titleColor,
                                    fontWeight: e.kind == TimelineKind.anchor
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                        ),
                        if (e.badge.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: e.tone.tint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              e.badge,
                              style: text.labelSmall?.copyWith(
                                color: e.tone.onTint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (e.sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          e.sub,
                          style: text.bodySmall?.copyWith(
                            color: AppTheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The vertical rail segment under a row's circle: solid, dashed (6/4),
/// dotted (2/4) or nothing, 2 px wide, centred.
class _RailPainter extends CustomPainter {
  const _RailPainter(this.style, this.color);

  final RailStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == RailStyle.none || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    if (style == RailStyle.solid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }
    final dash = style == RailStyle.dashed ? 6.0 : 2.0;
    const gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      final end = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.style != style || old.color != color;
}
