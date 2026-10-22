import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_outlook.dart';

/// The connector plan's `leave/team_outlook` sample, plus a few rows that
/// exercise the other units and states.
Map<String, dynamic> outlookSample() => {
      'success': true,
      'context': 'team',
      'view': 'team',
      'views': ['team', 'approvees'],
      'range': {'from': '2026-10-22', 'to': '2026-11-20', 'days': 30},
      'today': '2026-10-22',
      'team': {
        'kind': 'department',
        'label': 'Marketing',
        'size': 12,
        'department_id': 5,
      },
      'empty_reason': null,
      // HR turned pending on here (the default is off, D3 / A-L25): this
      // sample checks that an explicit true parses.
      'disclosure': {'show_type': false, 'show_pending': true},
      'departments': [
        {'id': 5, 'name': 'Marketing', 'size': 20},
      ],
      'summary': {
        'this_week_off': 2,
        'label': 'Marketing',
        'faces': [
          {'id': 12, 'initials': 'MO'},
          {'id': 14, 'initials': 'PN'},
        ],
      },
      'people': [
        {
          'id': 12,
          'name': 'Mei Lin Ong',
          'initials': 'MO',
          'department': 'Marketing',
          'you': false,
        },
        {
          'id': 14,
          'name': 'Priya Nair',
          'initials': 'PN',
          'department': 'Marketing',
          'you': true,
        },
      ],
      'leaves': [
        {
          'id': 901,
          'employee_id': 12,
          'date_from': '2026-10-22',
          'date_to': '2026-10-22',
          'from_period': 'am',
          'to_period': 'am',
          'hour_from': 0.0,
          'hour_to': 0.0,
          'number_of_days': 0.5,
          'unit': 'half_day',
          'state': 'approved',
          'type': null,
        },
        {
          'id': 902,
          'employee_id': 14,
          'date_from': '2026-11-12',
          'date_to': '2026-11-13',
          'from_period': null,
          'to_period': null,
          'hour_from': 0.0,
          'hour_to': 0.0,
          'number_of_days': 2,
          'unit': 'day',
          'state': 'pending',
          'type': 'Annual Leave',
        },
        {
          'id': 903,
          'employee_id': 12,
          'date_from': '2026-11-03',
          'date_to': '2026-11-03',
          'from_period': null,
          'to_period': null,
          'hour_from': 14.0,
          'hour_to': 17.0,
          'number_of_days': 0.375,
          'unit': 'hours',
          'state': 'approved',
          'type': null,
        },
      ],
      'days': [
        {
          'date': '2026-10-22',
          'off': 3,
          'pending': 1,
          'workday': true,
          'holiday': null,
        },
        {
          'date': '2026-10-24',
          'off': 0,
          'pending': 0,
          'workday': false,
          'holiday': null,
        },
        {
          'date': '2026-11-08',
          'off': 0,
          'pending': 0,
          'workday': true,
          'holiday': {'name': 'Deepavali', 'everyone': true},
        },
      ],
      'holidays': [
        {'date': '2026-11-08', 'name': 'Deepavali', 'everyone': true},
      ],
      'truncated': false,
      'auth_type': 'session',
    };

void main() {
  group('TeamOutlook.fromJson — contract sample', () {
    test('top level, range and scope', () {
      final o = TeamOutlook.fromJson(outlookSample());
      expect(o.context, 'team');
      expect(o.view, 'team');
      expect(o.views, ['team', 'approvees']);
      expect(o.rangeFrom, DateTime(2026, 10, 22));
      expect(o.rangeTo, DateTime(2026, 11, 20));
      expect(o.rangeDays, 30);
      expect(o.today, DateTime(2026, 10, 22));
      expect(o.team!.kind, 'department');
      expect(o.team!.label, 'Marketing');
      expect(o.team!.size, 12);
      expect(o.team!.departmentId, 5);
      expect(o.emptyReason, isNull);
      expect(o.disclosure.showType, isFalse);
      expect(o.disclosure.showPending, isTrue);
      expect(o.truncated, isFalse);
      expect(o.isEmpty, isFalse);
    });

    test('departments, summary and people', () {
      final o = TeamOutlook.fromJson(outlookSample());
      expect(o.departments.single.id, 5);
      expect(o.departments.single.name, 'Marketing');
      expect(o.departments.single.size, 20);
      expect(o.summary.thisWeekOff, 2);
      expect(o.summary.label, 'Marketing');
      expect(o.summary.faces.map((f) => f.initials), ['MO', 'PN']);
      expect(o.summary.faces.first.id, 12);
      expect(o.people, hasLength(2));
      expect(o.person(14)!.name, 'Priya Nair');
      expect(o.person(14)!.you, isTrue);
      expect(o.person(12)!.department, 'Marketing');
      expect(o.person(99), isNull);
    });

    test('leaves: half day, multi-day pending with a type, hours', () {
      final o = TeamOutlook.fromJson(outlookSample());
      final half = o.leaves[0];
      expect(half.id, 901);
      expect(half.employeeId, 12);
      expect(half.name, '');
      expect(half.dateFrom, DateTime(2026, 10, 22));
      expect(half.dateTo, DateTime(2026, 10, 22));
      expect(half.fromPeriod, 'am');
      expect(half.toPeriod, 'am');
      expect(half.numberOfDays, 0.5);
      expect(half.unit, 'half_day');
      expect(half.isPending, isFalse);
      expect(half.type, isNull);

      final multi = o.leaves[1];
      expect(multi.dateFrom, DateTime(2026, 11, 12));
      expect(multi.dateTo, DateTime(2026, 11, 13));
      expect(multi.fromPeriod, isNull);
      expect(multi.numberOfDays, 2.0);
      expect(multi.isPending, isTrue);
      expect(multi.type, 'Annual Leave');

      final hours = o.leaves[2];
      expect(hours.isHours, isTrue);
      expect(hours.hourFrom, 14.0);
      expect(hours.hourTo, 17.0);
    });

    test('days and holidays', () {
      final o = TeamOutlook.fromJson(outlookSample());
      expect(o.days, hasLength(3));
      final today = o.dayOf(DateTime(2026, 10, 22))!;
      expect(today.off, 3);
      expect(today.pending, 1);
      expect(today.workday, isTrue);
      expect(today.holiday, isNull);
      expect(o.dayOf(DateTime(2026, 10, 24))!.workday, isFalse);
      final ph = o.dayOf(DateTime(2026, 11, 8))!.holiday!;
      expect(ph.name, 'Deepavali');
      expect(ph.everyone, isTrue);
      expect(o.holidays.single.date, DateTime(2026, 11, 8));
      expect(o.dayOf(DateTime(2026, 12, 1)), isNull);
    });

    test('dayOf and leavesOn ignore the time of day', () {
      final o = TeamOutlook.fromJson(outlookSample());
      expect(o.dayOf(DateTime(2026, 10, 22, 17, 45))!.off, 3);
      expect(o.leavesOn(DateTime(2026, 11, 13, 9)).single.id, 902);
      expect(o.leavesOn(DateTime(2026, 11, 12)).single.id, 902);
      expect(o.leavesOn(DateTime(2026, 11, 14)), isEmpty);
      expect(o.leaves[1].covers(DateTime(2026, 11, 11)), isFalse);
    });

    test('raw keeps the decoded body for TeamCache', () {
      final body = outlookSample();
      final o = TeamOutlook.fromJson(body);
      expect(o.raw['view'], 'team');
      final back = TeamOutlook.fromJson(
          jsonDecode(jsonEncode(o.raw)) as Map<String, dynamic>);
      expect(back.leaves, hasLength(3));
      expect(back.summary.thisWeekOff, 2);
    });
  });

  group('TeamOutlook.fromJson — empty and missing keys', () {
    test('an empty map gives the defaults and never throws', () {
      final o = TeamOutlook.fromJson(const {});
      expect(o.context, 'team');
      expect(o.view, 'team');
      expect(o.views, isEmpty);
      expect(o.rangeFrom, isNull);
      expect(o.rangeDays, 30);
      expect(o.today, isNull);
      expect(o.team, isNull);
      expect(o.emptyReason, isNull);
      expect(o.disclosure.showType, isFalse);
      // Pending is off unless the server says so (D3, A-L25).
      expect(o.disclosure.showPending, isFalse);
      expect(o.departments, isEmpty);
      expect(o.summary.thisWeekOff, 0);
      expect(o.summary.faces, isEmpty);
      expect(o.people, isEmpty);
      expect(o.leaves, isEmpty);
      expect(o.days, isEmpty);
      expect(o.holidays, isEmpty);
      expect(o.truncated, isFalse);
      expect(o.isEmpty, isTrue);
    });

    test('an empty reason still sends range, days and holidays', () {
      final o = TeamOutlook.fromJson({
        'empty_reason': 'no_department',
        'range': {'from': '2026-10-22', 'to': '2026-11-20', 'days': 30},
        'days': [
          {'date': '2026-10-22', 'off': 0, 'pending': 0, 'workday': true},
        ],
        'holidays': [
          {'date': '2026-11-08', 'name': 'Deepavali', 'everyone': true},
        ],
        'people': [],
        'leaves': [],
      });
      expect(o.emptyReason, 'no_department');
      expect(o.isEmpty, isTrue);
      expect(o.days.single.off, 0);
      expect(o.holidays, hasLength(1));
    });

    test('wrong types read as defaults; rows without a date are dropped', () {
      final o = TeamOutlook.fromJson({
        'views': 'team',
        'range': 'soon',
        'team': ['Marketing'],
        'empty_reason': '',
        'disclosure': {'show_type': 'yes', 'show_pending': 'yes'},
        'departments': [
          {'id': 0, 'name': 'Nobody'},
          'junk',
          {'id': 7, 'name': 'Fabric'},
        ],
        'summary': {'this_week_off': '2', 'faces': 'MO'},
        'leaves': [
          {'id': 1, 'employee_id': 3, 'date_from': '2026-02-31'},
          {'id': 2, 'employee_id': 3, 'date_from': 'tomorrow'},
          {'id': 3, 'employee_id': 3},
          {
            'id': 4,
            'employee_id': 3,
            'date_from': '2026-10-23',
            'from_period': 'noon',
            'unit': '',
            'state': '',
            'type': '',
          },
          'not a map',
        ],
        'days': [
          {'off': 2},
          {'date': '2026-10-23', 'off': 'two', 'workday': 'yes'},
        ],
        'holidays': [
          {'name': 'No date', 'everyone': true},
        ],
        'truncated': 'true',
      });
      expect(o.views, isEmpty);
      expect(o.rangeFrom, isNull);
      expect(o.team, isNull);
      expect(o.emptyReason, isNull);
      // A string is not true: both stay off (A-L25).
      expect(o.disclosure.showType, isFalse);
      expect(o.disclosure.showPending, isFalse);
      expect(o.departments.map((d) => d.id), [7]);
      expect(o.departments.single.size, 0);
      expect(o.summary.thisWeekOff, 0);
      expect(o.summary.faces, isEmpty);
      final row = o.leaves.single;
      expect(row.id, 4);
      expect(row.dateTo, DateTime(2026, 10, 23)); // missing date_to = date_from
      expect(row.fromPeriod, isNull);
      expect(row.unit, 'day');
      expect(row.state, 'approved');
      expect(row.type, isNull);
      final day = o.days.single;
      expect(day.off, 0);
      expect(day.workday, isTrue);
      expect(o.holidays, isEmpty);
      expect(o.truncated, isFalse);
    });

    test('a date_to before date_from is clamped to date_from', () {
      final row = TeamLeaveRow.tryParse({
        'date_from': '2026-11-13',
        'date_to': '2026-11-12',
      })!;
      expect(row.dateTo, DateTime(2026, 11, 13));
    });

    test('truncated: true is read', () {
      expect(TeamOutlook.fromJson({'truncated': true}).truncated, isTrue);
    });

    test('view is null in the overview context (the server sends null)', () {
      final o = TeamOutlook.fromJson({
        'context': 'overview',
        'view': null,
        'views': <String>[],
      });
      expect(o.context, 'overview');
      expect(o.view, isNull);
      // Even a stray value is not read as a selected team-context chip.
      expect(
          TeamOutlook.fromJson({'context': 'overview', 'view': 'team'}).view,
          isNull);
      // The team context keeps the 'team' default.
      expect(TeamOutlook.fromJson({'context': 'team', 'view': null}).view,
          'team');
    });
  });

  group('TeamOverlap.fromJson', () {
    test('the contract sample', () {
      final o = TeamOverlap.fromJson({
        'success': true,
        'people': [
          {
            'name': 'Rachel Wong',
            'date_from': '2026-11-12',
            'date_to': '2026-11-12',
            'from_period': null,
            'to_period': null,
            'hour_from': 0.0,
            'hour_to': 0.0,
            'unit': 'day',
            'state': 'approved',
          },
          {
            'name': 'Jason Lee',
            'date_from': '2026-11-13',
            'date_to': '2026-11-13',
            'from_period': 'pm',
            'to_period': 'pm',
            'hour_from': 0.0,
            'hour_to': 0.0,
            'unit': 'half_day',
            'state': 'pending',
          },
        ],
        'more': 3,
        'empty_reason': null,
      });
      expect(o.people.map((p) => p.name), ['Rachel Wong', 'Jason Lee']);
      expect(o.people.first.dateFrom, DateTime(2026, 11, 12));
      expect(o.people.first.type, isNull);
      expect(o.people.last.fromPeriod, 'pm');
      expect(o.people.last.isPending, isTrue);
      expect(o.more, 3);
      expect(o.emptyReason, isNull);
      expect(o.isEmpty, isFalse);
    });

    test('off setting: empty list plus a reason', () {
      final o = TeamOverlap.fromJson(
          {'success': true, 'people': [], 'more': 0, 'empty_reason': 'off'});
      expect(o.isEmpty, isTrue);
      expect(o.emptyReason, 'off');
    });

    test('missing keys', () {
      final o = TeamOverlap.fromJson(const {});
      expect(o.people, isEmpty);
      expect(o.more, 0);
      expect(o.emptyReason, isNull);
    });
  });
}
