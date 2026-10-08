import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/models/leave_type.dart';
import 'package:omni_hr/screens/leave/leave_screen.dart';
import 'package:omni_hr/services/holiday_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

class FakeApi extends OmniMobileApi {
  FakeApi({this.applyResponse = const {}})
    : super(baseUrl: '', db: '', token: '');

  Map<String, dynamic> applyResponse;
  int applies = 0;
  int typeCalls = 0;

  /// Days left on Annual Leave, per getLeaveTypes call (last repeats).
  List<double>? balances;

  @override
  Future<List<ApprovalItem>> getPendingApprovals() async => const [];

  @override
  Future<List<LeaveType>> getLeaveTypes() async {
    final b = balances;
    final left = b?[typeCalls.clamp(0, b.length - 1)];
    typeCalls++;
    return [
      LeaveType.fromJson({
        'id': 74,
        'name': 'Annual Leave',
        'request_unit': 'day',
        'requires_allocation': left != null,
        'virtual_remaining_leaves': ?left,
      }),
    ];
  }

  @override
  Future<Map<String, dynamic>> applyLeave({
    required int holidayStatusId,
    required String dateFrom,
    required String dateTo,
    String reason = '',
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
    Map<String, dynamic>? attachment,
  }) async {
    applies++;
    return applyResponse;
  }
}

/// The Time Off approver /me reported: the employee's manager.
class FakeSession extends SessionService {
  int meRefreshes = 0;

  @override
  String get employeeTimeOffApprover => 'Manager Mia';

  @override
  Future<bool> refreshMe() async {
    meRefreshes++;
    return true;
  }
}

/// Became an approver since the last /me: the next /me says so.
class NewApproverSession extends SessionService {
  int meCalls = 0;

  @override
  Future<bool> refreshMe() async {
    meCalls++;
    await updateLeaveApprovalsFromMe({
      'leave_approvals': {'enabled': true, 'pending_count': 1},
    });
    return true;
  }
}

Widget host(FakeApi api, {SessionService? session}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SessionService>(
      create: (_) => session ?? FakeSession(),
    ),
    ChangeNotifierProvider<HolidayService>(create: (_) => HolidayService()),
  ],
  child: MaterialApp(
    home: LeaveScreen(
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
    ),
  ),
);

Future<void> submitAnnualLeave(WidgetTester tester) async {
  await tester.tap(find.text('Annual Leave'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('SUBMIT LEAVE'));
  await tester.tap(find.text('SUBMIT LEAVE'));
  await tester.pumpAndSettle();
  expect(find.text('Leave request submitted'), findsOneWidget);
}

void main() {
  group('receiptApprover', () {
    test('uses the apply response when the key is there', () {
      expect(receiptApprover({'approver': 'HR Hana'}, 'Manager Mia'),
          'HR Hana');
      expect(receiptApprover({'approver': ''}, 'Manager Mia'), '');
      expect(receiptApprover({'approver': false}, 'Manager Mia'), '');
    });

    test('falls back to /me only when the key is absent (older server)', () {
      expect(receiptApprover({'leave_id': 1}, 'Manager Mia'), 'Manager Mia');
    });
  });

  test('receiptStatus: approved on creation is not waiting', () {
    expect(receiptStatus({'state': 'validate'}), 'Approved');
    expect(receiptStatus({'state': 'confirm'}), 'Waiting for approval');
    expect(receiptStatus({}), 'Waiting for approval');
  });

  testWidgets('receipt shows the approver the server named (HR-only type)', (
    tester,
  ) async {
    final api = FakeApi(
      applyResponse: {
        'success': true,
        'leave_id': 42,
        'state': 'confirm',
        'approver': 'HR Hana',
      },
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await submitAnnualLeave(tester);
    expect(api.applies, 1);
    expect(find.text('Approver'), findsOneWidget);
    expect(find.text('HR Hana'), findsOneWidget);
    expect(find.text('Manager Mia'), findsNothing);
    expect(find.text('#42'), findsOneWidget);
  });

  testWidgets('auto-approved: no Approver row, reads Approved', (
    tester,
  ) async {
    final api = FakeApi(
      applyResponse: {
        'success': true,
        'leave_id': 43,
        'state': 'validate',
        'approver': '',
      },
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await submitAnnualLeave(tester);
    expect(find.text('Approver'), findsNothing);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsNothing);
  });

  testWidgets('an older server (no approver key) keeps the /me approver', (
    tester,
  ) async {
    final api = FakeApi(
      applyResponse: {'success': true, 'leave_id': 44, 'state': 'confirm'},
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await submitAnnualLeave(tester);
    expect(find.text('Approver'), findsOneWidget);
    expect(find.text('Manager Mia'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
  });

  group('the Leave tab re-reads the approvals block (M8)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('opening it shows the Leave approvals row', (tester) async {
      final session = NewApproverSession();
      expect(session.leaveApprovalsEnabled, isFalse);
      await tester.pumpWidget(host(FakeApi(), session: session));
      await tester.pumpAndSettle();
      expect(session.meCalls, 1);
      expect(find.byKey(const ValueKey('leave-approvals-row')), findsOneWidget);
    });

    testWidgets('tab re-opens within 30 s do not re-ask; a pull-down does', (
      tester,
    ) async {
      final session = NewApproverSession();
      final key = GlobalKey<LeaveScreenState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionService>.value(value: session),
            ChangeNotifierProvider<HolidayService>(
              create: (_) => HolidayService(),
            ),
          ],
          child: MaterialApp(
            home: LeaveScreen(
              key: key,
              apiBuilder: (_) => FakeApi(),
              appBar: AppBar(title: const Text('TEST BAR')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.meCalls, 1);

      // HomeShell calls refresh() on every switch to the Leave tab.
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(session.meCalls, 1);

      await key.currentState!.refresh(force: true); // pull-down
      await tester.pumpAndSettle();
      expect(session.meCalls, 2);
    });
  });

  testWidgets('balances reload after a submitted leave (N1)', (tester) async {
    final api = FakeApi(
      applyResponse: {'success': true, 'leave_id': 45, 'state': 'confirm'},
    )..balances = [5, 4];
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    expect(find.text('5d left'), findsOneWidget);

    await submitAnnualLeave(tester);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(api.typeCalls, 2);
    expect(find.text('4d left'), findsOneWidget);
    expect(find.text('5d left'), findsNothing);
  });

  testWidgets('closing the sheet without submitting does not reload', (
    tester,
  ) async {
    final api = FakeApi()..balances = [5, 4];
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(api.typeCalls, 1);
    expect(find.text('5d left'), findsOneWidget);
  });
}
