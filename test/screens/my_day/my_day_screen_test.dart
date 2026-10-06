import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/my_day_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../../fixtures/my_day_fixture.dart';

const _banner = "Couldn't refresh. Pull down to try again.";

/// Scriptable API: each fetchMyDay() call pops the next scripted result
/// (a MyDay, or an Object to throw); the last one repeats.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.script) : super(baseUrl: '', db: '', token: '');

  final List<Object> script;
  int calls = 0;
  int expenseCalls = 0;
  List<ExpenseRecord> expenses = [];

  /// When set, fetchMyDay / getExpenseList wait for it before answering.
  Completer<void>? fetchGate;
  Completer<void>? expenseGate;

  @override
  Future<MyDay> fetchMyDay() async {
    final i = calls < script.length ? calls : script.length - 1;
    calls++;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    final result = script[i];
    if (result is MyDay) return result;
    throw result;
  }

  @override
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async {
    expenseCalls++;
    final gate = expenseGate;
    if (gate != null) await gate.future;
    return ExpenseListPage(records: expenses, hasMore: false);
  }
}

class _Calls {
  final leave = <int>[];
  final expense = <int>[];
  int sessionRefreshes = 0;
}

Widget _host(
  _FakeApi api, {
  Key? key,
  _Calls? calls,
  SessionService? session,
}) => ChangeNotifierProvider<SessionService>(
  create: (_) => session ?? SessionService(),
  child: MaterialApp(
    home: MyDayScreen(
      key: key,
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
      onOpenLeave: (id) => calls?.leave.add(id),
      onOpenExpense: (id) => calls?.expense.add(id),
      refreshSession: () async => calls?.sessionRefreshes++,
      destinationBuilder: (item, expense) => Scaffold(
        appBar: AppBar(),
        body: Text('DEST ${item.kind} ${expense?.id ?? '-'}'),
      ),
    ),
  ),
);

/// Tall enough that every row of the screen is built.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('loads once and shows the card, the timeline and For you', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.byKey(const ValueKey('status-tile')), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Shift ends'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('3 leave requests to approve'), findsOneWidget);
    expect(find.text(_banner), findsNothing);
  });

  testWidgets('sections in order: tile, week, timeline, for you', (
    tester,
  ) async {
    _tallScreen(tester);
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()])));
    await tester.pumpAndSettle();
    final tile = tester.getTopLeft(find.byKey(const ValueKey('status-tile')));
    final week = tester.getTopLeft(find.text('This week'));
    final timeline = tester.getTopLeft(find.text('Timeline'));
    final forYou = tester.getTopLeft(find.text('For you'));
    expect(
      tile.dy < week.dy && week.dy < timeline.dy && timeline.dy < forYou.dy,
      isTrue,
    );
  });

  testWidgets('missing day: red For-you row opens the kiosk sheet', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', missing: true, punches: []);
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('for-you-missing')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('for-you-missing')));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsOneWidget);
  });

  testWidgets('leave day: off card replaces the timeline', (tester) async {
    _tallScreen(tester);
    final day = sampleMyDay(
      state: 'not_in',
      withShift: false,
      punches: [],
      off: {
        'kind': 'leave',
        'name': 'Annual leave',
        'date_from': '2026-10-06',
        'date_to': '2026-10-07',
        'back_on': '2026-10-08',
      },
    );
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('Annual leave'), findsOneWidget);
    expect(find.text('From 6 Oct to 7 Oct'), findsOneWidget);
    expect(find.text('Next shift 6 Oct · 08:00 – 17:00'), findsOneWidget);
  });

  testWidgets('empty day: both empty texts', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([
      sampleMyDay(state: 'not_in', withShift: false, punches: [], forYou: []),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('No attendance recorded today.'), findsOneWidget);
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
  });

  testWidgets('first load fails: centred message and Retry', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([ApiException('network_error'), sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text(_banner), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(find.text('Checked in'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the last day under a banner', (
    tester,
  ) async {
    _tallScreen(tester);
    final key = GlobalKey<MyDayScreenState>();
    final api = _FakeApi([
      sampleMyDay(),
      ApiException('timeout'),
      sampleMyDay(state: 'on_break'),
    ]);
    await tester.pumpWidget(_host(api, key: key));
    await tester.pumpAndSettle();

    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(_banner), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);

    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(_banner), findsNothing);
    expect(find.text('On break'), findsOneWidget);
  });

  testWidgets('pull down refreshes', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Timeline'), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('leave_approvals row opens approvals; back refreshes both', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 leave requests to approve'));
    await tester.pumpAndSettle();
    expect(find.text('DEST leave_approvals -'), findsOneWidget);
    expect(api.calls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(calls.sessionRefreshes, 1);
    expect(api.calls, 2);
  });

  testWidgets('my_leave row hands the id to onOpenLeave', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()]), calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual leave · 12 Oct – 13 Oct'));
    await tester.pumpAndSettle();
    expect(calls.leave, [412]);
    expect(find.textContaining('DEST'), findsNothing);
  });

  testWidgets('my_expense row opens the expense detail; back refreshes', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()])
      ..expenses = [
        ExpenseRecord.fromJson({
          'id': 88,
          'name': 'Transport',
          'state': 'submitted',
        }),
      ];
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(find.text('DEST my_expense 88'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(calls.sessionRefreshes, 0);
    expect(calls.expense, isEmpty);
  });

  testWidgets('my_expense row falls back to the Expenses tab', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()]), calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(calls.expense, [88]);
    expect(find.textContaining('DEST'), findsNothing);
  });

  testWidgets('payslip row opens the payslip screen; back refreshes', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(find.text('DEST payslip -'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('rows without an id (0) do nothing', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([
      sampleMyDay(
        forYou: [
          {'kind': 'my_leave', 'type': 'Sick leave', 'state': 'confirm'},
          {'kind': 'my_expense', 'name': 'Taxi', 'state': 'submitted'},
        ],
      ),
    ]);
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sick leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taxi'));
    await tester.pumpAndSettle();
    expect(calls.leave, isEmpty);
    expect(calls.expense, isEmpty);
    expect(find.textContaining('DEST'), findsNothing);
    expect(api.calls, 1);
  });

  testWidgets('a refresh during a push is shared with the return refresh', (
    tester,
  ) async {
    _tallScreen(tester);
    final key = GlobalKey<MyDayScreenState>();
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api, key: key));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    api.fetchGate = Completer<void>();
    final tabTap = key.currentState!.refresh(); // e.g. a Home tab tap
    await tester.pageBack(); // the return-from-push refresh
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 2);
    api.fetchGate!.complete();
    await tabTap;
    await tester.pumpAndSettle();
    expect(api.calls, 2);

    // Once finished, a new refresh issues a new request.
    api.fetchGate = null;
    await key.currentState!.refresh();
    expect(api.calls, 3);
  });

  testWidgets('app resume refreshes once', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets(
    'kiosk_only false re-pulls /me when the session still says true',
    (tester) async {
      _tallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({});
      final session = SessionService();
      await tester.runAsync(
        () => session.saveLoginResponse({
          'success': true,
          'access_token': 'A',
          'expires_at': '2026-10-13 10:00:00',
          'auth_source': 'omni',
          'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
          'employee': {'id': 6, 'name': 'A', 'attendance_kiosk_only': true},
        }),
      );
      expect(session.attendanceKioskOnly, isTrue);

      final calls = _Calls();
      final api = _FakeApi([
        sampleMyDay(),
        sampleMyDay(kioskOnly: false),
        sampleMyDay(kioskOnly: false),
      ]);
      final key = GlobalKey<MyDayScreenState>();
      await tester.pumpWidget(
        _host(api, key: key, calls: calls, session: session),
      );
      await tester.pumpAndSettle();
      expect(calls.sessionRefreshes, 0);

      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(calls.sessionRefreshes, 1);
    },
  );

  testWidgets('a kiosk_only answer does not re-pull /me', (tester) async {
    _tallScreen(tester);
    FlutterSecureStorage.setMockInitialValues({});
    final session = SessionService();
    await tester.runAsync(
      () => session.saveLoginResponse({
        'success': true,
        'access_token': 'A',
        'expires_at': '2026-10-13 10:00:00',
        'auth_source': 'omni',
        'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
        'employee': {'id': 6, 'name': 'A', 'attendance_kiosk_only': true},
      }),
    );
    expect(session.attendanceKioskOnly, isTrue);

    final calls = _Calls();
    final key = GlobalKey<MyDayScreenState>();
    await tester.pumpWidget(
      _host(
        _FakeApi([sampleMyDay()]), // the server also says kiosk_only: true
        key: key,
        calls: calls,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(calls.sessionRefreshes, 0);
  });

  testWidgets('rows stay tappable while the return refresh is pending', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(find.text('DEST payslip -'), findsOneWidget);

    // Back from the pushed screen, with the follow-up refresh still pending.
    api.fetchGate = Completer<void>();
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 2);
    expect(find.textContaining('DEST'), findsNothing);

    // Another row is not ignored: it pushes its screen.
    await tester.tap(find.text('3 leave requests to approve'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEST leave_approvals -'), findsOneWidget);

    api.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('DEST leave_approvals -'), findsOneWidget);
  });

  testWidgets('a second tap while the expense lookup runs is ignored', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()])
      ..expenses = [
        ExpenseRecord.fromJson({
          'id': 88,
          'name': 'Transport',
          'state': 'submitted',
        }),
      ]
      ..expenseGate = Completer<void>();
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pump();
    await tester.tap(find.text('Transport'));
    await tester.pump();
    api.expenseGate!.complete();
    await tester.pumpAndSettle();
    expect(api.expenseCalls, 1);
    expect(find.text('DEST my_expense 88'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('DEST'), findsNothing);
    expect(find.text('For you'), findsOneWidget);
    expect(api.calls, 2);

    // The guard is released afterwards: the row opens again.
    api.expenseGate = null;
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(find.text('DEST my_expense 88'), findsOneWidget);
    expect(api.expenseCalls, 2);
  });
}
