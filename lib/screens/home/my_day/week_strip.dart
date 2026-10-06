import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'day_sheet.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

enum _Mark { dot, calendar, star }

class _Cell {
  const _Cell({
    required this.day,
    required this.fill,
    required this.ring,
    required this.text,
    required this.mark,
    required this.markColor,
    this.hollow = false,
    this.ringWidth = 2,
  });

  final MyDayWeekDay day;
  final Color fill;
  final Color ring;
  final Color text;
  final _Mark mark;
  final Color markColor;

  /// A ring instead of a filled dot (future days).
  final bool hollow;
  final double ringWidth;
}

/// "This week": one cell per day, Monday first. A tap on any day but today
/// opens the day sheet (spec 2026-10-06 §4.3, §8.2).
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.day});

  final MyDay day;

  static String _dayName(String date) {
    final parsed = DateTime.tryParse(date);
    return parsed == null ? '' : DateFormat('EEE', 'en_US').format(parsed);
  }

  static String _kindLabel(MyDayWeekDay d) {
    switch (d.kind) {
      case 'today':
        return 'today';
      case 'worked':
        return 'worked';
      case 'absent':
        return 'no check-in';
      case 'public_holiday':
        return d.name.isEmpty ? 'public holiday' : 'public holiday, ${d.name}';
      case 'leave':
        return d.name.isEmpty ? 'leave' : 'leave, ${d.name}';
      case 'scheduled':
        return 'scheduled';
      default:
        return 'no shift';
    }
  }

  static String semanticLabel(MyDayWeekDay d) =>
      '${_dayName(d.date)}, ${_kindLabel(d)}';

  static bool _todayCounts(MyDay day) => day.state != 'not_in';

  static String workedSoFar(MyDay day) {
    var count = day.week.where((d) => d.kind == 'worked').length;
    if (day.week.any((d) => d.kind == 'today') && _todayCounts(day)) count++;
    return '$count day${count == 1 ? '' : 's'} worked so far';
  }

  _Cell _cell(MyDayWeekDay d, MyDayTone today) {
    switch (d.kind) {
      case 'today':
        return _Cell(
          day: d,
          fill: today.tint,
          ring: today.dot,
          text: today.onTint,
          mark: _Mark.dot,
          markColor: today.dot,
        );
      case 'worked':
        final late = d.verdict == 'late' || d.verdict == 'early_leave';
        return _Cell(
          day: d,
          fill: MyDayColors.work.tint,
          ring: Colors.transparent,
          text: MyDayColors.work.onTint,
          mark: _Mark.dot,
          markColor: late ? MyDayColors.late.dot : MyDayColors.work.dot,
        );
      case 'absent':
        return _Cell(
          day: d,
          fill: MyDayColors.missing.tint,
          ring: Colors.transparent,
          text: MyDayColors.missing.onTint,
          mark: _Mark.dot,
          markColor: MyDayColors.missing.dot,
        );
      case 'public_holiday':
        return _Cell(
          day: d,
          fill: MyDayColors.holiday.tint,
          ring: Colors.transparent,
          text: MyDayColors.holiday.onTint,
          mark: _Mark.star,
          markColor: MyDayColors.holiday.dot,
        );
      case 'leave':
        return _Cell(
          day: d,
          fill: MyDayColors.leave.tint,
          ring: Colors.transparent,
          text: MyDayColors.leave.onTint,
          mark: _Mark.calendar,
          markColor: MyDayColors.leave.dot,
        );
      case 'scheduled':
        return _Cell(
          day: d,
          fill: Colors.white,
          ring: AppTheme.outlineVariant,
          text: AppTheme.onSurfaceVariant,
          mark: _Mark.dot,
          markColor: MyDayColors.waiting.dot,
          hollow: true,
          ringWidth: 1,
        );
      default:
        return _Cell(
          day: d,
          fill: Colors.transparent,
          ring: Colors.transparent,
          text: AppTheme.outline,
          mark: _Mark.dot,
          markColor: AppTheme.outlineVariant,
          hollow: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (day.week.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final today = toneOf(displayOf(day));
    final cells = day.week.map((d) => _cell(d, today)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'This week',
                style: text.labelLarge?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              workedSoFar(day),
              style: text.bodySmall?.copyWith(color: AppTheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _cellWidget(context, text, cells[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _cellWidget(BuildContext context, TextTheme text, _Cell cell) {
    final Widget mark;
    switch (cell.mark) {
      case _Mark.calendar:
        mark = Icon(Icons.event_outlined, size: 14, color: cell.markColor);
      case _Mark.star:
        mark = Icon(Icons.star_outline, size: 14, color: cell.markColor);
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
    final box = Container(
      key: ValueKey('week-${cell.day.date}'),
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 52),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _dayName(cell.day.date),
              style: text.labelMedium?.copyWith(
                color: cell.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            mark,
          ],
        ),
      ),
    );
    final tappable = cell.day.kind != 'today';
    // Fill and ring live on the Material so the InkWell splash paints above
    // them (a child decoration would cover the ripple).
    return Semantics(
      button: tappable,
      label: semanticLabel(cell.day),
      child: Material(
        color: cell.fill,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: cell.ring, width: cell.ringWidth),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('week-tap-${cell.day.date}'),
          onTap: tappable ? () => showDaySheet(context, cell.day) : null,
          child: box,
        ),
      ),
    );
  }
}
