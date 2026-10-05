import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/approval_detail.dart';
import 'package:omni_hr/screens/approvals/approval_detail_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

Map<String, dynamic> detailJson({
  String state = 'confirm',
  bool canApprove = true,
  bool canRefuse = true,
  List<Map<String, dynamic>> attachments = const [],
}) =>
    {
      'id': 148,
      'employee': {
        'id': 51,
        'name': 'Lim Say Puay',
        'department': 'Accounts',
        'avatar_b64': '',
        'resource_calendar': 'Standard 40 hours/week',
      },
      'leave_type': {'id': 74, 'name': 'Annual Leave'},
      'state': state,
      'validation_type': 'both',
      'request_date_from': '2026-10-06',
      'request_date_to': '2026-10-07',
      'request_unit_hours': false,
      'request_hour_from': 0.0,
      'request_hour_to': 0.0,
      'number_of_days': 2.0,
      'number_of_hours': 16.0,
      'duration_label': '2d',
      'step': 'manager_approval',
      'assigned_to_me': true,
      'has_attachment': attachments.isNotEmpty,
      'create_date': '2026-10-01 02:00:00',
      'can_approve': canApprove,
      'can_refuse': canRefuse,
      'name': 'Family trip',
      'attachments': attachments,
      'balance_after': {'unit': 'day', 'total': 14.0, 'remaining': 10.0},
      'steps': [
        {
          'label': 'manager_approval',
          'status': 'current',
          'by': null,
          'at': null,
          'candidates': ['Christine Ng'],
        },
        {
          'label': 'hr_approval',
          'status': 'next',
          'by': null,
          'at': null,
          'candidates': ['Time Off Officers'],
        },
      ],
    };

/// Scriptable API. No HTTP: every method the screen uses is overridden.
class FakeApi extends OmniMobileApi {
  FakeApi(this.detail) : super(baseUrl: '', db: '', token: '');

  Map<String, dynamic> detail;
  Object? getError;
  Object? approveError;
  Object? refuseError;
  Object? attachmentError;
  String approveResult = 'validate1';
  Completer<String>? approveGate;
  final List<String> calls = [];

  @override
  Future<ApprovalDetail> getApprovalDetail(int leaveId) async {
    calls.add('get:$leaveId');
    if (getError != null) throw getError!;
    return ApprovalDetail.fromJson(detail);
  }

  @override
  Future<String> approveLeave({
    required int leaveId,
    required String expectedState,
  }) async {
    calls.add('approve:$leaveId:$expectedState');
    if (approveError != null) throw approveError!;
    if (approveGate != null) return approveGate!.future;
    return approveResult;
  }

  @override
  Future<String> refuseLeave({
    required int leaveId,
    required String expectedState,
    required String reason,
  }) async {
    calls.add('refuse:$leaveId:$expectedState:$reason');
    if (refuseError != null) throw refuseError!;
    return 'refuse';
  }

  @override
  Future<Map<String, dynamic>> getAttachment(int attachmentId) async {
    calls.add('attachment:$attachmentId');
    if (attachmentError != null) throw attachmentError!;
    return {'success': true, 'data_b64': ''};
  }
}

/// Counts /me refreshes instead of calling the server.
class FakeSession extends SessionService {
  int refreshMeCalls = 0;

  @override
  Future<bool> refreshMe() async {
    refreshMeCalls++;
    return true;
  }
}

/// A launcher page: its button pushes the detail screen and records the
/// value the screen pops with. The provider sits above MaterialApp so the
/// pushed route can read the session.
Widget host(FakeApi api, FakeSession session, List<Object?> popped) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped.add(await Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => ApprovalDetailScreen(
                        leaveId: 148, apiBuilder: (_) => api),
                  )));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Finder get approveButton => find.widgetWithText(FilledButton, 'Approve');
Finder get refuseButton => find.widgetWithText(OutlinedButton, 'Refuse');
Finder get sheetRefuseButton => find.widgetWithText(FilledButton, 'Refuse');

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
}

void main() {
  late FakeApi api;
  late FakeSession session;
  late List<Object?> popped;

  setUp(() {
    api = FakeApi(detailJson());
    session = FakeSession();
    popped = [];
  });

  testWidgets('shows the request with everything needed to decide',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Lim Say Puay'), findsOneWidget);
    expect(find.text('Accounts · Standard 40 hours/week'), findsOneWidget);
    expect(find.text('Annual Leave'), findsOneWidget);
    expect(find.text('Tue 6 Oct – Wed 7 Oct'), findsOneWidget);
    expect(find.text('2 days (16h)'), findsOneWidget);
    expect(find.text('10 days left of 14'), findsOneWidget);
    expect(find.text('Family trip'), findsOneWidget);
    expect(find.text('Manager approval'), findsOneWidget);
    expect(find.text('Christine Ng'), findsOneWidget);
    expect(find.text('HR approval'), findsOneWidget);
    expect(find.text('Time Off Officers'), findsOneWidget);
    expect(approveButton, findsOneWidget);
    expect(refuseButton, findsOneWidget);
    expect(api.calls, ['get:148']);
  });

  testWidgets('Approve sends the state seen, toasts, pops and refreshes /me',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(api.calls, ['get:148', 'approve:148:confirm']);
    expect(find.text('Approved · now waiting for HR'), findsOneWidget);
    expect(popped, [true]);
    expect(find.byType(ApprovalDetailScreen), findsNothing);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('a final approval toasts "Approved"', (tester) async {
    api.approveResult = 'validate';
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(find.text('Approved'), findsOneWidget);
    expect(popped, [true]);
  });

  testWidgets('no buttons when the user cannot act', (tester) async {
    api.detail = detailJson(canApprove: false, canRefuse: false);
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(find.text('Lim Say Puay'), findsOneWidget);
    expect(approveButton, findsNothing);
    expect(refuseButton, findsNothing);
  });

  testWidgets('only Refuse when the user may refuse but not approve',
      (tester) async {
    api.detail = detailJson(state: 'validate1', canApprove: false);
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(approveButton, findsNothing);
    expect(refuseButton, findsOneWidget);
  });

  testWidgets('no buttons once the state is final, whatever the flags say',
      (tester) async {
    api.detail = detailJson(state: 'validate');
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(approveButton, findsNothing);
    expect(refuseButton, findsNothing);
  });

  testWidgets('both buttons are locked while Approve is in flight',
      (tester) async {
    api.approveGate = Completer<String>();
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, approveButton);
    await tester.pump();

    expect(tester.widget<FilledButton>(approveButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(refuseButton).onPressed, isNull);
    expect(popped, isEmpty);

    api.approveGate!.complete('validate');
    await tester.pumpAndSettle();
    expect(popped, [true]);
  });

  testWidgets('state_changed says who decided, reloads and hides the buttons',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    api.approveError = ApiException('state_changed',
        data: {'state': 'validate', 'decided_by': 'Teoh Yit Ngoh'});
    api.detail = detailJson(state: 'validate', canApprove: false, canRefuse: false);
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(find.text('Already approved by Teoh Yit Ngoh'), findsOneWidget);
    expect(api.calls, ['get:148', 'approve:148:confirm', 'get:148']);
    expect(find.byType(ApprovalDetailScreen), findsOneWidget);
    expect(approveButton, findsNothing);
    expect(refuseButton, findsNothing);
    expect(popped, isEmpty);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('not_allowed explains, reloads and hides the buttons',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    api.approveError = ApiException('not_allowed');
    api.detail = detailJson(canApprove: false, canRefuse: false);
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(find.text("You can't approve this request."), findsOneWidget);
    expect(api.calls, ['get:148', 'approve:148:confirm', 'get:148']);
    expect(approveButton, findsNothing);
    expect(popped, isEmpty);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('a request that is gone goes back to the list with a message',
      (tester) async {
    api.getError = ApiException('not_found');
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(find.text('This request no longer exists.'), findsOneWidget);
    expect(find.byType(ApprovalDetailScreen), findsNothing);
    expect(popped, [true]);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('not_found on Approve also goes back to the list',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    api.approveError = ApiException('not_found');
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(find.text('This request no longer exists.'), findsOneWidget);
    expect(popped, [true]);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('an Odoo validation message is shown in a dialog; nothing changes',
      (tester) async {
    const odoo = 'You cannot approve a time off that starts in a locked period.';
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    api.approveError = ApiException(odoo);
    await tapVisible(tester, approveButton);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(odoo), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(approveButton, findsOneWidget);
    expect(tester.widget<FilledButton>(approveButton).onPressed, isNotNull);
    expect(api.calls, ['get:148', 'approve:148:confirm']);
    expect(popped, isEmpty);
  });

  testWidgets('Refuse goes through the reason sheet', (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, refuseButton);
    await tester.pumpAndSettle();

    expect(find.text('Refuse this request'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Coverage issue');
    await tester.pump();
    await tester.tap(sheetRefuseButton);
    await tester.pumpAndSettle();

    expect(api.calls, ['get:148', 'refuse:148:confirm:Coverage issue']);
    expect(find.text('Refused'), findsOneWidget);
    expect(popped, [true]);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('cancelling the sheet refuses nothing', (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, refuseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.calls, ['get:148']);
    expect(find.byType(ApprovalDetailScreen), findsOneWidget);
    expect(popped, isEmpty);
  });

  testWidgets('reason_required from the server is shown under the field',
      (tester) async {
    api.refuseError =
        ApiException('reason_required', data: {'min': 3, 'max': 500});
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    await tapVisible(tester, refuseButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(sheetRefuseButton);
    await tester.pumpAndSettle();

    expect(find.text('Write a reason of 3 to 500 characters.'), findsOneWidget);
    expect(find.text('Refuse this request'), findsOneWidget);
    expect(popped, isEmpty);
  });

  testWidgets('state_changed on Refuse closes the sheet and reloads',
      (tester) async {
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);
    api.refuseError = ApiException('state_changed',
        data: {'state': 'refuse', 'decided_by': 'Teoh Yit Ngoh'});
    api.detail = detailJson(state: 'refuse', canApprove: false, canRefuse: false);
    await tapVisible(tester, refuseButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Coverage issue');
    await tester.pump();
    await tester.tap(sheetRefuseButton);
    await tester.pumpAndSettle();

    expect(find.text('Refuse this request'), findsNothing);
    expect(find.text('Already refused'), findsOneWidget);
    expect(refuseButton, findsNothing);
    expect(popped, isEmpty);
    expect(session.refreshMeCalls, 1);
  });

  testWidgets('attachments are listed and a refused download is explained',
      (tester) async {
    api.detail = detailJson(attachments: [
      {'id': 9, 'name': 'mc.pdf', 'mimetype': 'application/pdf', 'file_size': 2048}
    ]);
    api.attachmentError = ApiException('not_owner');
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    final row = find.text('mc.pdf · 2KB');
    expect(row, findsOneWidget);
    await tapVisible(tester, row);
    await tester.pumpAndSettle();

    expect(api.calls, contains('attachment:9'));
    expect(
        find.text("Could not open file: You don't have access to this file."),
        findsOneWidget);
  });

  testWidgets('a failed load shows the error state; Retry reloads',
      (tester) async {
    api.getError = ApiException('server_error');
    await tester.pumpWidget(host(api, session, popped));
    await open(tester);

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(
        find.text('Something went wrong on our end. Please try again in a moment.'),
        findsOneWidget);

    api.getError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsNothing);
    expect(find.text('Lim Say Puay'), findsOneWidget);
  });
}
