import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/home/my_day/declaration_sheet.dart';
import 'package:omni_hr/screens/notifications/notifications_screen.dart';
import 'package:omni_hr/services/notification_service.dart';

/// A notification list the test sets directly: no session, no polling.
class _FakeNotifications extends NotificationService {
  _FakeNotifications(this._list);

  final List<NotificationRecord> _list;
  final List<int> marked = [];
  int refreshes = 0;

  @override
  List<NotificationRecord> get items => _list;

  @override
  int get unreadCount => _list.where((n) => !n.read).length;

  @override
  bool get loading => false;

  @override
  String? get lastError => null;

  @override
  Future<void> refreshList() async => refreshes++;

  @override
  Future<void> markRead(int id) async => marked.add(id);
}

const _question =
    'You checked in at 08:00 and out at 12:00 on 2026-10-06. Which is right?';

NotificationRecord _query({bool answered = false}) => NotificationRecord(
  id: 21,
  kind: 'attendance_query',
  title: 'HR has a question about 2026-10-06',
  body: _question,
  answered: answered,
  payload: const {
    'day_id': 5,
    'date': '2026-10-06',
    'question': _question,
    'options': [
      {'code': 'swap', 'label': 'My supervisor moved me to another shift'},
      {'code': 'early', 'label': 'Left early, personal reason'},
    ],
  },
);

const _declared =
    'You said you started at 08:00 on Thu 8 Oct (you tapped 10:44). '
    'Is that right?';

/// Connector 2.55.0: HR asks about the employee's own declaration.
NotificationRecord _declaredQuery() => NotificationRecord(
  id: 22,
  kind: 'attendance_query',
  title: 'HR has a question about Thu 8 Oct',
  body: _declared,
  payload: const {
    'day_id': 6,
    'date': '2026-10-08',
    'question': _declared,
    'suggested_time': '2026-10-08 00:00:00',
    'options': [
      {
        'code': 'declared_ok',
        'label': "Yes, that's right",
        'needs_time': false,
      },
      {
        'code': 'declared_change',
        'label': 'No, the right time is',
        'needs_time': true,
      },
      {'code': 'other', 'label': 'Other', 'needs_time': false},
    ],
  },
);

NotificationRecord _applied() => NotificationRecord(
  id: 23,
  kind: 'attendance_declaration_applied',
  title: 'HR updated your attendance',
  body: 'Your check-in for Tue 6 Oct was set to 08:00 from your note.',
  payload: const {
    'day_id': 5,
    'date': '2026-10-06',
    'field': 'check_in',
    'time': '2026-10-06 01:00:00',
  },
);

void main() {
  late List<(int, String, String)> answers;
  late List<DateTime?> times;
  late List<String> taps;

  setUp(() {
    answers = [];
    times = [];
    taps = [];
  });

  Widget host(_FakeNotifications svc, {Object? failWith}) =>
      ChangeNotifierProvider<NotificationService>.value(
        value: svc,
        child: MaterialApp(
          home: NotificationsScreen(
            onMyDayTap: () => taps.add('myday'),
            answerReview:
                ({
                  required int notificationId,
                  required String answerCode,
                  required String note,
                  DateTime? time,
                }) async {
                  if (failWith != null) throw failWith;
                  answers.add((notificationId, answerCode, note));
                  times.add(time);
                },
          ),
        ),
      );

  testWidgets(
    'HR question: the sheet answers through review/answer, then marks read',
    (tester) async {
      final svc = _FakeNotifications([_query()]);
      await tester.pumpWidget(host(svc));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HR has a question about 2026-10-06'));
      await tester.pumpAndSettle();
      expect(find.byType(DeclarationSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DeclarationSheet),
          matching: find.text(_question),
        ),
        findsOneWidget,
      );
      expect(svc.marked, isEmpty);
      // APP-4: HR's question is headed as one, not "Forgot something?".
      expect(
        find.descendant(
          of: find.byType(DeclarationSheet),
          matching: find.text('Question from HR'),
        ),
        findsOneWidget,
      );
      expect(find.text('Forgot something?'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('declaration-option-early')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('declaration-note')),
        'doctor',
      );
      await tester.tap(find.byKey(const ValueKey('declaration-send')));
      await tester.pumpAndSettle();
      expect(answers, [(21, 'early', 'doctor')]);
      expect(svc.marked, [21]);
      expect(find.text('Sent to HR'), findsOneWidget);
    },
  );

  testWidgets(
    'HR asks about a declaration: the corrected time goes with the answer',
    (tester) async {
      final svc = _FakeNotifications([_declaredQuery()]);
      await tester.pumpWidget(host(svc));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HR has a question about Thu 8 Oct'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(DeclarationSheet),
          matching: find.text(_declared),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('declaration-option-declared_change')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('declaration-send')));
      await tester.pumpAndSettle();
      expect(answers, [(22, 'declared_change', '')]);
      // The time chip starts on the declared time the server suggested.
      expect(times, [DateTime.utc(2026, 10, 8)]);
      expect(svc.marked, [22]);
    },
  );

  testWidgets('a failed answer shows the error and refreshes the list', (
    tester,
  ) async {
    final svc = _FakeNotifications([_query()]);
    await tester.pumpWidget(host(svc, failWith: Exception('already_answered')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR has a question about 2026-10-06'));
    await tester.pumpAndSettle();
    final before = svc.refreshes;
    await tester.tap(find.byKey(const ValueKey('declaration-option-early')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('declaration-send')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Sent to HR'), findsNothing);
    expect(svc.marked, isEmpty);
    expect(svc.refreshes, before + 1);
  });

  testWidgets('an answered question does not reopen the sheet', (tester) async {
    final svc = _FakeNotifications([_query(answered: true)]);
    await tester.pumpWidget(host(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR has a question about 2026-10-06'));
    await tester.pumpAndSettle();
    expect(find.byType(DeclarationSheet), findsNothing);
    expect(svc.marked, [21]);
    expect(answers, isEmpty);
    // APP-5: the tap says why nothing opens.
    expect(find.text('You already answered this question.'), findsOneWidget);
  });

  testWidgets('an answered question is labelled Answered on its card', (
    tester,
  ) async {
    await tester.pumpWidget(host(_FakeNotifications([_query(answered: true)])));
    await tester.pumpAndSettle();
    expect(find.text('Answered'), findsOneWidget);
  });

  testWidgets('an open question has no Answered label and no snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(host(_FakeNotifications([_query()])));
    await tester.pumpAndSettle();
    expect(find.text('Answered'), findsNothing);
    await tester.tap(find.text('HR has a question about 2026-10-06'));
    await tester.pumpAndSettle();
    expect(find.text('You already answered this question.'), findsNothing);
  });

  testWidgets('"HR updated your attendance" renders and opens My day', (
    tester,
  ) async {
    final svc = _FakeNotifications([_applied()]);
    await tester.pumpWidget(host(svc));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.event_available), findsOneWidget);
    await tester.tap(find.text('HR updated your attendance'));
    await tester.pumpAndSettle();
    expect(svc.marked, [23]);
    expect(taps, ['myday']);
  });

  testWidgets('the HR question has its own icon', (tester) async {
    await tester.pumpWidget(host(_FakeNotifications([_query()])));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  test('NotificationRecord reads answered and the new kinds', () {
    final record = NotificationRecord.fromJson({
      'id': 1,
      'kind': 'attendance_query',
      'title': 't',
      'answered': true,
    });
    expect(record.answered, isTrue);
    expect(record.isAttendanceQuery, isTrue);
    expect(record.isDeclarationApplied, isFalse);
    expect(_applied().isDeclarationApplied, isTrue);
    expect(
      NotificationRecord.fromJson({'id': 2, 'kind': 'system'}).answered,
      isFalse,
    );
  });
}
