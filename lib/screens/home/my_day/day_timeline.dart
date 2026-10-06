import 'package:flutter/material.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

enum TimelineKind { anchor, punch, lunch, now }

enum RailStyle { solid, dashed, dotted, none }

class TimelineEvent {
  const TimelineEvent({
    required this.at,
    required this.title,
    required this.sub,
    required this.kind,
    required this.tone,
    this.badge = '',
    this.rail = RailStyle.dotted,
    this.railColor = const Color(0xFFBCC9CA),
    this.current = false,
    this.upcoming = false,
  });

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
        at: at, title: title, sub: sub, badge: badge, kind: kind, tone: tone,
        rail: rail ?? this.rail, railColor: railColor ?? this.railColor,
        current: current, upcoming: upcoming,
      );
}

const _grey = MyDayColors.waiting;

bool _overlaps(String aStart, String aEnd, String bStart, String bEnd) =>
    aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;

/// The rows of the timeline in time order (spec 2026-10-06 §4.4). Pure,
/// so the tests check the data and not the paint.
@visibleForTesting
List<TimelineEvent> buildTimeline(MyDay day) {
  final shift = day.shift;
  final punches = day.punches;
  if (shift == null && punches.isEmpty) return const [];
  final display = displayOf(day);
  final open = day.state == 'checked_in' || day.state == 'on_break';
  final events = <TimelineEvent>[];

  if (shift != null) {
    final missing = display == MyDayDisplay.missing;
    final late = day.lateMinutes > 0;
    events.add(TimelineEvent(
      at: shift.start,
      title: 'Shift starts',
      sub: missing
          ? 'No kiosk check-in yet'
          : (punches.isEmpty ? 'Check in at the kiosk' : shift.blocksLabel),
      kind: TimelineKind.anchor,
      tone: missing ? MyDayColors.missing : (punches.isEmpty ? _grey : MyDayColors.work),
      badge: missing ? 'Missing' : '',
      rail: missing || late ? RailStyle.dashed : (punches.isEmpty ? RailStyle.dotted : RailStyle.solid),
      railColor: missing
          ? MyDayColors.missing.dot
          : (late ? MyDayColors.late.dot : (punches.isEmpty ? _grey.dot : MyDayColors.work.dot)),
      upcoming: punches.isEmpty && !missing,
    ));
    if (missing) {
      events.add(TimelineEvent(
        at: '',
        title: 'Now',
        sub: 'If you are at work, check in at the kiosk',
        kind: TimelineKind.now,
        tone: MyDayColors.missing,
        rail: RailStyle.dotted,
        railColor: _grey.dot,
        current: true,
      ));
    }
  }

  for (var i = 0; i < punches.length; i++) {
    final p = punches[i];
    final last = i == punches.length - 1;
    final isBreak = p.kind == 'break_start';
    var tone = isBreak ? MyDayColors.brk : MyDayColors.work;
    var badge = '';
    if (p.kind == 'check_in') {
      if (day.lateMinutes > 0) {
        tone = MyDayColors.late;
        badge = '${minutesLabel(day.lateMinutes)} late';
      } else if (shift != null) {
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
    // Rail under this punch: what happens between it and the next event.
    RailStyle rail;
    Color railColor;
    if (last && open) {
      rail = RailStyle.dotted;
      railColor = _grey.dot;
    } else if (p.kind == 'check_in' || p.kind == 'break_end') {
      rail = RailStyle.solid;
      railColor = MyDayColors.work.dot;
    } else if (p.kind == 'break_start') {
      rail = RailStyle.dashed;
      railColor = MyDayColors.brk.dot;
    } else if (day.earlyMinutes > 0) {
      rail = RailStyle.dashed;
      railColor = MyDayColors.late.dot;
    } else {
      rail = RailStyle.none;
      railColor = Colors.transparent;
    }
    events.add(TimelineEvent(
      at: p.at,
      title: p.label,
      sub: p.placeLabel,
      kind: TimelineKind.punch,
      tone: tone,
      badge: badge,
      rail: rail,
      railColor: railColor,
      current: last && open,
    ));
  }

  // The scheduled lunch, unless a punched break overlaps it or the day is
  // over for someone who punches breaks.
  final lunch = day.lunch;
  if (lunch != null) {
    var punchedOver = false;
    for (var i = 0; i + 1 < punches.length; i++) {
      if (punches[i].kind == 'break_start' &&
          _overlaps(punches[i].at, punches[i + 1].at, lunch.start, lunch.end)) {
        punchedOver = true;
      }
    }
    final dayOver = day.state == 'checked_out' && !day.breakExempt;
    if (!punchedOver && !dayOver) {
      events.add(TimelineEvent(
        at: lunch.start,
        title: 'Lunch',
        sub: '${lunch.label} · from your work schedule',
        kind: TimelineKind.lunch,
        tone: _grey,
        rail: RailStyle.dotted,
        railColor: _grey.dot,
        upcoming: true,
      ));
    }
  }

  if (shift != null) {
    final overtime = day.overtimeMinutes > 0;
    final passed = day.state == 'checked_out' && day.earlyMinutes == 0;
    events.add(TimelineEvent(
      at: shift.end,
      title: 'Shift ends',
      sub: display == MyDayDisplay.early
          ? 'Coming back? This counts as a break.'
          : (passed ? shift.label : 'Check out at the kiosk'),
      kind: TimelineKind.anchor,
      tone: passed ? MyDayColors.work : _grey,
      rail: overtime ? RailStyle.solid : RailStyle.none,
      railColor: overtime ? MyDayColors.overtime.dot : Colors.transparent,
      upcoming: !passed,
    ));
  }

  // Stable sort by time; the "Now" row (no time) keeps its place after
  // the start anchor. UTC strings sort as text.
  final order = List<int>.generate(events.length, (i) => i)
    ..sort((a, b) {
      final ea = events[a];
      final eb = events[b];
      if (ea.at.isEmpty || eb.at.isEmpty) return a.compareTo(b);
      final byTime = ea.at.compareTo(eb.at);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  final sorted = [for (final i in order) events[i]];
  // The last row never draws a rail.
  if (sorted.isNotEmpty) {
    sorted[sorted.length - 1] =
        sorted.last.copyWith(rail: RailStyle.none, railColor: Colors.transparent);
  }
  return sorted;
}

/// Today as a timeline with a drawn rail (spec 2026-10-06 §4.4).
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.day});

  final MyDay day;

  static const emptyText = 'No attendance recorded today.';

  @override
  Widget build(BuildContext context) {
    final events = buildTimeline(day);
    final text = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(emptyText, style: text.bodyMedium?.copyWith(color: AppTheme.outline)),
      );
    }
    return Column(
      children: [for (var i = 0; i < events.length; i++) _row(text, i, events[i])],
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
    final tinted = e.tone != MyDayColors.work && e.tone != MyDayColors.brk && !e.upcoming;
    final titleColor = e.upcoming ? AppTheme.onSurfaceVariant : AppTheme.onSurface;
    final timeText = e.at.isEmpty ? 'now' : DateTimeUtils.formatLocalTime(e.at);
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
                child: Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  width: 52,
                  decoration: BoxDecoration(
                    color: tinted ? e.tone.tint : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(timeText,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(
                          color: tinted ? e.tone.onTint : titleColor,
                          fontWeight: FontWeight.w700)),
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
                    child: Icon(_icon(e), size: 14, color: filled ? Colors.white : ringColor),
                  ),
                  Expanded(
                    child: CustomPaint(painter: _RailPainter(e.rail, e.railColor)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    e.kind == TimelineKind.anchor ? 0 : 12, 3, 0, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7,
                      runSpacing: 4,
                      children: [
                        Text(e.title,
                            style: (e.kind == TimelineKind.anchor
                                    ? text.titleMedium
                                    : text.bodyLarge)
                                ?.copyWith(
                                    color: titleColor,
                                    fontWeight: e.kind == TimelineKind.anchor
                                        ? FontWeight.w700
                                        : FontWeight.w600)),
                        if (e.badge.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: e.tone.tint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(e.badge,
                                style: text.labelSmall?.copyWith(
                                    color: e.tone.onTint, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    if (e.sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(e.sub,
                            style: text.bodySmall?.copyWith(color: AppTheme.outline)),
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
  bool shouldRepaint(_RailPainter old) => old.style != style || old.color != color;
}
