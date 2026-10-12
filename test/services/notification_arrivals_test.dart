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

  test('a notice a push tap opened is not handed over as an arrival (F1)', () {
    final svc = NotificationService();
    svc.suppressArrival(11);
    svc.queueArrivals([n(11, 'leave_approval_requested')], increase: 1);
    expect(svc.consumeFreshArrivals(), isEmpty);
    // A later notice still arrives.
    svc.queueArrivals(
        [n(12, 'leave_approved'), n(11, 'leave_approval_requested')],
        increase: 1);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [12]);
  });

  test('a suppressed notice still counts as one of the new ones: an older '
      'unread item does not take its place (F1)', () {
    final svc = NotificationService();
    svc.suppressArrival(11);
    svc.queueArrivals([n(11, 'leave_approved'), n(5, 'leave_refused')],
        increase: 1);
    expect(svc.consumeFreshArrivals(), isEmpty);

    final svc2 = NotificationService();
    svc2.suppressArrival(12);
    svc2.queueArrivals([n(12, 'leave_approved'), n(11, 'expense_approved')],
        increase: 2);
    expect(svc2.consumeFreshArrivals().map((e) => e.id), [11]);
  });

  test('a tapped notice already queued is dropped from the queue (F1)', () {
    final svc = NotificationService();
    svc.queueArrivals(
        [n(12, 'leave_approved'), n(11, 'attendance_query')], increase: 2);
    svc.suppressArrival(11);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [12]);
  });

  test('two polls before the host listens: both batches are kept', () {
    final svc = NotificationService();
    svc.queueArrivals([n(11, 'leave_approved')], increase: 1);
    svc.queueArrivals([n(12, 'expense_approved'), n(11, 'leave_approved')],
        increase: 1);
    expect(svc.consumeFreshArrivals().map((e) => e.id), [12, 11]);
  });
}
