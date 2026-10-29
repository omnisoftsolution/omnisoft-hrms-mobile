import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/omni_colors.dart';

const double _weekdayFontSize = 13;

/// Height of the weekday row: one line of the (scaled) weekday text
/// plus breathing room, never less than TableCalendar's 16 px default.
double weekdayRowHeight(TextScaler scaler) =>
    scaler.scale(_weekdayFontSize) * 1.4 + 6;

class RangePickerDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? Function(DateTime)? holidayName;
  final bool Function(DateTime)? isNonWorkingDay;
  /// Optional working-days calculator. When provided, the picker's
  /// header shows the count from this function (e.g. excludes
  /// weekends + holidays) instead of raw calendar days. Otherwise
  /// falls back to (end - start + 1) inclusive-calendar-day count.
  ///
  /// Wire to HolidayService.workingDaysBetween from leave-create
  /// flow so the count shown while choosing dates matches what the
  /// leave form shows after the picker closes.
  final int Function(DateTime start, DateTime end)? dayCount;

  const RangePickerDialog({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
    required this.lastDate,
    this.holidayName,
    this.isNonWorkingDay,
    this.dayCount,
  });

  @override
  State<RangePickerDialog> createState() => _RangePickerDialogState();
}

class _RangePickerDialogState extends State<RangePickerDialog> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _focused;
  // TableCalendar's own page controller, so our month header (with
  // labelled arrow buttons) can turn the page.
  PageController? _pageController;

  static DateTime _month(DateTime d) => DateTime(d.year, d.month);

  bool get _canGoBack => _month(_focused).isAfter(_month(widget.firstDate));
  bool get _canGoForward =>
      _month(_focused).isBefore(_month(widget.lastDate));

  void _turnPage({required bool forward}) {
    final c = _pageController;
    if (c == null) return;
    const duration = Duration(milliseconds: 300);
    if (forward) {
      c.nextPage(duration: duration, curve: Curves.easeOut);
    } else {
      c.previousPage(duration: duration, curve: Curves.easeOut);
    }
  }

  /// Month title between two arrow buttons. TableCalendar's built-in
  /// header has unlabelled chevrons; these carry "Previous month" /
  /// "Next month" tooltips (read by TalkBack / VoiceOver).
  Widget _monthHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: _canGoBack ? () => _turnPage(forward: false) : null,
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM('en_US').format(_focused),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: _canGoForward ? () => _turnPage(forward: true) : null,
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _focused = widget.initialStart;
  }

  Widget _selectedHolidayHint() {
    final names = <String>{};
    final f = widget.holidayName;
    if (f != null && _start != null) {
      final endOrStart = _end ?? _start!;
      var d = _start!;
      while (!d.isAfter(endOrStart)) {
        final n = f(d);
        if (n != null) names.add(n);
        d = d.add(const Duration(days: 1));
      }
    }
    if (names.isEmpty) return const SizedBox.shrink();
    final c = context.omni;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy, size: 16, color: c.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              names.length == 1
                  ? 'Public holiday: ${names.first}'
                  : 'Public holidays: ${names.join(', ')}',
              style: TextStyle(fontSize: 12, color: c.error),
            ),
          ),
        ],
      ),
    );
  }

  void _onDayTapped(DateTime selected, DateTime focused) {
    final tapped = DateTime(selected.year, selected.month, selected.day);
    setState(() {
      _focused = focused;
      if (_start == null || _end != null) {
        _start = tapped;
        _end = null;
      } else if (tapped.isBefore(_start!)) {
        _start = tapped;
        _end = null;
      } else {
        _end = tapped;
      }
    });
    if (_start != null && _end != null) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          Navigator.of(context).pop(
              DateTimeRange(start: _start!, end: _end!));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM');
    final c = context.omni;
    // table_calendar's own greys are kept exactly in light; dark uses
    // the tokens (its defaults are dark greys meant for white).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final int dayCount;
    if (_start != null && _end != null) {
      dayCount = widget.dayCount?.call(_start!, _end!) ??
          (_end!.difference(_start!).inDays + 1);
    } else {
      dayCount = 0;
    }
    final headerText = _start == null
        ? 'Select start date'
        : _end == null
            ? '${fmt.format(_start!)} → ?'
            : '${fmt.format(_start!)} → ${fmt.format(_end!)}  ·  ${dayCount}d';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(headerText,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            _monthHeader(),
            TableCalendar(
              headerVisible: false,
              onCalendarCreated: (c) => _pageController = c,
              onPageChanged: (focused) => setState(() => _focused = focused),
              // The weekday row ("Sun Mon Tue …") was a fixed 16 px and
              // clipped its text on the Samsung; size it from the font.
              daysOfWeekHeight: weekdayRowHeight(
                MediaQuery.textScalerOf(context),
              ),
              firstDay: widget.firstDate,
              lastDay: widget.lastDate,
              focusedDay: _focused,
              rangeStartDay: _start,
              rangeEndDay: _end,
              rangeSelectionMode: RangeSelectionMode.toggledOff,
              selectedDayPredicate: (day) =>
                  _start != null && _end == null && isSameDay(day, _start),
              holidayPredicate: (day) =>
                  widget.holidayName?.call(day) != null,
              onDaySelected: _onDayTapped,
              calendarBuilders: CalendarBuilders(
                // One line, shrunk rather than wrapped or clipped when a
                // big system font meets a narrow phone.
                dowBuilder: (context, day) {
                  final weekend = day.weekday == DateTime.saturday ||
                      day.weekday == DateTime.sunday;
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        DateFormat.E('en_US').format(day),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: _weekdayFontSize,
                          color: dark
                              ? (weekend ? c.textMuted : c.textSub)
                              : weekend
                                  ? const Color(0xFF6A6A6A)
                                  : const Color(0xFF4F4F4F),
                        ),
                      ),
                    ),
                  );
                },
                defaultBuilder: (context, day, focusedDay) {
                  if (widget.isNonWorkingDay?.call(day) == true &&
                      widget.holidayName?.call(day) == null) {
                    final inRange = _start != null &&
                        _end != null &&
                        !day.isBefore(_start!) &&
                        !day.isAfter(_end!);
                    return Container(
                      margin: const EdgeInsets.all(4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: inRange
                            ? c.accent.withValues(alpha: 0.15)
                            : null,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color:
                              c.textSub.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return null;
                },
                holidayBuilder: (context, day, focusedDay) {
                  final inRange = _start != null &&
                      _end != null &&
                      !day.isBefore(_start!) &&
                      !day.isAfter(_end!);
                  final isStart =
                      _start != null && isSameDay(day, _start);
                  final isEnd = _end != null && isSameDay(day, _end);
                  final selectedOnly = _start != null &&
                      _end == null &&
                      isSameDay(day, _start);
                  if (isStart || isEnd || selectedOnly) {
                    return null; // let default range start/end render
                  }
                  return Container(
                    margin: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inRange
                          ? c.accent.withValues(alpha: 0.15)
                          : null,
                      shape: BoxShape.rectangle,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.error.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: c.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: c.brandFill,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(
                    color: c.onBrandFill, fontWeight: FontWeight.w600),
                rangeStartDecoration: BoxDecoration(
                  color: c.brandFill,
                  shape: BoxShape.circle,
                ),
                rangeEndDecoration: BoxDecoration(
                  color: c.brandFill,
                  shape: BoxShape.circle,
                ),
                withinRangeDecoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.15),
                  shape: BoxShape.rectangle,
                ),
                rangeStartTextStyle: TextStyle(
                    color: c.onBrandFill, fontWeight: FontWeight.w600),
                rangeEndTextStyle: TextStyle(
                    color: c.onBrandFill, fontWeight: FontWeight.w600),
                todayDecoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(color: c.accent),
                weekendTextStyle: dark
                    ? TextStyle(color: c.textMuted)
                    : const TextStyle(color: Color(0xFF5A5A5A)),
                disabledTextStyle: dark
                    ? TextStyle(color: c.textMuted.withValues(alpha: 0.5))
                    : const TextStyle(color: Color(0xFFBFBFBF)),
                outsideDaysVisible: false,
              ),
              availableGestures: AvailableGestures.horizontalSwipe,
            ),
            if (widget.holidayName != null) ...[
              const SizedBox(height: 8),
              _selectedHolidayHint(),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
