import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';

void main() {
  group('friendlyError', () {
    test('SECURITY: never leaks the database name or request URI', () {
      // This is the exact string a no-internet ClientException produced
      // in production (see the bug report screenshot). It embeds the host
      // and the db name in the URI.
      const leaky =
          'ClientException with SocketException: Software caused connection '
          'abort (OS Error: Software caused connection abort, errno = 103), '
          'address = www.omnisoftsolution.com, port = 52528, '
          'uri=https://www.omnisoftsolution.com//api/v1/omni_mobile/'
          'attendance/status?db=willy-omnisoft-omnisoft-prod-7353588';

      final msg = friendlyError(leaky);

      expect(msg.contains('db='), isFalse);
      expect(msg.contains('willy-omnisoft'), isFalse);
      expect(msg.contains('omnisoftsolution.com'), isFalse);
      expect(msg.contains('SocketException'), isFalse);
      expect(msg.contains('errno'), isFalse);
      expect(msg.contains('uri='), isFalse);
      // It should fall back to a generic, friendly message.
      expect(msg, 'Something went wrong. Please try again.');
    });

    test('maps the wrapped network_error code to a no-connection message',
        () {
      expect(
        friendlyError('network_error'),
        'No internet connection. Check your network and try again.',
      );
    });

    test('maps timeout to a friendly retry message', () {
      expect(friendlyError('timeout'), contains('taking too long'));
    });

    test('maps server_error without leaking HTML', () {
      expect(friendlyError('server_error'), contains('our end'));
    });

    test('maps a known attendance code', () {
      expect(
        friendlyError('outside_geofence'),
        'You are outside the allowed office location.',
      );
    });

    test('maps session expiry', () {
      expect(friendlyError('invalid_session'), contains('expired'));
    });

    test('strips the Exception: prefix for short safe codes', () {
      expect(friendlyError('Exception: already_checked_in'),
          'You are already checked in.');
    });

    test('a bare unknown safe code is surfaced as-is', () {
      // Forward-compatible: a new short snake_case server code shows
      // through rather than being hidden, so it is still diagnosable.
      expect(friendlyError('some_new_code'), 'some_new_code');
    });

    test('a long/space-containing unknown message is genericized', () {
      expect(
        friendlyError('Exception: Internal Server Error at line 4096 /var/log'),
        'Something went wrong. Please try again.',
      );
    });

    test('maps backdate_limit_exceeded to a past-date message', () {
      expect(
        friendlyError(Exception('backdate_limit_exceeded')),
        contains('past'),
      );
    });
  });
}
