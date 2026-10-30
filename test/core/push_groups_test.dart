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

  test('automatic-punch confirmations open Home but are not reminders', () {
    for (final k in ['auto_checked_in', 'auto_checked_out']) {
      expect(isAutoConfirmationKind(k), isTrue);
      expect(isReminderKind(k), isFalse);
      expect(opensHomeKind(k), isTrue);
    }
    expect(opensHomeKind('remind_check_out'), isTrue);
    expect(opensHomeKind('auto_recheck'), isFalse);
    expect(opensHomeKind('leave_approved'), isFalse);
    expect(
      autoConfirmationTitle('auto_checked_out'),
      'Checked out automatically',
    );
    expect(
      autoConfirmationTitle('auto_checked_in'),
      'Checked in automatically',
    );
  });
}
