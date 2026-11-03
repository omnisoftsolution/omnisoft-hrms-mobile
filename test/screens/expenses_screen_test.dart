import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/screens/expenses/expense_detail_screen.dart';
import 'package:omni_hr/screens/expenses/expenses_screen.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:provider/provider.dart';

class _Session extends SessionService {
  @override
  bool get featureExpenses => true;

  @override
  bool get isLoggedIn => true;
}

class _Api extends OmniMobileApi {
  _Api() : super(baseUrl: 'http://test', db: 'test', token: 't');

  int calls = 0;

  @override
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async {
    calls++;
    return ExpenseListPage(
      records: [
        ExpenseRecord(
          id: 11,
          name: 'Clean September 2026',
          totalAmount: 150,
          state: 'paid',
        ),
        ExpenseRecord(
          id: 12,
          name: 'Season Parking Willy Oct-Dec 2026',
          totalAmount: 719.4,
          state: 'posted',
        ),
        ExpenseRecord(
          id: 13,
          name: 'Taxi to client',
          totalAmount: 32.5,
          state: 'submitted',
        ),
      ],
      hasMore: false,
    );
  }
}

Widget _host(_Api api) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SessionService>(create: (_) => _Session()),
    ChangeNotifierProvider<NotificationService>(
      create: (_) => NotificationService(),
    ),
  ],
  child: MaterialApp(home: ExpensesScreen(apiBuilder: (_) => api)),
);

void _sideways(WidgetTester tester) {
  tester.view.physicalSize = const Size(951, 669);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _inPane(String side, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('duo-pane-$side')), matching: f);

int _openId(WidgetTester tester) => tester
    .widget<ExpenseDetailScreen>(
      _inPane('right', find.byType(ExpenseDetailScreen)),
    )
    .record
    .id;

void main() {
  testWidgets('a phone lists the expenses and a tap opens a page', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.byType(ExpenseDetailScreen), findsNothing);
    expect(find.text('NEW EXPENSE'), findsOneWidget);
    await tester.tap(find.text('Season Parking Willy Oct-Dec 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseDetailScreen), findsOneWidget);
  });

  group('Duo open sideways (v4, idea A)', () {
    testWidgets('the list left of the fold, the first claim open right of '
        'it', (tester) async {
      _sideways(tester);
      await tester.pumpWidget(_host(_Api()));
      await tester.pumpAndSettle();
      expect(
        _inPane('left', find.text('Clean September 2026')),
        findsOneWidget,
      );
      expect(_openId(tester), 11);
      // New expense belongs to the list, not on top of the open claim.
      expect(_inPane('left', find.text('NEW EXPENSE')), findsOneWidget);
      expect(find.text('NEW EXPENSE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap opens that claim on the right, no page pushed', (
      tester,
    ) async {
      _sideways(tester);
      await tester.pumpWidget(_host(_Api()));
      await tester.pumpAndSettle();
      await tester.tap(
        _inPane('left', find.text('Season Parking Willy Oct-Dec 2026')),
      );
      await tester.pumpAndSettle();
      expect(_openId(tester), 12);
      expect(find.byType(ExpenseDetailScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expense-tile-12-open')),
        findsOneWidget,
      );
    });

    testWidgets('the open claim has no Expense bar; Edit and Delete sit in '
        'the pane', (tester) async {
      _sideways(tester);
      await tester.pumpWidget(_host(_Api()));
      await tester.pumpAndSettle();
      await tester.tap(_inPane('left', find.text('Taxi to client')));
      await tester.pumpAndSettle();
      expect(_openId(tester), 13);
      expect(_inPane('right', find.byType(AppBar)), findsNothing);
      expect(_inPane('right', find.text('Expense')), findsNothing);
      expect(_inPane('right', find.byTooltip('Edit')), findsOneWidget);
      expect(_inPane('right', find.byTooltip('Delete')), findsOneWidget);
    });

    testWidgets('a phone page keeps its Expense bar', (tester) async {
      await tester.pumpWidget(_host(_Api()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taxi to client'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Expense'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Edit'), findsOneWidget);
    });
  });
}
