import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/approvals_home_card.dart';

/// A session whose approvals capability the test sets directly.
class FakeSession extends SessionService {
  FakeSession({required this.enabled, required this.count});

  bool enabled;
  int count;

  @override
  bool get leaveApprovalsEnabled => enabled;

  @override
  int get leaveApprovalsPendingCount => count;

  void update({required bool enabled, required int count}) {
    this.enabled = enabled;
    this.count = count;
    notifyListeners();
  }
}

Widget host(FakeSession session, {String breakdown = '', VoidCallback? onTap}) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: ApprovalsHomeCard(breakdown: breakdown, onTap: onTap ?? () {}),
        ),
      ),
    );

ApprovalItem item(String type, {bool mine = true}) =>
    ApprovalItem(id: 1, leaveTypeName: type, assignedToMe: mine);

void main() {
  testWidgets('hidden for a user who cannot approve (and on an old connector)',
      (tester) async {
    await tester.pumpWidget(
        host(FakeSession(enabled: false, count: 0), breakdown: '2 Annual Leave'));
    expect(find.text('Leave approvals'), findsNothing);
    expect(find.text('Nothing waiting'), findsNothing);
    expect(find.text('2 Annual Leave'), findsNothing);
  });

  testWidgets('shows the count and the per-type breakdown', (tester) async {
    await tester.pumpWidget(host(FakeSession(enabled: true, count: 3),
        breakdown: '2 Annual Leave · 1 Sick Leave'));
    expect(find.text('Leave approvals'), findsOneWidget);
    expect(find.text('3 waiting for you'), findsOneWidget);
    expect(find.text('2 Annual Leave · 1 Sick Leave'), findsOneWidget);
  });

  testWidgets('an approver with nothing waiting still gets the card',
      (tester) async {
    await tester.pumpWidget(host(FakeSession(enabled: true, count: 0),
        breakdown: '2 Annual Leave'));
    expect(find.text('Leave approvals'), findsOneWidget);
    expect(find.text('Nothing waiting'), findsOneWidget);
    // A stale breakdown is never shown next to "Nothing waiting".
    expect(find.text('2 Annual Leave'), findsNothing);
  });

  testWidgets('tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
        host(FakeSession(enabled: true, count: 1), onTap: () => taps++));
    expect(find.text('1 waiting for you'), findsOneWidget);
    await tester.tap(find.byType(ApprovalsHomeCard));
    expect(taps, 1);
  });

  testWidgets('follows the session when the count changes', (tester) async {
    final session = FakeSession(enabled: false, count: 0);
    await tester.pumpWidget(host(session));
    expect(find.text('Leave approvals'), findsNothing);

    session.update(enabled: true, count: 2);
    await tester.pump();
    expect(find.text('2 waiting for you'), findsOneWidget);

    session.update(enabled: true, count: 0);
    await tester.pump();
    expect(find.text('Nothing waiting'), findsOneWidget);
  });

  test('approvalsBreakdown counts only my steps, biggest type first', () {
    expect(
        approvalsBreakdown([
          item('Sick Leave'),
          item('Annual Leave'),
          item('Annual Leave'),
          item('Unpaid', mine: false),
        ]),
        '2 Annual Leave · 1 Sick Leave');
    expect(approvalsBreakdown([item('Unpaid', mine: false)]), '');
    expect(approvalsBreakdown(const []), '');
    expect(approvalsBreakdown([item('B'), item('A')]), '1 A · 1 B');
  });
}
