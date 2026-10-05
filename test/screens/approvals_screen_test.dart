import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/approval_detail.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/screens/approvals/approval_detail_screen.dart';
import 'package:omni_hr/screens/approvals/approvals_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

ApprovalItem pendingItem(int id, {bool mine = true, String step = 'manager_approval'}) =>
    ApprovalItem(
      id: id,
      employeeName: 'Emp $id',
      leaveTypeName: 'Annual Leave',
      state: 'confirm',
      dateFrom: DateTime(2026, 10, 6),
      dateTo: DateTime(2026, 10, 7),
      numberOfDays: 2,
      numberOfHours: 16,
      durationLabel: '2d',
      step: step,
      assignedToMe: mine,
      canApprove: true,
      canRefuse: true,
    );

ApprovalItem recentItem(int id, String outcome,
        {String reason = '', String first = '', String second = ''}) =>
    ApprovalItem(
      id: id,
      employeeName: 'Emp $id',
      leaveTypeName: 'Annual Leave',
      state: outcome == 'refused'
          ? 'refuse'
          : outcome == 'waiting_hr'
              ? 'validate1'
              : 'validate',
      dateFrom: DateTime(2026, 9, 22),
      dateTo: DateTime(2026, 9, 22),
      numberOfDays: 1,
      numberOfHours: 8,
      durationLabel: '1d',
      outcome: outcome,
      decidedAt: '2026-09-10 10:00:00',
      firstApproverName: first,
      secondApproverName: second,
      refusalReason: reason,
    );

class FakeApi extends OmniMobileApi {
  FakeApi({this.pending = const [], this.recent = const []})
      : super(baseUrl: '', db: '', token: '');

  List<ApprovalItem> pending;
  List<ApprovalItem> recent;
  Object? listError;
  int pendingCalls = 0;
  int recentCalls = 0;
  final List<int> detailRequests = [];

  @override
  Future<List<ApprovalItem>> getPendingApprovals() async {
    pendingCalls++;
    if (listError != null) throw listError!;
    return pending;
  }

  @override
  Future<List<ApprovalItem>> getRecentApprovals() async {
    recentCalls++;
    if (listError != null) throw listError!;
    return recent;
  }

  @override
  Future<ApprovalDetail> getApprovalDetail(int leaveId) async {
    detailRequests.add(leaveId);
    return ApprovalDetail.fromJson({
      'id': leaveId,
      'employee': {'id': 1, 'name': 'Emp $leaveId'},
      'leave_type': {'id': 74, 'name': 'Annual Leave'},
      'state': 'confirm',
      'can_approve': true,
      'can_refuse': true,
    });
  }
}

class FakeSession extends SessionService {
  @override
  Future<bool> refreshMe() async => true;
}

Widget host(FakeApi api) => ChangeNotifierProvider<SessionService>.value(
      value: FakeSession(),
      child: MaterialApp(home: ApprovalsScreen(apiBuilder: (_) => api)),
    );

void main() {
  testWidgets('Pending lists the requests with their step chips',
      (tester) async {
    final api = FakeApi(pending: [
      pendingItem(1),
      pendingItem(2, mine: false),
      pendingItem(3, mine: false, step: 'hr_approval'),
    ]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(find.text('Leave approvals'), findsOneWidget);
    expect(find.text('Pending · 3'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Emp 1'), findsOneWidget);
    expect(find.text('Your approval'), findsOneWidget);
    expect(find.text('Manager approval'), findsOneWidget);
    expect(find.text('HR approval'), findsOneWidget);
    expect(find.text('Annual Leave · Tue 6 Oct – Wed 7 Oct'), findsNWidgets(3));
    expect(find.text('2 days (16h)'), findsNWidgets(3));
    expect(api.pendingCalls, 1);
    expect(api.recentCalls, 1);
  });

  testWidgets('Recent shows the outcome, who approved and the refusal reason',
      (tester) async {
    final api = FakeApi(recent: [
      recentItem(4, 'approved', first: 'Christine Ng', second: 'Teoh Yit Ngoh'),
      recentItem(5, 'refused', reason: 'Month-end closing', second: 'Christine Ng'),
      recentItem(6, 'waiting_hr', first: 'Christine Ng'),
    ]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Refused'), findsOneWidget);
    expect(find.text('Waiting for HR'), findsOneWidget);
    expect(find.text('Approved by Christine Ng and Teoh Yit Ngoh'), findsOneWidget);
    expect(find.text('"Month-end closing"'), findsOneWidget);
    expect(find.text('Second approval pending'), findsOneWidget);
    expect(find.text('1 day (8h) · Decided 10 Sep'), findsNWidgets(3));
  });

  testWidgets('empty states for both segments', (tester) async {
    await tester.pumpWidget(host(FakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('Pending · 0'), findsOneWidget);
    expect(find.text('Nothing waiting for you'), findsOneWidget);
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    expect(find.text('No decisions in the last 30 days'), findsOneWidget);
    expect(find.text('Nothing waiting for you'), findsNothing);
  });

  testWidgets('tapping a row opens the request; coming back reloads the lists',
      (tester) async {
    final api = FakeApi(pending: [pendingItem(1), pendingItem(2)]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Emp 2'));
    await tester.pumpAndSettle();
    expect(find.byType(ApprovalDetailScreen), findsOneWidget);
    expect(api.detailRequests, [2]);

    api.pending = [pendingItem(1)];
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ApprovalDetailScreen), findsNothing);
    expect(api.pendingCalls, 2);
    expect(api.recentCalls, 2);
    expect(find.text('Pending · 1'), findsOneWidget);
    expect(find.text('Emp 2'), findsNothing);
  });

  testWidgets('a Recent row opens the request too', (tester) async {
    final api = FakeApi(recent: [recentItem(4, 'approved')]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emp 4'));
    await tester.pumpAndSettle();

    expect(find.byType(ApprovalDetailScreen), findsOneWidget);
    expect(api.detailRequests, [4]);
  });

  testWidgets('pull to refresh reloads both lists', (tester) async {
    final api = FakeApi(pending: [pendingItem(1)]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    api.pending = [pendingItem(1), pendingItem(7)];
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();

    expect(api.pendingCalls, 2);
    expect(find.text('Pending · 2'), findsOneWidget);
    expect(find.text('Emp 7'), findsOneWidget);
  });

  testWidgets('a failed load (old connector, no network) shows Retry',
      (tester) async {
    final api = FakeApi(pending: [pendingItem(1)])
      ..listError = ApiException('server_error');
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(
        find.text('Something went wrong on our end. Please try again in a moment.'),
        findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    api.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsNothing);
    expect(find.text('Emp 1'), findsOneWidget);
  });
}
