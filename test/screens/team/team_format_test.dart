import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/team/team_format.dart';

import 'team_fixture.dart';

Map<String, dynamic> _leave({
  String from = '2026-10-22',
  String? to,
  String? fromPeriod,
  String? toPeriod,
  double hourFrom = 0,
  double hourTo = 0,
  double days = 1,
  String unit = 'day',
}) => {
  'id': 1,
  'employee_id': 12,
  'date_from': from,
  'date_to': to ?? from,
  'from_period': fromPeriod,
  'to_period': toPeriod,
  'hour_from': hourFrom,
  'hour_to': hourTo,
  'number_of_days': days,
  'unit': unit,
  'state': 'approved',
  'type': null,
};

void main() {
  group('dates', () {
    test('dayTitle is weekday, day, short month', () {
      expect(dayTitle(DateTime(2026, 10, 22)), 'Thu 22 Oct');
      expect(dayTitle(DateTime(2027, 1, 4)), 'Mon 4 Jan');
    });

    test('monthLabel spells the month and the year, across a new year', () {
      expect(monthLabel(DateTime(2026, 12)), 'December 2026');
      expect(monthLabel(DateTime(2027, 1)), 'January 2027');
    });

    test('clockLabel is 24 h', () {
      expect(clockLabel(DateTime(2026, 10, 22, 9, 5)), '09:05');
      expect(clockLabel(DateTime(2026, 10, 22, 17, 30)), '17:30');
    });

    test('isoDay pads month and day', () {
      expect(isoDay(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('initialsHue is hsl(id * 47 mod 360, 55%, 45%)', () {
      Color hsl(double hue) => HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
      expect(initialsHue(0), hsl(0));
      expect(initialsHue(8), hsl(16));
      expect(initialsHue(12), hsl(204));
      expect(initialsHue(12), isNot(initialsHue(14)));
    });
  });

  group('leaveWhenLabel', () {
    test('a whole day', () {
      expect(leaveWhenLabel(leaveRow(_leave())), 'Thu 22 Oct');
    });

    test('a morning or an afternoon', () {
      expect(
        leaveWhenLabel(
          leaveRow(_leave(fromPeriod: 'am', toPeriod: 'am', days: 0.5, unit: 'half_day')),
        ),
        'Thu 22 Oct (morning)',
      );
      expect(
        leaveWhenLabel(leaveRow(_leave(fromPeriod: 'pm', days: 0.5, unit: 'half_day'))),
        'Thu 22 Oct (afternoon)',
      );
    });

    test('morning to afternoon of one day is the whole day', () {
      expect(
        leaveWhenLabel(leaveRow(_leave(fromPeriod: 'am', toPeriod: 'pm'))),
        'Thu 22 Oct',
      );
    });

    test('hours', () {
      expect(
        leaveWhenLabel(
          leaveRow(_leave(from: '2026-11-03', hourFrom: 14, hourTo: 17, unit: 'hours')),
        ),
        'Tue 3 Nov, 14:00 – 17:00',
      );
      expect(
        leaveWhenLabel(
          leaveRow(_leave(from: '2026-11-03', hourFrom: 9.5, hourTo: 12.75, unit: 'hours')),
        ),
        'Tue 3 Nov, 09:30 – 12:45',
      );
    });

    test('several days with the day count', () {
      expect(
        leaveWhenLabel(leaveRow(_leave(from: '2026-11-12', to: '2026-11-13', days: 2))),
        'Thu 12 Nov – Fri 13 Nov · 2 days',
      );
      expect(
        leaveWhenLabel(leaveRow(_leave(from: '2026-11-13', to: '2026-11-16', days: 1))),
        'Fri 13 Nov – Mon 16 Nov · 1 day',
      );
      expect(
        leaveWhenLabel(leaveRow(_leave(from: '2026-11-12', to: '2026-11-13', days: 1.5))),
        'Thu 12 Nov – Fri 13 Nov · 1.5 days',
      );
    });

    test('across the new year', () {
      expect(
        leaveWhenLabel(leaveRow(_leave(from: '2026-12-31', to: '2027-01-04', days: 3))),
        'Thu 31 Dec – Mon 4 Jan · 3 days',
      );
    });

    test('several days starting in the afternoon or ending in the morning', () {
      expect(
        leaveWhenLabel(
          leaveRow(
            _leave(
              from: '2026-11-12',
              to: '2026-11-13',
              fromPeriod: 'pm',
              toPeriod: 'am',
              days: 1,
            ),
          ),
        ),
        'Thu 12 Nov (afternoon) – Fri 13 Nov (morning)',
      );
      expect(
        leaveWhenLabel(
          leaveRow(_leave(from: '2026-11-12', to: '2026-11-13', fromPeriod: 'pm', days: 1.5)),
        ),
        'Thu 12 Nov (afternoon) – Fri 13 Nov',
      );
    });

    test('no day count when the server sent none', () {
      expect(
        leaveWhenLabel(leaveRow(_leave(from: '2026-11-12', to: '2026-11-13', days: 0))),
        'Thu 12 Nov – Fri 13 Nov',
      );
    });
  });

  group('labels', () {
    test('heatDayLabel adds the holiday', () {
      expect(heatDayLabel(DateTime(2026, 10, 22), 3), 'Thu 22 Oct, 3 off');
      expect(
        heatDayLabel(DateTime(2026, 11, 9), 0, holidayName: 'Deepavali'),
        'Mon 9 Nov, 0 off, public holiday Deepavali',
      );
    });

    test('privacyLine combines type and pending', () {
      expect(
        privacyLine(showType: false, showPending: true),
        'Shown as “On leave” — no type or reason · includes pending requests',
      );
      expect(
        privacyLine(showType: true, showPending: false),
        'Leave type shown · approved leave only',
      );
    });

    test('teamScopeSubLabel by team kind', () {
      expect(teamScopeSubLabel(outlook()), 'Your department · 12 people');
      expect(
        teamScopeSubLabel(
          outlook(team: const {'kind': 'department', 'label': 'Solo', 'size': 1}),
        ),
        'Your department · 1 person',
      );
      final company = outlook(
        context: 'overview',
        team: const {'kind': 'overview', 'label': 'Novaworks', 'size': 60},
        departments: [
          for (var i = 1; i <= 6; i++) {'id': i, 'name': 'D$i', 'size': 10},
        ],
      );
      expect(teamScopeSubLabel(company), '60 people · 6 departments');
      // A department chip: that department's name and size (mockup).
      expect(teamScopeSubLabel(company, departmentId: 2), 'D2 · 10 people');
      // An id the list does not hold: the scope size.
      expect(teamScopeSubLabel(company, departmentId: 99), '60 people');
    });

    test('teamEmptyReasonText for every reason', () {
      expect(
        teamEmptyReasonText('no_department'),
        'Team leave shows the people in your department. Ask HR to add you to one.',
      );
      expect(
        teamEmptyReasonText('no_approver'),
        'Team leave shows the people who share your leave approver. Ask HR to set yours.',
      );
      expect(teamEmptyReasonText('no_people'), 'No one to show here yet.');
      expect(teamEmptyReasonText('off'), 'Team leave is turned off for your company.');
      expect(teamEmptyReasonText('something_new'), 'No one to show here yet.');
    });
  });

  group('days', () {
    test('leavesOnByName lists the rows covering the day, by name', () {
      final o = outlook();
      expect(
        leavesOnByName(o, DateTime(2026, 10, 22)).map((r) => r.id),
        [901, 902],
      );
      expect(leavesOnByName(o, DateTime(2026, 11, 13)).map((r) => r.id), [903]);
      expect(leavesOnByName(o, DateTime(2026, 10, 23)), isEmpty);
    });

    test('outlookToday: the server day, else the first day of the range', () {
      expect(outlookToday(outlook()), DateTime(2026, 10, 22));
      final noToday = TeamOutlook.fromJson({
        ...outlookJson(),
        'today': null,
      });
      expect(outlookToday(noToday), DateTime(2026, 10, 22));
    });

    test('defaultTeamDay: today when someone is off today', () {
      expect(defaultTeamDay(outlook()), DateTime(2026, 10, 22));
    });

    test('defaultTeamDay: else the busiest day, the earliest of equals', () {
      final o = outlook(off: const {'2026-10-26': 1, '2026-10-27': 3, '2026-11-02': 3});
      expect(defaultTeamDay(o), DateTime(2026, 10, 27));
    });

    test('defaultTeamDay: else today', () {
      final TeamOutlook o = outlook(off: const {}, leaves: const []);
      expect(defaultTeamDay(o), DateTime(2026, 10, 22));
    });
  });
}
