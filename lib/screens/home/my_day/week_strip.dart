import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

enum _Mark { dot, calendar, star, none }

class _Cell {
  const _Cell({
    required this.day,
    required this.fill,
    required this.ring,
    required this.text,
    required this.mark,
    required this.markColor,
    this.hollow = false,
  });

  final MyDayWeekDay day;
  final Color fill;
  final Color ring;
  final Color text;
  final _Mark mark;
  final Color markColor;

  /// A ring instead of a filled dot (future days).
  final bool hollow;
}

/// "This week": one cell per day, Monday first, with a legend for the
/// holidays and leave in the week (spec 2026-10-06 §4.3).
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.day});

  final MyDay day;

  static String _dayName(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null ? '' : DateFormat('EEE', 'en_US').format(parsed);
  }

  static bool _todayCounts(MyDay day) => day.state != 'not_in';

  static String workedSoFar(MyDay day) {
    var count = day.week.where((d) => d.kind == 'worked').length;
    if (day.week.any((d) => d.kind == 'today') && _todayCounts(day)) count++;
    return '$count day${count == 1 ? '' : 's'} worked so far';
  }

  _Cell _cell(MyDayWeekDay d, MyDayTone today) {
    switch (d.kind) {
      case 'today':
        return _Cell(day: d, fill: today.tint, ring: today.dot, text: today.onTint,
            mark: _Mark.dot, markColor: today.dot);
      case 'worked':
        final late = d.verdict == 'late' || d.verdict == 'early_leave';
        return _Cell(day: d, fill: MyDayColors.work.tint, ring: Colors.transparent,
            text: MyDayColors.work.onTint, mark: _Mark.dot,
            markColor: late ? MyDayColors.late.dot : MyDayColors.work.dot);
      case 'absent':
        return _Cell(day: d, fill: MyDayColors.missing.tint, ring: Colors.transparent,
            text: MyDayColors.missing.onTint, mark: _Mark.dot,
            markColor: MyDayColors.missing.dot);
      case 'public_holiday':
        return _Cell(day: d, fill: MyDayColors.holiday.tint, ring: Colors.transparent,
            text: MyDayColors.holiday.onTint, mark: _Mark.star,
            markColor: MyDayColors.holiday.dot);
      case 'leave':
        return _Cell(day: d, fill: MyDayColors.leave.tint, ring: Colors.transparent,
            text: MyDayColors.leave.onTint, mark: _Mark.calendar,
            markColor: MyDayColors.leave.dot);
      case 'scheduled':
        return _Cell(day: d, fill: Colors.white, ring: Colors.transparent,
            text: AppTheme.onSurfaceVariant, mark: _Mark.dot,
            markColor: MyDayColors.waiting.dot, hollow: true);
      default:
        return _Cell(day: d, fill: Colors.transparent, ring: Colors.transparent,
            text: AppTheme.outline, mark: _Mark.dot,
            markColor: AppTheme.outlineVariant, hollow: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (day.week.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final today = toneOf(displayOf(day));
    final cells = day.week.map((d) => _cell(d, today)).toList();
    final legend = [
      for (final d in day.week)
        if (d.kind == 'public_holiday' || d.kind == 'leave')
          (
            text: '${_dayName(d.date)} · ${d.name.isEmpty ? (d.kind == 'leave' ? 'Leave' : 'Public holiday') : d.name}',
            tone: d.kind == 'leave' ? MyDayColors.leave : MyDayColors.holiday,
            icon: d.kind == 'leave' ? Icons.event_outlined : Icons.star_outline,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('This week',
                  style: text.labelLarge?.copyWith(
                      color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
            Text(workedSoFar(day),
                style: text.bodySmall?.copyWith(color: AppTheme.outline)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _cellWidget(text, cells[i])),
            ],
          ],
        ),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in legend)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.tone.tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 13, color: item.tone.onTint),
                      const SizedBox(width: 6),
                      Text(item.text,
                          style: text.labelMedium?.copyWith(
                              color: item.tone.onTint, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cellWidget(TextTheme text, _Cell cell) {
    final Widget mark;
    switch (cell.mark) {
      case _Mark.calendar:
        mark = Icon(Icons.event_outlined, size: 14, color: cell.markColor);
      case _Mark.star:
        mark = Icon(Icons.star_outline, size: 14, color: cell.markColor);
      case _Mark.none:
        mark = const SizedBox(height: 10);
      case _Mark.dot:
        mark = Container(
          key: ValueKey('week-dot-${cell.day.date}'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cell.hollow ? Colors.transparent : cell.markColor,
            border: Border.all(color: cell.markColor, width: 2),
          ),
        );
    }
    return Container(
      key: ValueKey('week-${cell.day.date}'),
      height: 52,
      decoration: BoxDecoration(
        color: cell.fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cell.ring, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_dayName(cell.day.date),
              style: text.labelMedium
                  ?.copyWith(color: cell.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          mark,
        ],
      ),
    );
  }
}
