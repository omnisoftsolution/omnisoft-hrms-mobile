import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';

NotificationRecord record(String kind, String payload) =>
    NotificationRecord.fromJson(
        {'id': 1, 'kind': kind, 'title': 't', 'payload': payload});

void main() {
  test('leave_approval_requested is an approval request for the approver', () {
    final n = record('leave_approval_requested',
        '{"leave_id": 148, "employee_name": "Lim Say Puay", "step": "manager_approval"}');
    expect(n.isApprovalRequestKind, isTrue);
    expect(n.isLeaveKind, isFalse);
    expect(n.isExpenseKind, isFalse);
    expect(n.leaveIdHint, 148);
    expect(n.snackActionLabel, 'Review');
  });

  test('leave_first_approved behaves like the other own-leave kinds', () {
    final n = record(
        'leave_first_approved', '{"leave_id": 9, "approver_name": "Christine Ng"}');
    expect(n.isLeaveKind, isTrue);
    expect(n.isApprovalRequestKind, isFalse);
    expect(n.leaveIdHint, 9);
    expect(n.snackActionLabel, 'VIEW');
  });

  test('existing kinds keep their action; system has none', () {
    expect(record('leave_approved', '{"leave_id": 1}').snackActionLabel, 'VIEW');
    expect(record('leave_refused', '{"leave_id": 1}').snackActionLabel, 'VIEW');
    expect(
        record('expense_approved', '{"expense_id": 1}').snackActionLabel, 'VIEW');
    expect(record('system', '{}').snackActionLabel, isNull);
    expect(record('attendance_query', '{}').snackActionLabel, isNull);
  });
}
