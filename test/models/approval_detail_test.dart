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
