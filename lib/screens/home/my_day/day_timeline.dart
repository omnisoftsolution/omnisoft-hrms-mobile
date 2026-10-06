import 'package:flutter/material.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';

enum TimelineStatus { done, now, upcoming }

class _Event {
  const _Event(this.at, this.title, this.sub, this.status);

  /// UTC "yyyy-MM-dd HH:mm:ss".
  final String at;
  final String title;
  final String sub;
  final TimelineStatus status;
}

/// Today as a timeline: shift start, the punches (with their place),
/// shift end.
///
/// Rows are ordered purely by time. Punches are not assumed to lie inside the
/// shift window: a night-shift worker's open check-in from the previous day is
/// carried into today's punches and sorts before "Shift starts".
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.day});

  final MyDay day;

  static const emptyText = 'No attendance recorded today.';

  List<_Event> _events() {
    final shift = day.shift;
    final punches = day.punches;
    final checkedOut = day.state == 'checked_out';
    final events = <_Event>[
      if (shift != null)
        _Event(shift.start, 'Shift starts', shift.label,
            punches.isEmpty ? TimelineStatus.now : TimelineStatus.done),
      for (var i = 0; i < punches.length; i++)
        _Event(
          punches[i].at,
          punches[i].label,
          punches[i].placeLabel,
          i == punches.length - 1 && !checkedOut
              ? TimelineStatus.now
              : TimelineStatus.done,
        ),
    ];
    // The UTC strings sort chronologically as text. List.sort is not
    // stable, so the original index breaks ties.
    final order = List<int>.generate(events.length, (i) => i)
      ..sort((a, b) {
        final byTime = events[a].at.compareTo(events[b].at);
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    return [
      for (final i in order) events[i],
      if (shift != null && !checkedOut)
        _Event(shift.end, 'Shift ends',
            day.kioskOnly ? 'Check out at the kiosk' : '',
            TimelineStatus.upcoming),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final events = _events();
    final text = Theme.of(context).textTheme;
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(emptyText,
            style: text.bodyMedium?.copyWith(color: AppTheme.outline)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) _row(text, i, events[i]),
      ],
    );
  }

  Widget _row(TextTheme text, int index, _Event event) {
    final isNow = event.status == TimelineStatus.now;
    final isUpcoming = event.status == TimelineStatus.upcoming;
    final dotColor = isUpcoming ? AppTheme.outlineVariant : AppTheme.primary;
    final textColor = isUpcoming ? AppTheme.outline : AppTheme.onSurface;
    return Padding(
      key: ValueKey('timeline-$index-${event.status.name}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(DateTimeUtils.formatLocalTime(event.at),
                style: text.bodyMedium?.copyWith(color: textColor)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 12),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // "now" is a ring, done is filled, upcoming is a pale dot.
                color: isNow ? AppTheme.surfaceContainerLowest : dotColor,
                border: Border.all(color: dotColor, width: isNow ? 4 : 1),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: text.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight: isNow ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (event.sub.isNotEmpty)
                  Text(event.sub,
                      style:
                          text.bodySmall?.copyWith(color: AppTheme.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
