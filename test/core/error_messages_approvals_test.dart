import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  group('friendlyError for leave approvals', () {
    test('not_allowed', () {
      expect(friendlyError(ApiException('not_allowed')),
          "You can't approve this request.");
    });

    test('state_changed names who approved', () {
      expect(
          friendlyError(ApiException('state_changed',
              data: {'state': 'validate', 'decided_by': 'Teoh Yit Ngoh'})),
          'Already approved by Teoh Yit Ngoh');
      expect(
          friendlyError(ApiException('state_changed',
              data: {'state': 'validate1', 'decided_by': 'Christine Ng'})),
          'Already approved by Christine Ng');
      expect(
          friendlyError(ApiException('state_changed',
              data: {'state': 'validate', 'decided_by': ''})),
          'Already approved');
    });

    test('state_changed for a refused or cancelled request', () {
      expect(
          friendlyError(ApiException('state_changed',
              data: {'state': 'refuse', 'decided_by': 'Teoh Yit Ngoh'})),
          'Already refused');
      expect(
          friendlyError(
              ApiException('state_changed', data: {'state': 'cancel'})),
          'This request was cancelled.');
      expect(friendlyError(ApiException('state_changed')),
          'This request has changed. Pull down to refresh.');
    });

    test('reason_required uses the server limits', () {
      expect(
          friendlyError(
              ApiException('reason_required', data: {'min': 3, 'max': 500})),
          'Write a reason of 3 to 500 characters.');
      expect(friendlyError(ApiException('reason_required')),
          'Write a reason of 3 to 500 characters.');
    });

    test('not_found and not_owner', () {
      expect(friendlyError(ApiException('not_found')),
          'This request no longer exists.');
      expect(friendlyError(ApiException('not_owner')),
          "You don't have access to this file.");
    });

    test('longer codes that contain a new code are not swallowed', () {
      expect(friendlyError(ApiException('face_reenrollment_not_allowed')),
          'face_reenrollment_not_allowed');
    });
  });

  group('friendlyDecisionError', () {
    test('shows an Odoo validation sentence as it is', () {
      const odoo = 'You cannot approve a time off that starts in a locked period.';
      expect(friendlyError(ApiException(odoo)),
          'Something went wrong. Please try again.');
      expect(friendlyDecisionError(ApiException(odoo)), odoo);
    });

    test('keeps the friendly text for known codes', () {
      expect(friendlyDecisionError(ApiException('network_error')),
          'No internet connection. Check your network and try again.');
      expect(friendlyDecisionError(ApiException('not_allowed')),
          "You can't approve this request.");
    });

    test('never shows text that could carry a URL or the database name', () {
      expect(
          friendlyDecisionError(
              ApiException('failed uri=https://x.test/api?db=secret-db')),
          'Something went wrong. Please try again.');
      expect(friendlyDecisionError('a plain string with spaces'),
          'Something went wrong. Please try again.');
    });
  });
}
