import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/my_day.dart';

import '../fixtures/my_day_fixture.dart';

void main() {
  group('MyDay.fromJson', () {
    test('parses the spec example', () {
      final day = MyDay.fromJson(sampleMyDayJson());
      expect(day.date, '2026-10-05');
      expect(day.tz, 'Asia/Jakarta');
      expect(day.kioskOnly, isTrue);
      expect(day.state, 'checked_in');
      expect(day.hoursToday, 3.2);
      expect(day.shift!.start, '2026-10-05 01:00:00');
      expect(day.shift!.end, '2026-10-05 10:00:00');
      expect(day.shift!.label, '08:00 – 17:00');
      expect(day.punches, hasLength(1));
      expect(day.punches.single.kind, 'check_in');
      expect(day.punches.single.at, '2026-10-05 00:54:00');
      expect(day.punches.single.source, 'kiosk');
      expect(day.punches.single.place, 'Produksi Lt. 1');
      expect(day.forYou.map((i) => i.kind),
          ['leave_approvals', 'my_leave', 'my_expense', 'payslip']);
    });

    test('parses what jsonDecode really returns', () {
      final decoded =
          jsonDecode(jsonEncode(sampleMyDayJson())) as Map<String, dynamic>;
      final day = MyDay.fromJson(decoded);
      expect(day.punches.single.place, 'Produksi Lt. 1');
      expect(day.forYou, hasLength(4));
    });

    test('for_you fields', () {
      final items = MyDay.fromJson(sampleMyDayJson()).forYou;
      expect(items[0].count, 3);
      expect(items[0].oldestAt, '2026-10-03 02:10:00');
      expect(items[1].id, 412);
      expect(items[1].state, 'confirm');
      expect(items[1].type, 'Annual leave');
      expect(items[1].dateFrom, '2026-10-12');
      expect(items[1].dateTo, '2026-10-13');
      expect(items[1].approver, 'Hendra Wijaya');
      expect(items[1].reason, '');
      expect(items[2].id, 88);
      expect(items[2].state, 'submitted');
      expect(items[2].name, 'Transport');
      expect(items[2].amount, 350000.0);
      expect(items[2].currency, 'IDR');
      expect(items[3].id, 51);
      expect(items[3].period, 'September 2026');
      expect(items[3].issuedOn, '2026-09-30');
    });

    test('unknown for_you kinds are dropped, known ones kept in order', () {
      final json = sampleMyDayJson();
      // Re-typed: the fixture literal infers List<Map<...>>, which rejects
      // the String below.
      final forYou = List<Object?>.from(json['for_you'] as List)
        ..insert(1, {'kind': 'late_mark', 'id': 7})
        ..add('not even a map');
      json['for_you'] = forYou;
      final day = MyDay.fromJson(json);
      expect(day.forYou.map((i) => i.kind),
          ['leave_approvals', 'my_leave', 'my_expense', 'payslip']);
    });

    test('null shift, no punches, empty for_you', () {
      final day = sampleMyDay(
          state: 'not_in', withShift: false, punches: [], forYou: []);
      expect(day.shift, isNull);
      expect(day.punches, isEmpty);
      expect(day.forYou, isEmpty);
      expect(day.state, 'not_in');
    });

    test('a body with nothing in it still parses', () {
      final day = MyDay.fromJson({'success': true});
      expect(day.date, '');
      expect(day.kioskOnly, isFalse);
      expect(day.state, 'not_in');
      expect(day.hoursToday, 0.0);
      expect(day.shift, isNull);
      expect(day.punches, isEmpty);
      expect(day.forYou, isEmpty);
    });

    test('Odoo false for a text field reads as empty', () {
      final day = sampleMyDay(punches: [
        {'kind': 'check_in', 'at': '2026-10-05 00:54:00', 'source': 'kiosk', 'place': false},
      ]);
      expect(day.punches.single.place, '');
    });

    test('parses the 2.52.0 keys', () {
      final day = MyDay.fromJson(sampleMyDayJson());
      expect(day.shift!.blocks.map((b) => b.label), ['08:00 – 12:00', '13:00 – 17:00']);
      expect(day.lunch!.label, '12:00 – 13:00');
      expect(day.breakExempt, isFalse);
      expect(day.lateMinutes, 0);
      expect(day.missing, isFalse);
      expect(day.off, isNull);
      expect(day.week.map((d) => d.kind), [
        'today', 'scheduled', 'scheduled', 'public_holiday', 'leave', 'off', 'off']);
      expect(day.week[3].name, 'Deepavali');
      expect(day.nextShift!.date, '2026-10-06');
    });

    test('2.51.0 body (no new keys) still parses with defaults', () {
      final json = sampleMyDayJson();
      final today = Map<String, dynamic>.from(json['today'] as Map)
        ..remove('lunch')
        ..remove('break_exempt')
        ..remove('late_minutes')
        ..remove('early_minutes')
        ..remove('overtime_minutes')
        ..remove('missing')
        ..remove('off');
      (today['shift'] as Map).remove('blocks');
      json['today'] = today;
      json.remove('week');
      json.remove('next_shift');
      final day = MyDay.fromJson(json);
      expect(day.shift!.blocks, isEmpty);
      expect(day.lunch, isNull);
      expect(day.lateMinutes, 0);
      expect(day.missing, isFalse);
      expect(day.week, isEmpty);
      expect(day.nextShift, isNull);
    });

    test('off and leave fields', () {
      final day = sampleMyDay(off: {
        'kind': 'leave', 'name': 'Annual leave',
        'date_from': '2026-10-05', 'date_to': '2026-10-06', 'back_on': '2026-10-08',
      }, withShift: false);
      expect(day.off!.kind, 'leave');
      expect(day.off!.backOn, '2026-10-08');
      final holiday = sampleMyDay(off: {'kind': 'public_holiday', 'name': 'X'});
      expect(holiday.off!.name, 'X');
      expect(holiday.off!.backOn, '');
    });
  });

  group('MyDayPunch labels', () {
    MyDayPunch punch(String kind, {String source = 'kiosk', String place = ''}) =>
        MyDayPunch.fromJson({
          'kind': kind,
          'at': '2026-10-05 00:54:00',
          'source': source,
          'place': place,
        });

    test('label per kind', () {
      expect(punch('check_in').label, 'Check in');
      expect(punch('break_start').label, 'Break start');
      expect(punch('break_end').label, 'Break end');
      expect(punch('check_out').label, 'Check out');
      expect(punch('something_new').label, 'something_new');
    });

    test('placeLabel prefers the place, then the source', () {
      expect(punch('check_in', place: 'Produksi Lt. 1').placeLabel,
          'Produksi Lt. 1');
      expect(punch('check_in').placeLabel, 'Kiosk');
      expect(punch('check_in', source: 'mobile').placeLabel, 'Phone');
      expect(punch('check_in', source: 'other').placeLabel, '');
    });
  });

  test('ForYouItem.isKnown', () {
    expect(const ForYouItem(kind: 'payslip').isKnown, isTrue);
    expect(const ForYouItem(kind: 'late_mark').isKnown, isFalse);
  });
}
