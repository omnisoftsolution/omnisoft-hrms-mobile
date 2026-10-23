import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/leave/also_off_line.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

Map<String, dynamic> _p(
  String name,
  String from,
  String to, {
  String unit = 'day',
  String? fromPeriod,
  String? toPeriod,
  double hourFrom = 0,
  double hourTo = 0,
  String state = 'approved',
}) => {
  'name': name,
  'date_from': from,
  'date_to': to,
  'from_period': fromPeriod,
  'to_period': toPeriod,
  'hour_from': hourFrom,
  'hour_to': hourTo,
  'unit': unit,
  'state': state,
};

TeamOverlap _overlap(List<Map<String, dynamic>> people, {int more = 0}) =>
    TeamOverlap.fromJson({
      'success': true,
      'people': people,
      'more': more,
      'empty_reason': null,
    });

TeamLeaveRow _row(Map<String, dynamic> json) =>
    _overlap([json]).people.single;

void main() {
  group('alsoOffText', () {
    test('a full day', () {
      expect(
        alsoOffText(_row(_p('Rachel Wong', '2026-11-12', '2026-11-12'))),
        'Rachel Wong · Thu 12 Nov',
      );
    });

    test('an afternoon, pending', () {
      expect(
        alsoOffText(
          _row(
            _p(
              'Jason Lee',
              '2026-11-12',
              '2026-11-12',
              unit: 'half_day',
              fromPeriod: 'pm',
              toPeriod: 'pm',
              state: 'pending',
            ),
          ),
        ),
        'Jason Lee · Thu 12 Nov (afternoon) · pending',
      );
    });

    test('a morning', () {
      expect(
        alsoOffText(
          _row(
            _p(
              'Mei Lin Ong',
              '2026-10-22',
              '2026-10-22',
              unit: 'half_day',
              fromPeriod: 'am',
              toPeriod: 'am',
            ),
          ),
        ),
        'Mei Lin Ong · Thu 22 Oct (morning)',
      );
    });

    test('several days', () {
      expect(
        alsoOffText(_row(_p('Priya Nair', '2026-11-12', '2026-11-13'))),
        'Priya Nair · Thu 12 Nov – Fri 13 Nov',
      );
    });

    test('several days starting in the afternoon, ending in the morning', () {
      expect(
        alsoOffText(
          _row(
            _p(
              'Lina Koh',
              '2026-11-12',
              '2026-11-13',
              unit: 'half_day',
              fromPeriod: 'pm',
              toPeriod: 'am',
            ),
          ),
        ),
        'Lina Koh · Thu 12 Nov (afternoon) – Fri 13 Nov (morning)',
      );
    });

    test('hours', () {
      expect(
        alsoOffText(
          _row(
            _p(
              'Kelvin Goh',
              '2026-11-03',
              '2026-11-03',
              unit: 'hours',
              hourFrom: 9.5,
              hourTo: 17,
            ),
          ),
        ),
        'Kelvin Goh · Tue 3 Nov, 09:30 – 17:00',
      );
    });
  });

  testWidgets('AlsoOffLine: title, rows, +N more, reassurance, link', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlsoOffLine(
            overlap: _overlap([
              _p('Rachel Wong', '2026-11-12', '2026-11-12'),
              _p(
                'Jason Lee',
                '2026-11-12',
                '2026-11-12',
                unit: 'half_day',
                fromPeriod: 'pm',
                toPeriod: 'pm',
                state: 'pending',
              ),
            ], more: 2),
            onSeeTeamLeave: () => opened++,
          ),
        ),
      ),
    );
    expect(find.text('Also off on these dates'), findsOneWidget);
    expect(find.text('Rachel Wong · Thu 12 Nov'), findsOneWidget);
    expect(
      find.text('Jason Lee · Thu 12 Nov (afternoon) · pending'),
      findsOneWidget,
    );
    expect(find.text('+2 more'), findsOneWidget);
    expect(
      find.text('Just so you know — this never stops you applying.'),
      findsOneWidget,
    );
    await tester.tap(find.text('See team leave'));
    expect(opened, 1);
  });

  testWidgets('no "+N more" when nothing is left over', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlsoOffLine(
            overlap: _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]),
            onSeeTeamLeave: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('more'), findsNothing);
  });

  group('TeamOverlapLookup', () {
    final d12 = DateTime(2026, 11, 12);
    final d13 = DateTime(2026, 11, 13);
    final d14 = DateTime(2026, 11, 14);

    testWidgets('asks once, 400 ms after the last change', (tester) async {
      final asked = <String>[];
      var changes = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async {
          asked.add('${from.day}-${to.day}');
          return _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]);
        },
        onChanged: () => changes++,
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 200));
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 399));
      expect(asked, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(asked, ['12-13']);
      await tester.pump();
      expect(lookup.visible, isTrue);
      expect(changes, 1);
      lookup.dispose();
    });

    testWidgets('the same dates are not asked again', (tester) async {
      var asked = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async {
          asked++;
          return _overlap([]);
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 400));
      lookup.schedule(DateTime(2026, 11, 12, 15, 30), d13); // same day
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked, 1);
      lookup.dispose();
    });

    testWidgets('a stale answer is dropped', (tester) async {
      final first = Completer<TeamOverlap>();
      var asked = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) {
          asked++;
          return asked == 1
              ? first.future
              : Future.value(
                  _overlap([_p('Priya Nair', '2026-11-14', '2026-11-14')]),
                );
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 400)); // first on the wire
      lookup.schedule(d14, d14);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.value!.people.single.name, 'Priya Nair');

      first.complete(
        _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]),
      );
      await tester.pump();
      expect(lookup.value!.people.single.name, 'Priya Nair');
      lookup.dispose();
    });

    testWidgets('new dates hide the old answer at once', (tester) async {
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async =>
            _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]),
        onChanged: () {},
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.visible, isTrue);
      lookup.schedule(d13, d13);
      expect(lookup.visible, isFalse);
      expect(lookup.value, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      lookup.dispose();
    });

    testWidgets('an empty list is not visible', (tester) async {
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async => TeamOverlap.fromJson({
          'success': true,
          'people': [],
          'more': 0,
          'empty_reason': 'no_department',
        }),
        onChanged: () {},
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.visible, isFalse);
      lookup.dispose();
    });

    testWidgets('an error hides the line and the next dates ask again', (
      tester,
    ) async {
      var asked = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async {
          asked++;
          throw ApiException('network_error');
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.visible, isFalse);
      lookup.schedule(d13, d13);
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked, 2);
      lookup.dispose();
    });

    testWidgets('after an error the same dates are asked again (A10)', (
      tester,
    ) async {
      var asked = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async {
          asked++;
          if (asked == 1) throw ApiException('network_error');
          return _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]);
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.visible, isFalse);
      // The sheet schedules the unchanged dates again (a rebuild, a
      // re-open of the picker): the blip is retried.
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(asked, 2);
      expect(lookup.visible, isTrue);
      // A success remembers the dates again: no third ask.
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked, 2);
      lookup.dispose();
    });

    testWidgets('an older connector (HTML 404) is not asked again', (
      tester,
    ) async {
      var asked = 0;
      final lookup = TeamOverlapLookup(
        fetch: (from, to) async {
          asked++;
          throw ApiException('server_error', data: {'http_status': 404});
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d12);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      lookup.schedule(d13, d13);
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked, 1);
      expect(lookup.visible, isFalse);
      lookup.dispose();
    });

    testWidgets('invalidate hides the answer at once and asks the same dates '
        'again; an answer on the wire is dropped (A-L22)', (tester) async {
      final wire = Completer<TeamOverlap>();
      final asked = <String>[];
      final lookup = TeamOverlapLookup(
        fetch: (from, to) {
          asked.add('${from.day}-${to.day}');
          return switch (asked.length) {
            1 => Future.value(
              _overlap([_p('Rachel Wong', '2026-11-12', '2026-11-12')]),
            ),
            2 => wire.future,
            _ => Future.value(
              _overlap([_p('Priya Nair', '2026-11-12', '2026-11-12')]),
            ),
          };
        },
        onChanged: () {},
      );
      lookup.schedule(d12, d13);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.value!.people.single.name, 'Rachel Wong');
      // Hide only: nothing is asked.
      lookup.invalidate(askAgain: false);
      expect(lookup.value, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(asked, ['12-13']);
      // Ask again: the same dates, after the delay.
      lookup.invalidate();
      await tester.pump(const Duration(milliseconds: 400));
      expect(asked, ['12-13', '12-13']); // on the wire
      lookup.invalidate();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(lookup.value!.people.single.name, 'Priya Nair');
      wire.complete(_overlap([_p('Jason Lee', '2026-11-12', '2026-11-12')]));
      await tester.pump();
      expect(lookup.value!.people.single.name, 'Priya Nair');
      lookup.dispose();
    });
  });
}
