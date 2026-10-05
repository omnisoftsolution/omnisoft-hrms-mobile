import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/approval_item.dart';

Map<String, dynamic> sample([Map<String, dynamic> extra = const {}]) => {
      'id': 148,
      'employee': {'id': 51, 'name': 'Lim Say Puay', 'department': 'Accounts'},
      'leave_type': {'id': 74, 'name': 'Annual Leave'},
      'state': 'confirm',
      'validation_type': 'both',
      'request_date_from': '2026-10-06',
      'request_date_to': '2026-10-07',
      'request_unit_hours': false,
      'request_hour_from': 0.0,
      'request_hour_to': 0.0,
      'number_of_days': 2.0,
      'number_of_hours': 16.0,
      'duration_label': '2d',
      'step': 'manager_approval',
      'assigned_to_me': true,
      'has_attachment': false,
      'create_date': '2026-10-01 02:00:00',
      'can_approve': true,
      'can_refuse': true,
      ...extra,
    };

void main() {
  group('ApprovalItem', () {
    test('parses a pending item', () {
      final it = ApprovalItem.fromJson(sample());
      expect(it.id, 148);
      expect(it.employeeId, 51);
      expect(it.employeeName, 'Lim Say Puay');
      expect(it.department, 'Accounts');
      expect(it.leaveTypeName, 'Annual Leave');
      expect(it.state, 'confirm');
      expect(it.isPending, isTrue);
      expect(it.assignedToMe, isTrue);
      expect(it.canApprove, isTrue);
      expect(it.canRefuse, isTrue);
      expect(it.stepLabel, 'Your approval');
      expect(it.datesLabel, 'Tue 6 Oct – Wed 7 Oct');
      expect(it.durationLong, '2 days (16h)');
      expect(it.submittedLabel, startsWith('Submitted'));
    });

    test('step chip when the step is not mine', () {
      expect(ApprovalItem.fromJson(sample({'assigned_to_me': false})).stepLabel,
          'Manager approval');
      expect(
          ApprovalItem.fromJson(
              sample({'assigned_to_me': false, 'step': 'hr_approval'})).stepLabel,
          'HR approval');
    });

    test('single day, hour range and hour-unit duration', () {
      final oneDay =
          ApprovalItem.fromJson(sample({'request_date_to': '2026-10-06',
              'number_of_days': 1.0, 'number_of_hours': 8.0, 'duration_label': '1d'}));
      expect(oneDay.datesLabel, 'Tue 6 Oct');
      expect(oneDay.durationLong, '1 day (8h)');

      final hours = ApprovalItem.fromJson(sample({
        'request_date_to': '2026-10-06',
        'request_unit_hours': true,
        'request_hour_from': 13.5,
        'request_hour_to': 17.5,
        'number_of_days': 0.5,
        'number_of_hours': 4.0,
        'duration_label': '4h',
      }));
      expect(hours.datesLabel, 'Tue 6 Oct, 13:30 – 17:30');
      expect(hours.durationLong, '4h');
    });

    test('recent rows: outcome, approvers, reason, decided date', () {
      final r = ApprovalItem.fromJson(sample({
        'state': 'refuse',
        'can_approve': false,
        'can_refuse': false,
        'outcome': 'refused',
        'decided_at': '2026-09-10 10:00:00',
        'first_approver': {'id': 30, 'name': 'Christine Ng'},
        'second_approver': null,
        'refusal_reason': 'Month-end closing',
      }));
      expect(r.isPending, isFalse);
      expect(r.outcomeLabel, 'Refused');
      expect(r.refusalReason, 'Month-end closing');
      expect(r.firstApproverName, 'Christine Ng');
      expect(r.secondApproverName, '');
      expect(r.decidedLabel, 'Decided 10 Sep');
      expect(ApprovalItem.fromJson(sample({'outcome': 'approved'})).outcomeLabel,
          'Approved');
      expect(ApprovalItem.fromJson(sample({'outcome': 'waiting_hr'})).outcomeLabel,
          'Waiting for HR');
      expect(ApprovalItem.fromJson(sample()).outcomeLabel, '');
    });

    test('a sparse payload does not throw and cannot be acted on', () {
      final it = ApprovalItem.fromJson({'id': 1});
      expect(it.id, 1);
      expect(it.employeeName, '');
      expect(it.state, '');
      expect(it.isPending, isFalse);
      expect(it.canApprove, isFalse);
      expect(it.canRefuse, isFalse);
      expect(it.datesLabel, '');
      expect(it.durationLong, '');
      expect(it.submittedLabel, '');
      expect(it.decidedLabel, '');
    });

    test('Odoo false for empty values reads as empty', () {
      final it = ApprovalItem.fromJson(sample({
        'employee': {'id': 51, 'name': 'Lim Say Puay', 'department': false},
        'request_date_to': false,
        'create_date': false,
        'first_approver': false,
      }));
      expect(it.department, '');
      expect(it.dateTo, isNull);
      expect(it.datesLabel, 'Tue 6 Oct');
      expect(it.createDate, '');
      expect(it.firstApproverName, '');
    });
  });
}
