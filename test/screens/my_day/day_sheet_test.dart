import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/day_sheet.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';

MyDayWeekDay _day(Map<String, dynamic> json) => MyDayWeekDay.fromJson(json);

void main() {
  test('dayTitle is the long English date', () {
    expect(dayTitle('2026-10-05'), 'Monday 5 October');
    expect(dayTitle('2026-10-08'), 'Thursday 8 October');
    expect(dayTitle('nonsense'), '');
  });

  group('daySummaryOf', () {
    test('worked, on time', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'ok',
          'shift': '08:00 – 17:00',
          'first_in': '08:02',
          'last_out': '17:05',
          'worked_minutes': 498,
          'late_minutes': 0,
          'early_minutes': 0,
          'place': 'Front desk',
        }),
      );
      expect(s.title, 'Monday 5 October');
      expect(s.head, 'Worked 8h 18m · on time');
      expect(s.sub, '08:02 – 17:05 · Front desk');
      expect(s.tone, MyDayColors.work);
      expect(s.icon, Icons.check_circle_outline);
    });

    test('worked, late', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'late',
          'first_in': '08:17',
          'last_out': '17:05',
          'worked_minutes': 483,
          'late_minutes': 17,
        }),
      );
      expect(s.head, 'Worked 8h 03m · 17 min late');
      expect(s.sub, '08:17 – 17:05');
      expect(s.tone, MyDayColors.late);
      expect(s.icon, Icons.alarm_outlined);
    });

    test('worked, left early', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'early_leave',
          'first_in': '08:00',
          'last_out': '16:10',
          'worked_minutes': 445,
          'early_minutes': 50,
        }),
      );
      expect(s.head, 'Worked 7h 25m · left 50 min early');
      expect(s.tone, MyDayColors.late);
      expect(s.icon, Icons.logout_outlined);
    });

    test('a late verdict without minutes falls back to hours only', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'late',
          'first_in': '08:17',
          'last_out': '17:05',
          'worked_minutes': 483,
        }),
      );
      expect(s.head, 'Worked 8h 03m');
      expect(s.tone, MyDayColors.work);
    });

    test('other verdicts show the hours only', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'no_checkout',
          'first_in': '08:00',
          'worked_minutes': 0,
        }),
      );
      expect(s.head, 'Worked');
      expect(s.sub, 'From 08:00');
    });

    test('an open last session reads From', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-05',
          'kind': 'worked',
          'verdict': 'ok',
          'first_in': '08:00',
          'last_out': '',
          'worked_minutes': 240,
        }),
      );
      expect(s.head, 'Worked 4h 00m · on time');
      expect(s.sub, 'From 08:00');
    });

    test('a 2.52.0 worked entry shows the kind only', () {
      final s = daySummaryOf(
        _day({'date': '2026-10-05', 'kind': 'worked', 'verdict': 'ok'}),
      );
      expect(s.head, 'Worked · on time');
      expect(s.sub, '');
    });

    test('absent', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-07',
          'kind': 'absent',
          'shift': '08:00 – 17:00',
        }),
      );
      expect(s.head, 'No check-in recorded');
      expect(s.sub, 'Shift 08:00 – 17:00');
      expect(s.tone, MyDayColors.missing);
      expect(s.icon, Icons.warning_amber_outlined);
      expect(
        daySummaryOf(_day({'date': '2026-10-07', 'kind': 'absent'})).sub,
        '',
      );
    });

    test('public holiday', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-08',
          'kind': 'public_holiday',
          'name': 'Omni test holiday',
        }),
      );
      expect(s.title, 'Thursday 8 October');
      expect(s.head, 'Public holiday');
      expect(s.sub, 'Omni test holiday');
      expect(s.tone, MyDayColors.holiday);
      expect(s.icon, Icons.star_outline);
    });

    test('leave, with and without an approver', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-09',
          'kind': 'leave',
          'name': 'Annual Leave',
          'approver': 'Sophia Johnson',
        }),
      );
      expect(s.head, 'Annual Leave');
      expect(s.sub, 'Approved by Sophia Johnson');
      expect(s.tone, MyDayColors.leave);
      expect(s.icon, Icons.event_available_outlined);
      final bare = daySummaryOf(_day({'date': '2026-10-09', 'kind': 'leave'}));
      expect(bare.head, 'Leave');
      expect(bare.sub, '');
    });

    test('scheduled and off', () {
      final s = daySummaryOf(
        _day({
          'date': '2026-10-10',
          'kind': 'scheduled',
          'shift': '08:00 – 17:00',
        }),
      );
      expect(s.head, 'Scheduled');
      expect(s.sub, 'Shift 08:00 – 17:00');
      expect(s.tone, MyDayColors.waiting);
      expect(s.icon, Icons.schedule_outlined);
      final off = daySummaryOf(_day({'date': '2026-10-11', 'kind': 'off'}));
      expect(off.head, 'No shift');
      expect(off.sub, '');
      expect(off.tone, MyDayColors.waiting);
      expect(off.icon, Icons.wb_sunny_outlined);
      expect(
        daySummaryOf(_day({'date': '2026-10-11', 'kind': 'weird'})).head,
        'No shift',
      );
    });
  });

  testWidgets('showDaySheet renders title, head and sub', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Like HomeShell: the tab's own Navigator lives in the body, the bar
          // belongs to the Scaffold outside it.
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomNavigationBar: const SizedBox(key: ValueKey('nav'), height: 80),
        ),
      ),
    );
    showDaySheet(
      ctx,
      _day({
        'date': '2026-10-05',
        'kind': 'worked',
        'verdict': 'ok',
        'first_in': '08:02',
        'last_out': '17:05',
        'worked_minutes': 498,
        'place': 'Front desk',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Monday 5 October'), findsOneWidget);
    expect(find.text('Worked 8h 18m · on time'), findsOneWidget);
    expect(find.text('08:02 – 17:05 · Front desk'), findsOneWidget);
    // The sheet stops above the bottom bar: its bottom edge is at or above
    // the bar's top edge.
    final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
    final navTop = tester.getTopLeft(find.byKey(const ValueKey('nav'))).dy;
    expect(sheetBottom, lessThanOrEqualTo(navTop + 0.01));
  });
}
