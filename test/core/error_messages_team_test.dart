import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

String team(String code, {Map<String, dynamic>? data}) =>
    friendlyError(ApiException(code, data: data), context: ErrorContext.team);

void main() {
  group('friendlyError for team leave and Team overview', () {
    test('names_hidden and invalid_department, in any context', () {
      expect(friendlyError(ApiException('names_hidden')),
          "Counts only — your company doesn't show names here.");
      expect(team('names_hidden'), "Counts only — your company doesn't show names here.");
      expect(friendlyError(ApiException('invalid_department')),
          "That department isn't available any more.");
      expect(team('invalid_department'),
          "That department isn't available any more.");
    });

    test('not_allowed: approval words by default, access words for team', () {
      expect(friendlyError(ApiException('not_allowed')),
          "You can't approve this request.");
      expect(team('not_allowed'), 'You no longer have access to this view.');
    });

    test('not_found: the person sheet words for team only', () {
      expect(friendlyError(ApiException('not_found')),
          'This request no longer exists.');
      expect(team('not_found'), 'This person is no longer in your view.');
    });

    test('team context keeps the usual transport words (not add-phone ones)',
        () {
      expect(team('timeout'),
          'The server is taking too long to respond. Please try again.');
      expect(team('network_error'),
          'No internet connection. Check your network and try again.');
      expect(team('server_error', data: {'http_status': 404}),
          'Something went wrong on our end. Please try again in a moment.');
      expect(team('unknown_route'), 'unknown_route');
      expect(team('feature_unavailable'),
          "This feature isn't included in your company's plan. Ask HR.");
      expect(team('invalid_session'),
          'Your session has expired. Please log in again.');
    });

    test('team context leaves the other codes alone', () {
      for (final code in ['kiosk_only', 'state_changed']) {
        expect(team(code), friendlyError(ApiException(code)), reason: code);
      }
    });

    test('contract codes with no team words read as a server error, never '
        'raw (final review M2)', () {
      for (final code in [
        'database_error',
        'invalid_request',
        'no_employee_linked',
      ]) {
        expect(
          team(code),
          'Something went wrong on our end. Please try again in a moment.',
          reason: code,
        );
      }
    });

    test('add-phone contexts are unchanged', () {
      expect(
          friendlyError(ApiException('not_allowed'),
              context: ErrorContext.addPhone),
          "You can't approve this request.");
      expect(
          friendlyError(ApiException('server_error', data: {'http_status': 404}),
              context: ErrorContext.addPhone),
          "Adding a phone isn't available for your company yet. Ask HR.");
    });
  });
}
