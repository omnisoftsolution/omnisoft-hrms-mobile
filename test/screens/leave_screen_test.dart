import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

  @override
  Future<List<LeaveType>> getLeaveTypes() async => [
    LeaveType.fromJson({
      'id': 74,
      'name': 'Annual Leave',
      'request_unit': 'day',
      'requires_allocation': false,
    }),
  ];

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
}
