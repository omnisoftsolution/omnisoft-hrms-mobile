import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/approval_detail.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/screens/approvals/approval_detail_screen.dart';
import 'package:omni_hr/screens/approvals/approvals_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

ApprovalItem pendingItem(
  int id, {
  bool mine = true,
  String step = 'manager_approval',
  WaitingFor? waitingFor,
  String? name,
}) => ApprovalItem(
  id: id,
  employeeName: name ?? 'Emp $id',
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
  waitingFor: waitingFor,
);

ApprovalItem recentItem(
  int id,
  String outcome, {
  String reason = '',
  String first = '',
  String second = '',
}) => ApprovalItem(
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

Widget host(FakeApi api, {int initialSegment = 0}) =>
    ChangeNotifierProvider<SessionService>.value(
      value: FakeSession(),
      child: MaterialApp(
        home: ApprovalsScreen(
          apiBuilder: (_) => api,
          initialSegment: initialSegment,
        ),
      ),
    );

void main() {
  testWidgets('Pending lists the requests with their step chips', (
    tester,
  ) async {
    final api = FakeApi(
      pending: [
        pendingItem(1),
        pendingItem(2, mine: false),
        pendingItem(3, mine: false, step: 'hr_approval'),
      ],
    );
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

  testWidgets('Recent shows the outcome, who approved and the refusal reason', (
    tester,
  ) async {
    final api = FakeApi(
      recent: [
        recentItem(
          4,
          'approved',
          first: 'Christine Ng',
          second: 'Teoh Yit Ngoh',
        ),
        recentItem(
          5,
          'refused',
          reason: 'Month-end closing',
          second: 'Christine Ng',
        ),
        recentItem(6, 'waiting_hr', first: 'Christine Ng'),
      ],
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Refused'), findsOneWidget);
    expect(find.text('Waiting for HR'), findsOneWidget);
    expect(
      find.text('Approved by Christine Ng and Teoh Yit Ngoh'),
      findsOneWidget,
    );
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

  testWidgets('initialSegment 1 opens on Recent', (tester) async {
    await tester.pumpWidget(host(FakeApi(), initialSegment: 1));
    await tester.pumpAndSettle();
    expect(find.text('No decisions in the last 30 days'), findsOneWidget);
    expect(find.text('Nothing waiting for you'), findsNothing);
  });

  testWidgets(
    'tapping a row opens the request; coming back reloads the lists',
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
    },
  );

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

  testWidgets('P1: a reload after the first load keeps the lists (no '
      'spinner); a failed one keeps them and says so', (tester) async {
    final api = FakeApi(pending: [pendingItem(1)]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    expect(find.text('Emp 1'), findsOneWidget);

    api.pending = [pendingItem(1), pendingItem(7)];
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The list stays while the reload runs (only the pull indicator).
    expect(find.text('Emp 1'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Emp 7'), findsOneWidget);

    api.listError = ApiException('network_error');
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(find.text('Emp 1'), findsOneWidget);
    expect(find.text('Emp 7'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Pending splits into Waiting for you and You can also approve', (
    tester,
  ) async {
    final api = FakeApi(
      pending: [pendingItem(1), pendingItem(2, mine: false), pendingItem(3)],
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(find.text('Pending · 3'), findsOneWidget);
    expect(find.text('Waiting for you'), findsOneWidget);
    expect(find.text('You can also approve'), findsOneWidget);
    expect(find.text('Nothing waiting for you.'), findsNothing);
    // Mine first (server order kept), then the section, then the others.
    final y1 = tester.getTopLeft(find.text('Emp 1')).dy;
    final y3 = tester.getTopLeft(find.text('Emp 3')).dy;
    final yOthers = tester.getTopLeft(find.text('You can also approve')).dy;
    final y2 = tester.getTopLeft(find.text('Emp 2')).dy;
    expect(y1 < y3, isTrue);
    expect(y3 < yOthers, isTrue);
    expect(yOthers < y2, isTrue);
  });

  testWidgets('nothing assigned to me: the first section says so', (
    tester,
  ) async {
    final api = FakeApi(pending: [pendingItem(2, mine: false)]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for you'), findsOneWidget);
    expect(find.text('Nothing waiting for you.'), findsOneWidget);
    expect(find.text('You can also approve'), findsOneWidget);
    expect(find.text('Emp 2'), findsOneWidget);
  });

  testWidgets('only my requests: no second section', (tester) async {
    final api = FakeApi(pending: [pendingItem(1)]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for you'), findsOneWidget);
    expect(find.text('Nothing waiting for you.'), findsNothing);
    expect(find.text('You can also approve'), findsNothing);
  });

  testWidgets('an empty Pending keeps the single empty state', (tester) async {
    await tester.pumpWidget(host(FakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing waiting for you'), findsOneWidget);
    expect(find.text('Waiting for you'), findsNothing);
    expect(find.text('You can also approve'), findsNothing);
  });

  testWidgets('chips follow waiting_for', (tester) async {
    final api = FakeApi(
      pending: [
        pendingItem(
          1,
          waitingFor: const WaitingFor(
            role: 'manager',
            names: ['Herianto Ramli'],
            you: true,
          ),
        ),
        pendingItem(
          2,
          mine: false,
          waitingFor: const WaitingFor(role: 'manager', names: ['Kelvin Tan']),
        ),
        pendingItem(
          3,
          mine: false,
          step: 'hr_approval',
          waitingFor: const WaitingFor(role: 'hr'),
        ),
      ],
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(find.text('Your approval'), findsOneWidget);
    expect(find.text('Waiting for Kelvin (manager)'), findsOneWidget);
    expect(find.text('Waiting for HR'), findsOneWidget);
    expect(find.text('Manager approval'), findsNothing);
    expect(find.text('HR approval'), findsNothing);
  });

  testWidgets('Recent has no sections', (tester) async {
    final api = FakeApi(
      pending: [pendingItem(1)],
      recent: [recentItem(4, 'approved')],
    );
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('Emp 4'), findsOneWidget);
    expect(find.text('Waiting for you'), findsNothing);
    expect(find.text('You can also approve'), findsNothing);
  });

  testWidgets('a failed load (old connector, no network) shows Retry', (
    tester,
  ) async {
    final api = FakeApi(pending: [pendingItem(1)])
      ..listError = ApiException('server_error');
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(
      find.text(
        'Something went wrong on our end. Please try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);

    api.listError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsNothing);
    expect(find.text('Emp 1'), findsOneWidget);
  });

  testWidgets('a short chip stays on the name line where it fits', (
    tester,
  ) async {
    final api = FakeApi(pending: [pendingItem(1, name: 'Budi Santoso')]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();

    final name = tester.getRect(find.text('Budi Santoso'));
    final chip = tester.getRect(find.text('Your approval'));
    expect(chip.center.dy, closeTo(name.center.dy, 4));
    expect(chip.left, greaterThan(name.right));
  });

  testWidgets(
    'narrow phone, large text (360 dp, 1.3x): long waiting_for chips never '
    'squeeze the employee name or overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeApi(
        pending: [
          pendingItem(
            1,
            name: 'Budi Santoso',
            waitingFor: const WaitingFor(
              role: 'manager',
              names: ['Herianto Ramli'],
              you: true,
            ),
          ),
          pendingItem(
            2,
            mine: false,
            name: 'Siti Rahayu',
            waitingFor: const WaitingFor(
              role: 'manager',
              names: ['Kelvin Tan'],
            ),
          ),
          pendingItem(
            3,
            mine: false,
            name: 'Agus Salim',
            waitingFor: const WaitingFor(
              role: 'manager',
              names: ['Christopher Lee', 'Ann Lim'],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionService>.value(
          value: FakeSession(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: ApprovalsScreen(apiBuilder: (_) => api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A RenderFlex overflow would be reported here.
      expect(tester.takeException(), isNull);
      for (final name in ['Budi Santoso', 'Siti Rahayu', 'Agus Salim']) {
        final p = tester.renderObject<RenderParagraph>(find.text(name));
        expect(p.didExceedMaxLines, isFalse, reason: '$name is cut');
        expect(tester.getSize(find.text(name)).width, greaterThan(100));
      }
      expect(find.text('Your approval'), findsOneWidget);
      expect(find.text('Waiting for Kelvin (manager)'), findsOneWidget);
      expect(find.text('Waiting for Christopher +1 (manager)'), findsOneWidget);
    },
  );
}
