import '../../../models/team_overview.dart';

// Copy for Team overview (Overview.dc.html). Task 7 starts this file with
// the bucket table the drill-down needs; Task 8 adds the overview's own
// lines below it.

/// The six live buckets, in the order the tiles and the drill-down chips
/// show them ([OverviewCounts.buckets]).
const List<String> overviewBucketOrder = OverviewCounts.buckets;

/// The bucket's label on its tile and its chip (D8: "No check-in").
String overviewBucketLabel(String bucket) => switch (bucket) {
  'on_time' => 'On time',
  'late' => 'Late',
  'not_in_yet' => 'Not in yet',
  'no_check_in' => 'No check-in',
  'on_leave' => 'On leave',
  'off_today' => 'Off today',
  _ => '',
};

/// The line under the drill-down chips: what the bucket means.
String overviewBucketHint(String bucket) => switch (bucket) {
  'on_time' => 'Checked in within the grace period.',
  'late' =>
    'Checked in after the grace period of their attendance rule. '
        'Latest first.',
  'not_in_yet' =>
    'Their shift has not started, or started less than 30 minutes ago. '
        'Part-day leave is shown here when work is still due later.',
  'no_check_in' =>
    'No check-in 30 minutes after their shift started — the same rule My '
        'day uses. It updates the moment they check in.',
  'on_leave' =>
    'Approved leave covers all of today’s shift. Pending requests are not '
        'counted here.',
  'off_today' =>
    'No shift today (day off, part-time pattern or public holiday).',
  _ => '',
};

/// The live count of [bucket] in [counts]; 0 for an unknown bucket
/// ([OverviewCounts.countOf]).
int overviewCountOf(OverviewCounts counts, String bucket) =>
    counts.countOf(bucket);
