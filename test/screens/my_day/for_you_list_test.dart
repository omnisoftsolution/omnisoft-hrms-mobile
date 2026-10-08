import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/attendance_ask.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/for_you_list.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';

import '../../fixtures/my_day_fixture.dart';

Widget _host(List<ForYouItem> items, {void Function(ForYouItem)? onTap}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ForYouList(items: items, onTap: onTap ?? (_) {}),
        ),
      ),
    );

void main() {
  final items = sampleMyDay().forYou;
  final approvals = items[0];
  final leave = items[1];
  final expense = items[2];
  final payslip = items[3];

  group('texts', () {
    test('leave_approvals', () {
      expect(forYouTitle(approvals), '3 leave requests to approve');
      expect(
        forYouTitle(const ForYouItem(kind: 'leave_approvals', count: 1)),
        '1 leave request to approve',
      );
      expect(
        forYouSubtitle(approvals, now: DateTime.utc(2026, 10, 5, 3)),
        'Oldest has waited 2 days',
      );
      expect(
        forYouSubtitle(approvals, now: DateTime.utc(2026, 10, 4, 3)),
        'Oldest has waited 1 day',
      );
      expect(
        forYouSubtitle(approvals, now: DateTime.utc(2026, 10, 3, 9)),
        'Oldest is from today',
      );
    });

    test('my_leave shows the requested dates as sent (LEAVE-2)', () {
      // omnihrdemo hr.leave 17: request 2026-11-04 -> 2026-11-09.
      final item = ForYouItem.fromJson(const {
        'kind': 'my_leave',
        'id': 17,
        'state': 'confirm',
        'type': 'Childcare Leave',
        'date_from': '2026-11-04',
        'date_to': '2026-11-09',
        'approver': '',
        'reason': '',
      });
      expect(forYouTitle(item), 'Childcare Leave · 4 Nov – 9 Nov');
    });

    test('my_leave', () {
      expect(forYouTitle(leave), 'Annual leave · 12 Oct – 13 Oct');
      expect(forYouSubtitle(leave), 'Waiting for Hendra Wijaya');
      ForYouItem withState(
        String state, {
        String approver = 'Hendra Wijaya',
        String reason = '',
      }) => ForYouItem(
        kind: 'my_leave',
        id: 1,
        state: state,
        type: 'Sick leave',
        dateFrom: '2026-10-06',
        dateTo: '2026-10-06',
        approver: approver,
        reason: reason,
      );
      expect(forYouTitle(withState('confirm')), 'Sick leave · 6 Oct');
      expect(
        forYouSubtitle(withState('confirm', approver: '')),
        'Waiting for approval',
      );
      expect(
        forYouSubtitle(withState('validate1')),
        'Waiting for HR',
      );
      expect(
        forYouSubtitle(withState('validate')),
        'Approved by Hendra Wijaya',
      );
      expect(forYouSubtitle(withState('validate', approver: '')), 'Approved');
      expect(
        forYouSubtitle(withState('refuse', reason: 'Not this week')),
        'Refused: Not this week',
      );
      expect(forYouSubtitle(withState('refuse')), 'Refused');
    });

    test('my_expense', () {
      expect(forYouTitle(expense), 'Transport');
      expect(forYouSubtitle(expense), 'Waiting for approval · IDR 350,000');
      ForYouItem withState(String state) => ForYouItem(
        kind: 'my_expense',
        id: 2,
        state: state,
        name: '',
        amount: 12.5,
        currency: 'SGD',
      );
      expect(forYouTitle(withState('approved')), 'Expense');
      expect(forYouSubtitle(withState('approved')), 'Approved · SGD 12.5');
      expect(forYouSubtitle(withState('paid')), 'Approved · SGD 12.5');
      expect(forYouSubtitle(withState('refused')), 'Refused · SGD 12.5');
    });

    test('payslip', () {
      expect(forYouTitle(payslip), 'September 2026 payslip is ready');
      expect(forYouSubtitle(payslip), 'Tap to view');
    });
  });

  testWidgets('one row per item, in order', (tester) async {
    await tester.pumpWidget(_host(items));
    expect(find.byType(ListTile), findsNWidgets(4));
    expect(find.text('3 leave requests to approve'), findsOneWidget);
    expect(find.text('Annual leave · 12 Oct – 13 Oct'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('September 2026 payslip is ready'), findsOneWidget);
    expect(find.byKey(const ValueKey('for-you-my_leave-412')), findsOneWidget);
  });

  testWidgets('tapping a row reports the item', (tester) async {
    final tapped = <ForYouItem>[];
    await tester.pumpWidget(_host(items, onTap: tapped.add));
    await tester.tap(find.text('Transport'));
    expect(tapped.single.kind, 'my_expense');
    expect(tapped.single.id, 88);
  });

  testWidgets('empty list', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('an unknown kind is skipped', (tester) async {
    await tester.pumpWidget(
      _host([const ForYouItem(kind: 'late_mark', id: 7), payslip]),
    );
    expect(find.byType(ListTile), findsOneWidget);
    await tester.pumpWidget(_host([const ForYouItem(kind: 'late_mark')]));
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
  });

  testWidgets('rows carry a tinted icon tile per kind', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForYouList(items: sampleMyDay().forYou, onTap: (_) {}),
        ),
      ),
    );
    Color tileOf(String key) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey('for-you-tile-$key')),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    expect(tileOf('leave_approvals-0'), MyDayColors.brk.tint);
    expect(tileOf('my_leave-412'), MyDayColors.work.tint);
    expect(tileOf('my_expense-88'), MyDayColors.brk.tint);
    expect(tileOf('payslip-51'), MyDayColors.overtime.tint);
  });

  testWidgets('missing prepends a red row that calls onMissingTap', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForYouList(
            items: const [],
            onTap: (_) {},
            missing: true,
            onMissingTap: () => tapped++,
          ),
        ),
      ),
    );
    expect(find.text('No check-in recorded today'), findsOneWidget);
    expect(find.text('Tell HR if you are at work'), findsOneWidget);
    expect(find.text(ForYouList.emptyText), findsNothing);
    await tester.tap(find.byKey(const ValueKey('for-you-missing')));
    expect(tapped, 1);
  });

  const yesterday = ForYouItem(
    kind: 'yesterday_incomplete',
    date: '2026-10-06',
    attendanceId: 798,
    title: 'Yesterday looks incomplete',
    body: 'No check-out was recorded for Tue 6 Oct. Tell HR when you left.',
    options: [AskOption(code: 'left_at', label: 'I left at', needsTime: true)],
  );

  test('yesterday_incomplete texts', () {
    expect(forYouTitle(yesterday), 'Yesterday looks incomplete');
    expect(
      forYouSubtitle(yesterday),
      'No check-out was recorded for Tue 6 Oct. Tell HR when you left.',
    );
    expect(
      forYouTitle(const ForYouItem(kind: 'yesterday_incomplete')),
      'Yesterday looks incomplete',
    );
  });

  testWidgets('the yesterday card: amber, first, Tell HR calls onYesterday', (
    tester,
  ) async {
    final told = <ForYouItem>[];
    final tapped = <ForYouItem>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ForYouList(
              items: [yesterday, payslip],
              onTap: tapped.add,
              onYesterday: told.add,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(YesterdayCard), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.text('Yesterday looks incomplete'), findsOneWidget);
    expect(find.text('Tell HR'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(YesterdayCard)).dy,
      lessThan(tester.getTopLeft(find.byType(ListTile)).dy),
    );
    await tester.tap(find.byKey(const ValueKey('for-you-yesterday-tell')));
    expect(told, [yesterday]);
    expect(tapped, isEmpty);
  });
}
