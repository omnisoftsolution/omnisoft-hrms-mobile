import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/team_outlook.dart';
import 'team_colors.dart';
import 'team_format.dart';

/// The outlook's calendar heat map (D1): a legend, then one card per month
/// the range touches. A day's shade is the number of people off
/// (`days[].off`); tapping a day in range calls [onSelect].
///
/// The range is the outlook's `days` list (one entry per date, first to
/// last); days outside it are dimmed and cannot be tapped.
class TeamHeatMap extends StatelessWidget {
  const TeamHeatMap({
    super.key,
    required this.outlook,
    required this.selected,
    required this.onSelect,
  });

  final TeamOutlook outlook;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = outlook.days;
    final byDay = {for (final d in days) isoDay(d.date): d};
    final months = <DateTime>[];
    if (days.isNotEmpty) {
      final from = dayOnly(days.first.date);
      final to = dayOnly(days.last.date);
      var m = DateTime(from.year, from.month);
      final last = DateTime(to.year, to.month);
      // 90 days touch at most 4 months; the cap guards against a bad range.
      while (!m.isAfter(last) && months.length < 13) {
        months.add(m);
        m = DateTime(m.year, m.month + 1);
      }
    }
    final sel = selected == null ? null : dayOnly(selected!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Legend(),
        for (final month in months) ...[
          const SizedBox(height: 12),
          _MonthCard(
            month: month,
            from: dayOnly(days.first.date),
            to: dayOnly(days.last.date),
            today: outlookToday(outlook),
            selected: sel,
            byDay: byDay,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  static const _style = TextStyle(fontSize: 11, color: TeamColors.muted);

  Widget _swatch(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: _style),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('People off:', style: _style),
          _swatch(TeamColors.c1, '1'),
          _swatch(TeamColors.c2, '2'),
          _swatch(TeamColors.c3, '3+'),
          _swatch(TeamColors.holCell, 'PH = public holiday'),
          const Text('Tap a day to see who', style: _style),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.from,
    required this.to,
    required this.today,
    required this.selected,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime from;
  final DateTime to;
  final DateTime today;
  final DateTime? selected;
  final Map<String, TeamDay> byDay;
  final ValueChanged<DateTime> onSelect;

  static const _cellHeight = 40.0;
  static const _gap = 4.0;
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Widget _row(List<Widget> seven) => Row(
    children: [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: _gap),
        Expanded(child: seven[i]),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final slots = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(height: _cellHeight),
      for (var d = 1; d <= daysInMonth; d++)
        _cell(DateTime(month.year, month.month, d)),
    ];
    while (slots.length % 7 != 0) {
      slots.add(const SizedBox(height: _cellHeight));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.glassShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              monthLabel(month),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
              ),
            ),
          ),
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _row([
                for (final w in _weekdays)
                  Text(
                    w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TeamColors.muted,
                    ),
                  ),
              ]),
            ),
          ),
          for (var r = 0; r < slots.length; r += 7) ...[
            if (r > 0) const SizedBox(height: _gap),
            _row(slots.sublist(r, r + 7)),
          ],
        ],
      ),
    );
  }

  Widget _cell(DateTime date) {
    final iso = isoDay(date);
    final inRange = !date.isBefore(from) && !date.isAfter(to);
    if (!inRange) {
      return ExcludeSemantics(
        child: Opacity(
          opacity: 0.35,
          child: Container(
            key: ValueKey('heat-cell-$iso'),
            height: _cellHeight,
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.onSurface,
              ),
            ),
          ),
        ),
      );
    }
    final day = byDay[iso];
    final off = day?.off ?? 0;
    final holiday = day?.holiday;
    final everyone = holiday != null && holiday.everyone;
    final workday = day?.workday ?? true;
    final fill = everyone
        ? TeamColors.holCell
        : !workday
        ? TeamColors.cellOff
        : TeamColors.shade(off);
    final fg = fill == TeamColors.c3 ? TeamColors.onC3 : AppTheme.onSurface;
    final isToday = date == today;
    final isSelected = date == selected;
    final side = isSelected
        ? const BorderSide(color: TeamColors.accent, width: 2)
        : isToday
        ? const BorderSide(color: TeamColors.accent, width: 1.5)
        : BorderSide.none;
    final sub = everyone ? 'PH' : (off > 0 ? '$off off' : '');
    return Semantics(
      button: true,
      label: heatDayLabel(date, off, holidayName: holiday?.name),
      child: Material(
        key: ValueKey('heat-cell-$iso'),
        color: fill,
        shape: RoundedRectangleBorder(
          side: side,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('heat-tap-$iso'),
          onTap: () => onSelect(date),
          child: SizedBox(
            height: _cellHeight,
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                color: fg,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (holiday != null && !everyone)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        key: ValueKey('heat-hol-dot-$iso'),
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: TeamColors.holDot,
                        ),
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
