import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/services/notification_service.dart';

NotificationRecord n(int id, String kind, {bool read = false}) =>
    NotificationRecord(id: id, kind: kind, title: '$kind $id', read: read);

void main() {
  test('every new arrival of a poll is handed over, newest first', () {
    final svc = NotificationService();
    // Server order: newest first. A leave decision came in, then an
    // expense update, before the next poll (count went up by 2).
    svc.queueArrivals([
      n(12, 'expense_approved'),
      n(11, 'leave_approved'),
      n(9, 'leave_refused', read: true),
      n(5, 'leave_approved'), // unread, but older than this poll
    ], increase: 2);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [12, 11]);
    // Consumed once.
    expect(svc.consumeFreshArrivals(), isEmpty);
  });

  test('an arrival already handed over is not handed over again', () {
    final svc = NotificationService();
    svc.queueArrivals([n(11, 'leave_approved')], increase: 1);
    svc.consumeFreshArrivals();
    svc.queueArrivals([n(11, 'leave_approved')], increase: 1);
    expect(svc.consumeFreshArrivals(), isEmpty);
    svc.queueArrivals([n(13, 'leave_refused'), n(11, 'leave_approved')],
        increase: 1);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [13]);
  });

  test('two polls before the host listens: both batches are kept', () {
    final svc = NotificationService();
    svc.queueArrivals([n(11, 'leave_approved')], increase: 1);
    svc.queueArrivals([n(12, 'expense_approved'), n(11, 'leave_approved')],
        increase: 1);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [12, 11]);
  });
}
