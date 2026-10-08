import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/home/home_shell.dart';

NotificationRecord _leaveApproved() => NotificationRecord(
  id: 7,
  kind: 'leave_approved',
  title: 'Leave approved',
  body: 'Your Annual Leave for 20 Oct → 21 Oct was approved.',
  payload: const {'leave_id': 42},
);

/// Shows the arrival snackbar from a button, like HomeShell does.
Widget _host(NotificationRecord n, VoidCallback onAction) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(notificationArrivalSnackBar(n, onAction: onAction)),
          child: const Text('ARRIVE'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the arrival snackbar with VIEW goes away by itself (APP-8)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_leaveApproved(), () {}));
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    expect(find.text('Leave approved'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    // Past its 5 s duration plus the exit animation.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('VIEW still runs the action', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_host(_leaveApproved(), () => opened++));
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VIEW'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('a kind with nowhere to go has no action', (tester) async {
    await tester.pumpWidget(
      _host(NotificationRecord(id: 8, kind: 'system', title: 'Hello'), () {}),
    );
    await tester.tap(find.text('ARRIVE'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBarAction), findsNothing);
  });

  NotificationRecord n(String kind, {int id = 1}) =>
      NotificationRecord(id: id, kind: kind, title: 't', body: '');

  test('a decision on my leave reloads History while it is on screen (M4)', () {
    for (final kind in [
      'leave_approved',
      'leave_refused',
      'leave_first_approved',
    ]) {
      expect(reloadsLeaveHistory([n(kind)], tabIndex: historyTabIndex),
          isTrue, reason: kind);
      // Another tab: History reloads when it is opened anyway.
      expect(reloadsLeaveHistory([n(kind)], tabIndex: 0), isFalse);
    }
    expect(
      reloadsLeaveHistory([n('leave_approval_requested')],
          tabIndex: historyTabIndex),
      isFalse,
    );
    expect(reloadsLeaveHistory([], tabIndex: historyTabIndex), isFalse);
  });

  test('a leave decision under a newer expense arrival still reloads', () {
    // One poll brought both; the expense one is the newest (snackbar).
    final batch = [n('expense_approved', id: 12), n('leave_refused', id: 11)];
    expect(reloadsLeaveHistory(batch, tabIndex: historyTabIndex), isTrue);
    expect(
      refreshesApprovals([n('expense_approved', id: 12),
          n('leave_approval_requested', id: 11)]),
      isTrue,
    );
    expect(refreshesApprovals(batch), isFalse);
  });
}
