import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
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

  Widget _swatch(
    TextStyle style,
    Color color,
    String label, {
    Key? key,
    Color? border,
  }) => Row(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: border == null ? null : Border.all(color: border),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: style),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = TeamColors.of(context);
    final style = TextStyle(fontSize: 11, color: t.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('People off:', style: style),
          _swatch(
            style,
            t.cell0,
            '0',
            key: const ValueKey('legend-0'),
            border: t.cellLine,
          ),
          _swatch(style, t.c1, '1'),
          _swatch(style, t.c2, '2'),
          _swatch(style, t.c3, '3+'),
          _swatch(
            style,
            t.holCell,
            'PH = public holiday',
            key: const ValueKey('legend-ph'),
          ),
          Text('Tap a day to see who', style: style),
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
    final c = context.omni;
    final t = TeamColors.of(context);
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final slots = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(height: _cellHeight),
      for (var d = 1; d <= daysInMonth; d++)
        _cell(c, t, DateTime(month.year, month.month, d)),
    ];
    while (slots.length % 7 != 0) {
      slots.add(const SizedBox(height: _cellHeight));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              monthLabel(month),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _row([
                for (var i = 0; i < _weekdays.length; i++)
                  Text(
                    _weekdays[i],
                    key: i == 6 ? const ValueKey('heat-head-sun') : null,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      // Sunday in red, like a paper calendar (1.34.1).
                      color: i == 6 ? t.sunday : t.muted,
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

  Widget _cell(OmniColors c, TeamColors t, DateTime date) {
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.text,
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
        ? t.holCell
        : !workday
        ? t.cellOff
        : t.shade(off);
    final dark = fill == t.c3;
    // The count / "PH" line: [TeamColors.onC3] on the strongest shade, the
    // shade's own text colour on c1 / c2 (white in dark), red "PH".
    final shadeFg = fill == t.c1
        ? t.onC1
        : fill == t.c2
        ? t.onC2
        : c.text;
    final subFg = everyone
        ? t.holText
        : dark
        ? t.onC3
        : shadeFg;
    // The digit: Sunday red unless the shade is too dark for it, a muted
    // digit on a non-working day, else the sub line's colour.
    final isSunday = date.weekday == DateTime.sunday;
    final digitFg = dark
        ? t.onC3
        : isSunday && fill != t.c2
        ? t.sunday
        : fill == t.cellOff
        ? t.offDigit
        : shadeFg;
    final isToday = date == today;
    final isSelected = date == selected;
    final side = isSelected
        ? BorderSide(color: t.accent, width: 2)
        : isToday
        ? BorderSide(color: t.accent, width: 1.5)
        : fill == t.cell0
        ? BorderSide(color: t.cellLine)
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
                              color: digitFg,
                            ),
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                color: subFg,
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.holDot,
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
