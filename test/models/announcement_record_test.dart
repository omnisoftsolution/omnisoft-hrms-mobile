// test/models/announcement_record_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/announcement_record.dart';

void main() {
  group('AnnouncementRecord parsing', () {
    test('new-server payload', () {
      final r = AnnouncementRecord.fromJson({
        'id': 5,
        'name': 'Holiday notice',
        'body': 'Collective leave Dec 25',
        'kind': 'direct_message',
        'priority': 'urgent',
        'date_start': '2026-12-22 06:00:00',
        'date_end': '2027-01-02 23:59:00',
        'has_image': true,
        'acked': false,
      });
      expect(r.id, 5);
      expect(r.isDirect, isTrue);
      expect(r.isUrgent, isTrue);
      expect(r.hasImage, isTrue);
      expect(r.acked, isFalse);
      expect(r.dateStart, isNotNull);
    });

    test('junk payload falls back safely', () {
      final r = AnnouncementRecord.fromJson({
        'id': '7', 'name': null, 'body': false, 'kind': 'weird',
        'priority': null, 'date_start': false, 'acked': 'yes',
      });
      expect(r.id, 7);
      expect(r.name, '');
      expect(r.body, '');
      expect(r.kind, 'announcement');
      expect(r.priority, 'normal');
      expect(r.dateStart, isNull);
      expect(r.acked, isFalse);
    });

    test('cache round-trip via toJson', () {
      final r = AnnouncementRecord.fromJson({
        'id': 9, 'name': 'N', 'body': 'B', 'kind': 'announcement',
        'priority': 'normal', 'date_start': '2026-01-01 00:00:00',
        'date_end': '2026-02-01 00:00:00', 'has_image': false,
        'acked': true,
      });
      final back = AnnouncementRecord.fromJson(r.toJson());
      expect(back.id, 9);
      expect(back.acked, isTrue);
      expect(back.dateEnd, r.dateEnd);
    });
  });

  group('AnnouncementListResult', () {
    test('parses list and survives missing key', () {
      final res = AnnouncementListResult.fromJson({
        'success': true,
        'announcements': [
          {'id': 1, 'name': 'A', 'body': 'x'},
        ],
      });
      expect(res.announcements.length, 1);
      final empty = AnnouncementListResult.fromJson({'success': true});
      expect(empty.announcements, isEmpty);
      final round =
          AnnouncementListResult.fromJson(res.toJson());
      expect(round.announcements.single.name, 'A');
    });
  });
}
