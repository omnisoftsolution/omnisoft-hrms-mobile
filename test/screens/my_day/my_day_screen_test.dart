import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/day_timeline.dart';
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
  List<ExpenseRecord> expenses = [];

  @override
  Future<MyDay> fetchMyDay() async {
    final i = calls < script.length ? calls : script.length - 1;
    calls++;
    final result = script[i];
    if (result is MyDay) return result;
    throw result;
  }

  @override
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async =>
      ExpenseListPage(records: expenses, hasMore: false);
}

class _Calls {
  final leave = <int>[];
  final expense = <int>[];
  int sessionRefreshes = 0;
}

Widget _host(_FakeApi api, {Key? key, _Calls? calls}) =>
    ChangeNotifierProvider<SessionService>(
      create: (_) => SessionService(),
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
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Attendance is recorded at the kiosk.'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Shift ends'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('3 leave requests to approve'), findsOneWidget);
    expect(find.text(_banner), findsNothing);
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
    await tester.drag(find.byType(DayTimeline), const Offset(0, 800));
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
}
