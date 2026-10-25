import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/overview_copy.dart';
import 'package:omni_hr/screens/home/overview/overview_tiles.dart';
import 'package:omni_hr/screens/home/overview/who_out_card.dart';
import 'package:omni_hr/screens/team/team_colors.dart';

WhoOutToday _row(Map<String, dynamic> json) => TeamOverview.fromJson({
  'who_out': {
    'today': [json],
    'next_7': [],
  },
}).whoOut!.today.single;

Map<String, dynamic> _p({
  String name = 'Lina Koh',
  String department = 'Fabric',
  String? type,
  String state = 'approved',
  String? part,
  String? until = '2026-10-22',
  String? backAt,
}) => {
  'id': 31,
  'name': name,
  'initials': 'LK',
  'department': department,
  'type': type,
  'state': state,
  'part': part,
  'until': until,
  'back_at': backAt,
  'tracked': true,
};

final _today = DateTime(2026, 10, 22);

void main() {
  group('today cells (Task 7 bucket table)', () {
    test('one cell per bucket, in tile order, with its count', () {
      final cells = todayCells(
        OverviewCounts.fromJson({
          'on_time': 36,
          'late': 6,
          'not_in_yet': 4,
          'no_check_in': 3,
          'on_leave': 4,
          'off_today': 1,
        }),
      );
      expect(cells.map((c) => c.id), overviewBucketOrder);
      expect(cells.map((c) => c.label), [
        'On time',
        'Late',
        'Not in yet',
        'No check-in',
        'On leave',
        'Off today',
      ]);
      expect(cells.map((c) => c.count), [36, 6, 4, 3, 4, 1]);
    });
  });

  group('OverviewCopy', () {
    test('Yesterday copy (A-L7)', () {
      expect(OverviewCopy.reviewedFinal, 'Scored by the Daily Review');
      expect(
        OverviewCopy.reviewedProvisional,
        'Still being scored — numbers may change tonight.',
      );
    });

    test('tile semantics: person / people', () {
      expect(OverviewCopy.tileSemantics('Late', 6), 'Late: 6 people');
      expect(OverviewCopy.tileSemantics('Off today', 1), 'Off today: 1 person');
    });

    test('the live line, with and without the time', () {
      expect(
        OverviewCopy.liveLine('09:12', 54),
        'Live · as of 09:12 · not yet reviewed by HR · 54 people tracked',
      );
      expect(
        OverviewCopy.liveLine('', 54),
        'Live · not yet reviewed by HR · 54 people tracked',
      );
    });

    test('expected lines', () {
      expect(
        OverviewCopy.ofExpectedToday(49, 'Novaworks'),
        'of 49 expected · Novaworks today',
      );
      expect(
        OverviewCopy.ofExpectedOn(50, DateTime(2026, 10, 21), 'Novaworks'),
        'of 50 expected · Wed 21 Oct · Novaworks',
      );
      expect(OverviewCopy.ofExpectedOn(50, null, ''), 'of 50 expected');
    });
  });

  group('overviewTone', () {
    test('Today keys are T5\'s tones', () {
      for (final b in overviewBucketOrder) {
        expect(overviewTone(b), same(TeamColors.bucket(b)));
      }
    });

    test('Yesterday ids borrow Late, No check-in and Off today', () {
      expect(overviewTone('left_early'), same(TeamColors.bucket('late')));
      expect(overviewTone('absent'), same(TeamColors.bucket('no_check_in')));
      expect(overviewTone('off'), same(TeamColors.bucket('off_today')));
    });

    test('every Today bucket has its own dot', () {
      final dots = {for (final b in overviewBucketOrder) overviewTone(b).dot};
      expect(dots.length, 6);
    });
  });

  group('whoOutTodayLine', () {
    test('a full-day leave until later, with its type', () {
      expect(
        whoOutTodayLine(
          _row(_p(type: 'Annual Leave', until: '2026-10-23')),
          today: _today,
        ),
        'Fabric · Annual Leave · until Fri 23 Oct',
      );
    });

    test('no type sent (D4): "On leave"; ending today: "today"', () {
      expect(
        whoOutTodayLine(
          _row(_p(name: 'Patricia Wee', department: 'Management')),
          today: _today,
        ),
        'Management · On leave · today',
      );
    });

    test('a morning off, back after lunch', () {
      expect(
        whoOutTodayLine(
          _row(_p(department: 'Marketing', part: 'morning', backAt: '13:30')),
          today: _today,
        ),
        'Marketing · morning only, back 13:30',
      );
    });

    test('an afternoon off', () {
      expect(
        whoOutTodayLine(_row(_p(part: 'afternoon')), today: _today),
        'Fabric · afternoon only',
      );
    });

    test('a few hours off, no return time known', () {
      expect(
        whoOutTodayLine(_row(_p(part: 'hours')), today: _today),
        'Fabric · part of the day',
      );
    });

    test('pending (D3) and no department', () {
      expect(
        whoOutTodayLine(
          _row(_p(department: '', state: 'pending')),
          today: _today,
        ),
        'On leave · today · pending',
      );
    });
  });

  group('next 7 days', () {
    test('day label', () {
      expect(next7DayLabel(DateTime(2026, 10, 23)), 'Fri 23');
    });

  });

  group('collapseNext7 (1.34.1)', () {
    Map<String, dynamic> p(
      int id,
      String name, {
      String department = 'R&D',
      String state = 'approved',
    }) => {'id': id, 'name': name, 'department': department, 'state': state};

    List<Next7Range> collapse(Map<String, List<Map<String, dynamic>>> byDay) =>
        collapseNext7(
          WhoOut.fromJson({
            'today': [],
            'next_7': [
              for (final e in byDay.entries)
                {'date': e.key, 'people': e.value},
            ],
          }).next7,
        );

    test('a single day', () {
      final r = collapse({
        '2026-10-23': [p(14, 'Priya Nair', department: 'Marketing')],
      });
      expect(r.map((x) => x.line), ['Priya Nair · Marketing · Fri 23']);
      expect(r.single.pending, isFalse);
    });

    test('consecutive days become one line', () {
      final r = collapse({
        for (final d in ['26', '27', '28', '29', '30', '31'])
          '2026-10-$d': [p(7, 'Vanessa Leonora')],
        '2026-11-01': [p(7, 'Vanessa Leonora')],
      });
      expect(r.map((x) => x.line), ['Vanessa Leonora · R&D · Mon 26 – Sun 1']);
      expect(r.single.from, DateTime(2026, 10, 26));
      expect(r.single.to, DateTime(2026, 11, 1));
    });

    test('a month boundary does not split a run', () {
      final r = collapse({
        '2026-10-31': [p(7, 'Vanessa Leonora')],
        '2026-11-01': [p(7, 'Vanessa Leonora')],
        '2026-11-02': [p(7, 'Vanessa Leonora')],
      });
      expect(r.map((x) => x.line), ['Vanessa Leonora · R&D · Sat 31 – Mon 2']);
    });

    test('a gap splits the run', () {
      final r = collapse({
        '2026-10-26': [p(7, 'Vanessa Leonora')],
        '2026-10-27': [p(7, 'Vanessa Leonora')],
        '2026-10-29': [p(7, 'Vanessa Leonora')],
      });
      expect(r.map((x) => x.line), [
        'Vanessa Leonora · R&D · Mon 26 – Tue 27',
        'Vanessa Leonora · R&D · Thu 29',
      ]);
    });

    test('a status change splits the run; the pending part keeps its flag', () {
      final r = collapse({
        '2026-10-26': [p(7, 'Vanessa Leonora')],
        '2026-10-27': [p(7, 'Vanessa Leonora')],
        '2026-10-28': [p(7, 'Vanessa Leonora', state: 'pending')],
        '2026-10-29': [p(7, 'Vanessa Leonora', state: 'pending')],
      });
      expect(r.map((x) => x.toString()), [
        'Vanessa Leonora · R&D · Mon 26 – Tue 27',
        'Vanessa Leonora · R&D · Wed 28 – Thu 29 (pending)',
      ]);
    });

    test('several people: ordered by first day, then name; no department '
        'means no department part', () {
      final r = collapse({
        '2026-10-23': [
          p(31, 'Lina Koh', department: 'Fabric', state: 'pending'),
          p(14, 'Priya Nair', department: 'Marketing'),
        ],
        '2026-10-24': [p(14, 'Priya Nair', department: 'Marketing')],
        '2026-10-26': [p(40, 'Daniel Tan', department: '')],
        '2026-10-22': [p(41, 'Marcus Yeo', department: '')],
      });
      expect(r.map((x) => x.toString()), [
        'Marcus Yeo · Thu 22',
        'Lina Koh · Fabric · Fri 23 (pending)',
        'Priya Nair · Marketing · Fri 23 – Sat 24',
        'Daniel Tan · Mon 26',
      ]);
    });

    test('unordered days and a person listed twice on one day', () {
      final r = collapse({
        '2026-10-24': [p(7, 'Vanessa Leonora')],
        '2026-10-23': [p(7, 'Vanessa Leonora'), p(7, 'Vanessa Leonora')],
      });
      expect(r.map((x) => x.line), ['Vanessa Leonora · R&D · Fri 23 – Sat 24']);
    });

    test('nothing in the next 7 days: no lines', () {
      expect(collapse({}), isEmpty);
      expect(collapse({'2026-10-23': []}), isEmpty);
    });
  });
}
