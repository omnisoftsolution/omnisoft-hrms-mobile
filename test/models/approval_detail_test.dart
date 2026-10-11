import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/approval_detail.dart';

void main() {
  group('ApprovalDetail', () {
    test('parses header, note, attachments, balance and steps', () {
      final d = ApprovalDetail.fromJson({
        'id': 148,
        'employee': {
          'id': 51,
          'name': 'Lim Say Puay',
          'department': 'Accounts',
          'avatar_b64': 'QUJD',
          'resource_calendar': 'Standard 40 hours/week',
        },
        'leave_type': {'id': 74, 'name': 'Annual Leave'},
        'state': 'confirm',
        'validation_type': 'both',
        'request_date_from': '2026-10-06',
        'request_date_to': '2026-10-07',
        'number_of_days': 2.0,
        'number_of_hours': 16.0,
        'duration_label': '2d',
        'step': 'manager_approval',
        'assigned_to_me': true,
        'has_attachment': true,
        'can_approve': true,
        'can_refuse': true,
        'name': 'Family trip',
        'attachments': [
          {'id': 9, 'name': 'mc.pdf', 'mimetype': 'application/pdf', 'file_size': 2048}
        ],
        'balance_after': {'unit': 'day', 'total': 14.0, 'remaining': 10.0},
        'steps': [
          {
            'label': 'manager_approval',
            'status': 'current',
            'by': null,
            'at': null,
            'candidates': ['Christine Ng'],
          },
          {
            'label': 'hr_approval',
            'status': 'next',
            'by': null,
            'at': null,
            'candidates': ['Teoh Yit Ngoh', 'Wong Kin Loong'],
          },
        ],
      });
      expect(d.item.id, 148);
      expect(d.item.employeeName, 'Lim Say Puay');
      expect(d.item.canApprove, isTrue);
      expect(d.note, 'Family trip');
      expect(d.avatarB64, 'QUJD');
      expect(d.resourceCalendar, 'Standard 40 hours/week');
      expect(d.attachments.single.name, 'mc.pdf');
      expect(d.attachments.single.sizeLabel, '2KB');
      expect(d.balanceAfter!.label, '10 days left of 14');
      expect(d.steps, hasLength(2));
      expect(d.steps[0].title, 'Manager approval');
      expect(d.steps[0].isCurrent, isTrue);
      expect(d.steps[0].subtitle, 'Christine Ng');
      expect(d.steps[1].title, 'HR approval');
      expect(d.steps[1].subtitle, 'Teoh Yit Ngoh or Wong Kin Loong');
    });

    test('done and refused steps name who acted; hour balance', () {
      final d = ApprovalDetail.fromJson({
        'id': 1,
        'state': 'refuse',
        'validation_type': 'both',
        'balance_after': {'unit': 'hour', 'total': 112.0, 'remaining': 96.0},
        'steps': [
          {
            'label': 'manager_approval',
            'status': 'done',
            'by': null,
            'at': '2026-09-10 09:00:00',
            'candidates': ['Christine Ng'],
          },
          {
            'label': 'hr_approval',
            'status': 'refused',
            'by': {'id': 7, 'name': 'Teoh Yit Ngoh'},
            'at': '2026-09-10 09:00:00',
            'candidates': ['Time Off Officers'],
          },
        ],
      });
      expect(d.steps[0].isDone, isTrue);
      expect(d.steps[0].subtitle, 'Done');
      expect(d.steps[1].isRefused, isTrue);
      expect(d.steps[1].subtitle, 'Refused by Teoh Yit Ngoh');
      expect(d.balanceAfter!.label, '96h left of 112h');
    });

    test('a done step with a name shows the name', () {
      final s = ApprovalStep.fromJson({
        'label': 'manager_approval',
        'status': 'done',
        'by': {'id': 30, 'name': 'Christine Ng'},
        'at': '2026-09-10 09:00:00',
        'candidates': ['Christine Ng'],
      });
      expect(s.subtitle, 'Christine Ng');
    });

    test('half_day balance reads in days; no balance for non-allocation types', () {
      expect(
          ApprovalBalance.fromJson(
                  {'unit': 'half_day', 'total': 14.0, 'remaining': 9.5})!
              .label,
          '9.5 days left of 14');
      expect(ApprovalBalance.fromJson(null), isNull);
      expect(ApprovalBalance.fromJson(false), isNull);
    });

    test('exactly one day left uses the singular', () {
      expect(
          ApprovalBalance.fromJson(
                  {'unit': 'day', 'total': 14.0, 'remaining': 1.0})!
              .label,
          '1 day left of 14');
      expect(
          ApprovalBalance.fromJson(
                  {'unit': 'day', 'total': 14.0, 'remaining': 0.0})!
              .label,
          '0 days left of 14');
    });

    test('waiting_for titles the current step; other steps keep their titles',
        () {
      final d = ApprovalDetail.fromJson({
        'id': 148,
        'state': 'confirm',
        'validation_type': 'both',
        'waiting_for': {
          'role': 'manager',
          'names': ['Christine Ng'],
          'you': false,
        },
        'steps': [
          {
            'label': 'manager_approval',
            'status': 'current',
            'candidates': ['Christine Ng'],
          },
          {
            'label': 'hr_approval',
            'status': 'next',
            'candidates': ['Time Off Officers'],
          },
        ],
      });
      expect(d.item.waitingFor!.label, 'Waiting for Christine (manager)');
      expect(d.steps[0].title, 'Waiting for Christine (manager)');
      expect(d.steps[0].subtitle, 'Christine Ng');
      expect(d.steps[1].title, 'HR approval');
    });

    test('second step current and mine: "Your approval"', () {
      final d = ApprovalDetail.fromJson({
        'id': 149,
        'state': 'validate1',
        'validation_type': 'both',
        'waiting_for': {'role': 'hr', 'names': ['Herianto Ramli'], 'you': true},
        'steps': [
          {'label': 'manager_approval', 'status': 'done', 'candidates': []},
          {'label': 'hr_approval', 'status': 'current', 'candidates': []},
        ],
      });
      expect(d.steps[0].title, 'Manager approval');
      expect(d.steps[1].title, 'Your approval');
    });

    test('HR step without officers: "Waiting for HR"', () {
      final d = ApprovalDetail.fromJson({
        'id': 150,
        'state': 'confirm',
        'validation_type': 'hr',
        'waiting_for': {'role': 'hr', 'names': [], 'you': false},
        'steps': [
          {'label': 'hr_approval', 'status': 'current', 'candidates': []},
        ],
      });
      expect(d.steps.single.title, 'Waiting for HR');
    });

    test('a request that is no longer pending ignores waiting_for', () {
      final d = ApprovalDetail.fromJson({
        'id': 151,
        'state': 'refuse',
        'validation_type': 'manager',
        'waiting_for': {'role': 'manager', 'names': ['Kelvin Tan'], 'you': false},
        'steps': [
          {'label': 'manager_approval', 'status': 'current', 'candidates': []},
        ],
      });
      expect(d.steps.single.title, 'Manager approval');
    });

    test('a step parsed on its own has no waiting_for', () {
      final s = ApprovalStep.fromJson(
          {'label': 'hr_approval', 'status': 'current', 'candidates': []});
      expect(s.waitingFor, isNull);
      expect(s.title, 'HR approval');
    });

    test('a sparse payload does not throw', () {
      final d = ApprovalDetail.fromJson({'id': 1, 'state': 'confirm'});
      expect(d.note, '');
      expect(d.avatarB64, '');
      expect(d.attachments, isEmpty);
      expect(d.balanceAfter, isNull);
      expect(d.steps, isEmpty);
    });
  });
}
