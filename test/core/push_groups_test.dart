import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/push_groups.dart';

void main() {
  test('the six groups of spec §3.1, in app order, keys = connector PUSH_GROUPS', () {
    expect(pushGroups.map((g) => g.key), [
      'requests',
      'approvals',
      'attendance',
      'reminders',
      'news',
      'security',
    ]);
    expect(pushGroups.map((g) => g.name), [
      'My requests',
      'Approvals',
      'Attendance',
      'Check-in reminders',
      'Company news',
      'Security',
    ]);
  });

  test('only Security cannot be muted', () {
    expect(pushGroups.where((g) => !g.canMute).map((g) => g.key), ['security']);
  });

  test('reminder kinds are push-only kinds', () {
    expect(isReminderKind('remind_check_in'), isTrue);
    expect(isReminderKind('remind_check_out'), isTrue);
    expect(isReminderKind('leave_approved'), isFalse);
    expect(isReminderKind(''), isFalse);
  });
}
