import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/notifications/notifications_screen.dart';
import 'package:omni_hr/services/notification_service.dart';

/// A notification list the test sets directly: no session, no polling.
class FakeNotifications extends NotificationService {
  FakeNotifications(this._list);

  final List<NotificationRecord> _list;
  final List<int> marked = [];

  @override
  List<NotificationRecord> get items => _list;

  @override
  int get unreadCount => _list.where((n) => !n.read).length;

  @override
  bool get loading => false;

  @override
  String? get lastError => null;

  @override
  Future<void> refreshList() async {}

  @override
  Future<void> markRead(int id) async => marked.add(id);
}

void main() {
  late FakeNotifications svc;
  late List<String> taps;

  setUp(() {
    taps = [];
    svc = FakeNotifications([
      NotificationRecord(
        id: 11,
        kind: 'leave_approval_requested',
        title: 'Approval needed',
        body: 'Lim Say Puay requests 2d Annual Leave, 06 Oct – 07 Oct.',
        payload: const {'leave_id': 148, 'step': 'manager_approval'},
      ),
      NotificationRecord(
        id: 12,
        kind: 'leave_first_approved',
        title: 'First approval done',
        body: 'Your Annual Leave 06 Nov was approved by Christine Ng and is '
            'now waiting for HR.',
        payload: const {'leave_id': 9, 'approver_name': 'Christine Ng'},
      ),
    ]);
  });

  Widget host() => ChangeNotifierProvider<NotificationService>.value(
        value: svc,
        child: MaterialApp(
          home: NotificationsScreen(
            onLeaveTap: (id) => taps.add('leave:$id'),
            onExpenseTap: (id) => taps.add('expense:$id'),
            onApprovalTap: (id) => taps.add('approval:$id'),
          ),
        ),
      );

  testWidgets('"Approval needed" opens the request for the approver',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approval needed'));
    await tester.pumpAndSettle();

    expect(svc.marked, [11]);
    expect(taps, ['approval:148']);
  });

  testWidgets('"First approval done" opens the employee\'s own leave history',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('First approval done'));
    await tester.pumpAndSettle();

    expect(svc.marked, [12]);
    expect(taps, ['leave:9']);
  });

  testWidgets('the new kinds get their own icons', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
  });
}
