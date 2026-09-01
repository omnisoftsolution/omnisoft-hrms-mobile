import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';

void main() {
  test('announcement kind + id hint', () {
    final n = NotificationRecord.fromJson({
      'id': 1,
      'kind': 'announcement',
      'title': 'Message from HR',
      'body': 'Contract ready',
      'payload': '{"announcement_id": 42, "announcement_kind": "direct_message"}',
      'read': false,
      'create_date': '2026-08-28 01:00:00',
    });
    expect(n.isAnnouncementKind, isTrue);
    expect(n.announcementIdHint, 42);
    expect(n.isLeaveKind, isFalse);
    expect(n.isExpenseKind, isFalse);
  });

  test('id hint tolerates string and missing payload', () {
    final s = NotificationRecord.fromJson({
      'id': 2, 'kind': 'announcement', 'title': 't', 'body': '',
      'payload': '{"announcement_id": "7"}', 'read': true,
    });
    expect(s.announcementIdHint, 7);
    final none = NotificationRecord.fromJson({
      'id': 3, 'kind': 'announcement', 'title': 't', 'body': '',
      'payload': '', 'read': true,
    });
    expect(none.announcementIdHint, isNull);
  });
}
