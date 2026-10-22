import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/team_overview.dart';

/// The connector plan's `home/overview` (today) sample, with one For-you
/// row of a known kind and one of an unknown kind.
Map<String, dynamic> overviewSample() => {
      'success': true,
      'day': 'today',
      'date': '2026-10-22',
      'as_of': '09:12',
      'live': true,
      'scope': {
        'access': 'company',
        'label': 'Novaworks',
        'department_id': null,
        'empty_reason': null,
      },
      'departments': [
        {'id': 5, 'name': 'Marketing'},
      ],
      'sections': {'attendance': true, 'leave': true},
      'names': true,
      'counts': {
        'on_time': 36,
        'late': 6,
        'not_in_yet': 4,
        'no_check_in': 3,
        'on_leave': 4,
        'off_today': 1,
        'checked_in': 42,
        'expected': 49,
        'tracked': 54,
      },
      'who_out': {
        'today': [
          {
            'id': 31,
            'name': 'Lina Koh',
            'initials': 'LK',
            'department': 'Fabric',
            'type': null,
            'state': 'approved',
            'part': null,
            'until': '2026-10-23',
            'back_at': null,
            'tracked': false,
          },
          {
            'id': 32,
            'name': 'Ahmad Rahman',
            'initials': 'AR',
            'department': 'Sewing',
            'type': 'Sick Leave',
            'state': 'pending',
            'part': 'morning',
            'until': null,
            'back_at': '13:30',
            'tracked': true,
          },
        ],
        'next_7': [
          {
            'date': '2026-10-23',
            'people': [
              {
                'id': 14,
                'name': 'Priya Nair',
                'department': 'Marketing',
                'state': 'approved',
              },
            ],
          },
        ],
      },
      'for_you': [
        {'kind': 'leave_approvals', 'count': 2, 'oldest_at': '2026-10-21 02:00:00'},
        {'kind': 'team_party', 'id': 9},
      ],
      'auth_type': 'session',
    };

Map<String, dynamic> yesterdaySample({bool provisional = false}) => {
      'success': true,
      'day': 'yesterday',
      'date': '2026-10-21',
      'as_of': '09:12',
      'live': false,
      'scope': {'access': 'department', 'label': 'Marketing', 'department_id': 5},
      'sections': {'attendance': true, 'leave': true},
      'names': false,
      'reviewed': {
        'date': '2026-10-21',
        'provisional': provisional,
        'counts': {
          'on_time': 43,
          'late': 4,
          'left_early': 2,
          'absent': 1,
          'on_leave': 3,
          'off': 1,
          'not_reviewed': 0,
          'worked': 47,
          'expected': 50,
          'tracked': 54,
        },
      },
      'who_out': null,
      'for_you': [],
    };

void main() {
  group('TeamOverview.fromJson — today', () {
    test('top level, scope and sections', () {
      final o = TeamOverview.fromJson(overviewSample());
      expect(o.day, 'today');
      expect(o.date, DateTime(2026, 10, 22));
      expect(o.asOf, '09:12');
      expect(o.live, isTrue);
      expect(o.scope.access, 'company');
      expect(o.scope.label, 'Novaworks');
      expect(o.scope.departmentId, isNull);
      expect(o.scope.emptyReason, isNull);
      expect(o.departments.single.name, 'Marketing');
      expect(o.sections.attendance, isTrue);
      expect(o.sections.leave, isTrue);
      expect(o.names, isTrue);
      expect(o.reviewed, isNull);
      expect(o.raw['as_of'], '09:12');
    });

    test('counts and the total helpers', () {
      final c = TeamOverview.fromJson(overviewSample()).counts!;
      expect(c.onTime, 36);
      expect(c.lateCount, 6);
      expect(c.notInYet, 4);
      expect(c.noCheckIn, 3);
      expect(c.onLeave, 4);
      expect(c.offToday, 1);
      expect(c.totalCheckedIn, 42);
      expect(c.totalExpected, 49);
      expect(c.totalTracked, 54);
      expect(c.totalBar, 49);
      expect(OverviewCounts.buckets.map(c.countOf), [36, 6, 4, 3, 4, 1]);
      expect(c.countOf('nonsense'), 0);
    });

    test('totals are computed when the server leaves them out', () {
      final c = OverviewCounts.fromJson({
        'on_time': 10,
        'late': 2,
        'not_in_yet': 3,
        'no_check_in': 1,
        'on_leave': 2,
        'off_today': 1,
      });
      expect(c.checkedIn, isNull);
      expect(c.totalCheckedIn, 12);
      expect(c.totalTracked, 19);
      expect(c.totalExpected, 16);
      expect(OverviewCounts.fromJson(const {}).totalExpected, 0);
    });

    test("who's out today and next 7 days", () {
      final w = TeamOverview.fromJson(overviewSample()).whoOut!;
      final lina = w.today.first;
      expect(lina.id, 31);
      expect(lina.name, 'Lina Koh');
      expect(lina.initials, 'LK');
      expect(lina.department, 'Fabric');
      expect(lina.type, isNull);
      expect(lina.isPending, isFalse);
      expect(lina.part, isNull);
      expect(lina.until, DateTime(2026, 10, 23));
      expect(lina.backAt, isNull);
      expect(lina.tracked, isFalse);
      final ahmad = w.today.last;
      expect(ahmad.type, 'Sick Leave');
      expect(ahmad.isPending, isTrue);
      expect(ahmad.part, 'morning');
      expect(ahmad.backAt, '13:30');
      expect(ahmad.tracked, isTrue);
      expect(w.next7.single.date, DateTime(2026, 10, 23));
      final priya = w.next7.single.people.single;
      expect(priya.name, 'Priya Nair');
      expect(priya.department, 'Marketing');
      expect(priya.initials, '');
      expect(priya.tracked, isFalse); // no key = not tappable
    });

    test('for_you reuses ForYouItem and drops unknown kinds', () {
      final o = TeamOverview.fromJson(overviewSample());
      expect(o.forYou.single.kind, 'leave_approvals');
      expect(o.forYou.single.count, 2);
    });
  });

  group('TeamOverview.fromJson — yesterday', () {
    test('reviewed counts replace counts', () {
      final o = TeamOverview.fromJson(yesterdaySample());
      expect(o.day, 'yesterday');
      expect(o.live, isFalse);
      expect(o.counts, isNull);
      expect(o.whoOut, isNull);
      expect(o.names, isFalse);
      expect(o.scope.departmentId, 5);
      final r = o.reviewed!;
      expect(r.date, DateTime(2026, 10, 21));
      expect(r.provisional, isFalse);
      expect(r.onTime, 43);
      expect(r.lateCount, 4);
      expect(r.leftEarly, 2);
      expect(r.absent, 1);
      expect(r.onLeave, 3);
      expect(r.off, 1);
      expect(r.notReviewed, 0);
      expect(r.totalWorked, 47);
      expect(r.totalExpected, 50);
      expect(r.totalTracked, 54);
      expect(ReviewedDay.buckets.map(r.countOf), [43, 4, 2, 1, 3, 1]);
    });

    test('not_reviewed is read and stays inside expected', () {
      final r = ReviewedDay.fromJson({
        'provisional': true,
        'counts': {
          'on_time': 40,
          'late': 4,
          'left_early': 2,
          'absent': 1,
          'on_leave': 3,
          'off': 1,
          'not_reviewed': 3,
        },
      });
      expect(r.notReviewed, 3);
      expect(r.countOf('not_reviewed'), 3);
      expect(ReviewedDay.buckets, isNot(contains('not_reviewed')));
      // expected = worked + absent + not_reviewed = tracked − on_leave − off.
      expect(r.totalWorked, 46);
      expect(r.totalTracked, 54);
      expect(r.totalExpected, 50);
      expect(r.totalExpected, r.totalWorked + r.absent + r.notReviewed);
    });

    test('provisional is read', () {
      expect(
          TeamOverview.fromJson(yesterdaySample(provisional: true))
              .reviewed!
              .provisional,
          isTrue);
    });

    test('reviewed totals are computed when left out', () {
      final r = ReviewedDay.fromJson({
        'counts': {
          'on_time': 5,
          'late': 1,
          'left_early': 1,
          'absent': 1,
          'on_leave': 1,
          'off': 1,
        },
      });
      expect(r.totalWorked, 7);
      expect(r.totalTracked, 10);
      expect(r.totalExpected, 8);
      expect(r.provisional, isFalse);
      expect(r.date, isNull);
    });
  });

  group('TeamOverview.fromJson — sections and missing keys', () {
    test('attendance off: counts null, leave only', () {
      // Connector 2.65.0 answers feature_unavailable without Attendance
      // (A-L24) and never sends this shape; the parse stays tolerant.
      final o = TeamOverview.fromJson({
        ...overviewSample(),
        'sections': {'attendance': false, 'leave': true},
        'counts': null,
      });
      expect(o.counts, isNull);
      expect(o.sections.attendance, isFalse);
      expect(o.sections.leave, isTrue);
      expect(o.whoOut, isNotNull);
    });

    test('time off off: who_out null, attendance only', () {
      final o = TeamOverview.fromJson({
        ...overviewSample(),
        'sections': {'attendance': true, 'leave': false},
        'who_out': null,
      });
      expect(o.whoOut, isNull);
      expect(o.sections.leave, isFalse);
      expect(o.counts, isNotNull);
    });

    test('no sections key: follows what was sent', () {
      final body = overviewSample()
        ..remove('sections')
        ..['who_out'] = null;
      final o = TeamOverview.fromJson(body);
      expect(o.sections.attendance, isTrue);
      expect(o.sections.leave, isFalse);
    });

    test('an empty map gives safe defaults', () {
      final o = TeamOverview.fromJson(const {});
      expect(o.day, 'today');
      expect(o.date, isNull);
      expect(o.asOf, '');
      expect(o.live, isFalse);
      expect(o.scope.access, '');
      expect(o.scope.label, '');
      expect(o.scope.emptyReason, isNull);
      expect(o.departments, isEmpty);
      expect(o.sections.attendance, isFalse);
      expect(o.sections.leave, isFalse);
      expect(o.names, isFalse); // counts only unless the server says names
      expect(o.counts, isNull);
      expect(o.reviewed, isNull);
      expect(o.whoOut, isNull);
      expect(o.forYou, isEmpty);
    });

    test('scope empty_reason and odd part values', () {
      final o = TeamOverview.fromJson({
        'scope': {'access': 'department', 'label': '', 'empty_reason': 'no_department'},
        'who_out': {
          'today': [
            {'id': 1, 'name': 'X', 'part': 'evening', 'until': 'friday'},
          ],
          'next_7': [
            {'people': []},
          ],
        },
      });
      expect(o.scope.emptyReason, 'no_department');
      expect(o.whoOut!.today.single.part, isNull);
      expect(o.whoOut!.today.single.until, isNull);
      expect(o.whoOut!.today.single.state, 'approved');
      expect(o.whoOut!.next7, isEmpty);
      expect(o.whoOut!.truncated, isFalse); // no key = complete
    });

    test('who_out.truncated is read; only a real true counts', () {
      expect(
          TeamOverview.fromJson({
            'who_out': {'today': [], 'next_7': [], 'truncated': true},
          }).whoOut!.truncated,
          isTrue);
      expect(
          TeamOverview.fromJson({
            'who_out': {'today': [], 'next_7': [], 'truncated': 'true'},
          }).whoOut!.truncated,
          isFalse);
    });
  });

  group('OverviewPage.fromJson', () {
    test('the contract sample', () {
      final p = OverviewPage.fromJson({
        'success': true,
        'bucket': 'late',
        'total': 6,
        'next_offset': null,
        'rows': [
          {
            'id': 40,
            'name': 'Jason Lee',
            'initials': 'JL',
            'department': 'Marketing',
            'you': false,
            'bucket': 'late',
            'first_in': '08:58',
            'late_minutes': 28,
            'shift': {'start': '08:30', 'end': '17:30'},
            'minutes_since_start': null,
            'starts_in_min': null,
            'later_today': false,
            'flexible': false,
            'source': 'mobile',
            'kiosk_name': null,
            'location': null,
            'note': null,
            'leave': null,
          },
        ],
      });
      expect(p.bucket, 'late');
      expect(p.total, 6);
      expect(p.nextOffset, isNull);
      expect(p.hasMore, isFalse);
      final r = p.rows.single;
      expect(r.id, 40);
      expect(r.name, 'Jason Lee');
      expect(r.initials, 'JL');
      expect(r.department, 'Marketing');
      expect(r.you, isFalse);
      expect(r.bucket, 'late');
      expect(r.firstIn, '08:58');
      expect(r.lateMinutes, 28);
      expect(r.shift!.start, '08:30');
      expect(r.shift!.end, '17:30');
      expect(r.shift!.label, '08:30 – 17:30');
      expect(r.shift!.blocks, isEmpty);
      expect(r.minutesSinceStart, isNull);
      expect(r.startsInMin, isNull);
      expect(r.laterToday, isFalse);
      expect(r.flexible, isFalse);
      expect(r.source, 'mobile');
      expect(r.kioskName, isNull);
      expect(r.location, isNull);
      expect(r.note, isNull);
      expect(r.leave, isNull);
    });

    test('kiosk source, a note, a leave and the next page', () {
      final p = OverviewPage.fromJson({
        'bucket': 'not_in_yet',
        'total': 120,
        'next_offset': 50,
        'rows': [
          {
            'id': 41,
            'name': 'Siti',
            'bucket': 'not_in_yet',
            'first_in': null,
            'shift': {'start': '09:30', 'end': '18:30'},
            'starts_in_min': 18,
            'minutes_since_start': null,
            'source': 'kiosk',
            'kiosk_name': 'Lobby kiosk',
            'location': 'HQ',
            'note': {'kind': 'part_day_leave'},
            'leave': {
              'type': null,
              'state': 'approved',
              'part': 'morning',
              'back_at': '13:30',
              'until': null,
            },
          },
          'junk',
        ],
      });
      expect(p.hasMore, isTrue);
      expect(p.nextOffset, 50);
      final r = p.rows.single;
      expect(r.firstIn, isNull);
      expect(r.startsInMin, 18);
      expect(r.source, 'kiosk');
      expect(r.kioskName, 'Lobby kiosk');
      expect(r.location, 'HQ');
      expect(r.note, 'part_day_leave');
      expect(r.leave!.part, 'morning');
      expect(r.leave!.backAt, '13:30');
      expect(r.leave!.type, isNull);
      expect(r.leave!.until, isNull);
    });

    test('missing keys', () {
      final p = OverviewPage.fromJson(const {});
      expect(p.bucket, '');
      expect(p.total, 0);
      expect(p.rows, isEmpty);
      expect(p.hasMore, isFalse);
      final r = OverviewRow.fromJson(const {});
      expect(r.lateMinutes, 0);
      expect(r.shift, isNull);
      expect(r.source, '');
    });
  });

  group('OverviewPerson.fromJson', () {
    Map<String, dynamic> person() => {
          'success': true,
          'person': {
            'id': 40,
            'name': 'Jason Lee',
            'initials': 'JL',
            'department': 'Marketing',
            'calendar': 'Standard 44 hours/week',
            'you': false,
          },
          'today': {'bucket': 'late', 'late_minutes': 28, 'note': null},
          'shift': {
            'start': '08:30',
            'end': '17:30',
            'blocks': [
              {'start': '08:30', 'end': '12:30'},
              {'start': '13:30', 'end': '17:30'},
            ],
          },
          'punches': [
            {
              'at': '08:58',
              'kind': 'check_in',
              'source': 'mobile',
              'kiosk_name': null,
              'location': null,
            },
          ],
          'leave_week': [
            {
              'date_from': '2026-10-27',
              'date_to': '2026-10-28',
              'from_period': null,
              'to_period': null,
              'hour_from': 0.0,
              'hour_to': 0.0,
              'unit': 'day',
              'state': 'approved',
              'type': null,
            },
          ],
          'sections': {'attendance': true, 'leave': true},
        };

    test('the contract sample', () {
      final p = OverviewPerson.fromJson(person());
      expect(p.id, 40);
      expect(p.name, 'Jason Lee');
      expect(p.initials, 'JL');
      expect(p.department, 'Marketing');
      expect(p.calendar, 'Standard 44 hours/week');
      expect(p.you, isFalse);
      expect(p.bucket, 'late');
      expect(p.lateMinutes, 28);
      expect(p.note, isNull);
      expect(p.shift!.label, '08:30 – 17:30');
      expect(p.shift!.blocks.map((b) => b.label),
          ['08:30 – 12:30', '13:30 – 17:30']);
      final punch = p.punches.single;
      expect(punch.at, '08:58');
      expect(punch.kind, 'check_in');
      expect(punch.source, 'mobile');
      expect(punch.kioskName, isNull);
      expect(punch.location, isNull);
      final leave = p.leaveWeek!.single;
      expect(leave.dateFrom, DateTime(2026, 10, 27));
      expect(leave.dateTo, DateTime(2026, 10, 28));
      expect(p.sections.attendance, isTrue);
      expect(p.sections.leave, isTrue);
    });

    test('time off off: leave_week null; no shift; a note', () {
      final body = person()
        ..['leave_week'] = null
        ..['shift'] = null
        ..['today'] = {
          'bucket': 'on_time',
          'late_minutes': 0,
          'note': {'kind': 'came_in_on_leave'},
        }
        ..['sections'] = {'attendance': true, 'leave': false};
      final p = OverviewPerson.fromJson(body);
      expect(p.leaveWeek, isNull);
      expect(p.shift, isNull);
      expect(p.note, 'came_in_on_leave');
      expect(p.sections.leave, isFalse);
    });

    test('an empty leave week is an empty list, not null', () {
      final p = OverviewPerson.fromJson(person()..['leave_week'] = []);
      expect(p.leaveWeek, isEmpty);
    });

    test('missing keys', () {
      final p = OverviewPerson.fromJson(const {});
      expect(p.id, 0);
      expect(p.name, '');
      expect(p.bucket, '');
      expect(p.shift, isNull);
      expect(p.punches, isEmpty);
      expect(p.leaveWeek, isNull);
      expect(p.sections.attendance, isFalse);
    });
  });
}
