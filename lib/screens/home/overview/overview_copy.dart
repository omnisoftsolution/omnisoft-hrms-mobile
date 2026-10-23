import '../../../models/team_overview.dart';
import '../../team/team_format.dart';

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

/// Every other string of the Team overview, in one place.
class OverviewCopy {
  OverviewCopy._();

  static const todayLive = 'Today · live';
  static const yesterdayLabel = 'Yesterday · reviewed';
  static const whichDay = 'Which day';
  static const allDepartments = 'All';

  static String checkedIn(int n) => '$n checked in';

  static String ofExpectedToday(int expected, String label) => label.isEmpty
      ? 'of $expected expected today'
      : 'of $expected expected · $label today';

  static String liveLine(String asOf, int tracked) => [
    'Live',
    if (asOf.isNotEmpty) 'as of $asOf',
    'not yet reviewed by HR',
    '$tracked people tracked',
  ].join(' · ');

  static String worked(int n) => '$n worked';

  static String ofExpectedOn(int expected, DateTime? date, String label) => [
    'of $expected expected',
    if (date != null) dayTitle(date),
    if (label.isNotEmpty) label,
  ].join(' · ');

  /// A-L7: Yesterday is scored in the morning by the Daily Review.
  static const reviewedFinal =
      "Scored by the Daily Review — the same verdicts HR sees, including "
      "HR's corrections.";
  static const reviewedProvisional =
      'Still being scored — numbers may change tonight.';

  static const yOnTime = 'On time';
  static const yLate = 'Late';
  static const yLeftEarly = 'Left early';
  static const yAbsent = 'Absent';
  static const yOnLeave = 'On leave';
  static const yOff = 'Off';

  static const countsOnly =
      "Counts only — your company doesn't show names here.";

  static const whoOut = "Who's out";
  static String everyoneIn(String label) => 'everyone in $label';
  static String todayCount(int n) => 'TODAY · $n';
  static const next7Caption = 'NEXT 7 DAYS';
  static const partDay = 'Part day';
  static const noOneOutToday = 'No one is out today.';
  static const nothingNext7 = 'No one is booked off in the next 7 days.';
  static const seeOutlook = 'See 30 / 60 / 90 days';

  static const forYou = 'For you';

  static const noDepartment =
      'Team overview shows the people in your department. Ask HR to add '
      'you to one.';
  static const noPeople = 'No one to show here yet.';

  static String showingFrom(String hhmm) => 'Showing what you saw at $hhmm';

  static String tileSemantics(String label, int n) =>
      '$label: $n ${n == 1 ? 'person' : 'people'}';
}
