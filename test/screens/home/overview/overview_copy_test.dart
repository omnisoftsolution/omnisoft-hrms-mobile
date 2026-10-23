import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/overview_copy.dart';

void main() {
  test('the six buckets in tile order', () {
    expect(overviewBucketOrder, [
      'on_time',
      'late',
      'not_in_yet',
      'no_check_in',
      'on_leave',
      'off_today',
    ]);
  });

  test('labels (D8: "No check-in")', () {
    expect(overviewBucketOrder.map(overviewBucketLabel).toList(), [
      'On time',
      'Late',
      'Not in yet',
      'No check-in',
      'On leave',
      'Off today',
    ]);
    expect(overviewBucketLabel('weird'), '');
  });

  test('hints are the mockup copy, verbatim', () {
    expect(
      overviewBucketHint('on_time'),
      'Checked in within the grace period.',
    );
    expect(
      overviewBucketHint('late'),
      'Checked in after the grace period of their attendance rule. Latest first.',
    );
    expect(
      overviewBucketHint('not_in_yet'),
      'Their shift has not started, or started less than 30 minutes ago. '
      'Part-day leave is shown here when work is still due later.',
    );
    expect(
      overviewBucketHint('no_check_in'),
      'No check-in 30 minutes after their shift started — the same rule My '
      'day uses. It updates the moment they check in.',
    );
    expect(
      overviewBucketHint('on_leave'),
      'Approved leave covers all of today’s shift. Pending requests are not '
      'counted here.',
    );
    expect(
      overviewBucketHint('off_today'),
      'No shift today (day off, part-time pattern or public holiday).',
    );
    expect(overviewBucketHint('weird'), '');
  });

  test('count per bucket', () {
    final counts = OverviewCounts.fromJson({
      'on_time': 36,
      'late': 6,
      'not_in_yet': 4,
      'no_check_in': 3,
      'on_leave': 4,
      'off_today': 1,
      'checked_in': 42,
      'expected': 49,
      'tracked': 54,
    });
    expect(
      overviewBucketOrder.map((b) => overviewCountOf(counts, b)).toList(),
      [36, 6, 4, 3, 4, 1],
    );
    expect(overviewCountOf(counts, 'weird'), 0);
  });
}
