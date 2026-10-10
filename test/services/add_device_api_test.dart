import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

/// Runs [run] with every `http.post` answered by [handler] (no network).
Future<T> withServer<T>(
  Future<http.Response> Function(http.Request request) handler,
  Future<T> Function() run,
) =>
    http.runWithClient(run, () => MockClient(handler));

http.Response json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Unauthenticated client, as AddPhoneScreen builds it.
OmniMobileApi anon() =>
    OmniMobileApi(baseUrl: 'https://example.test', db: 'testdb', token: '');

Future<ApiException> failWith(String code, int status,
    [Map<String, dynamic> extra = const {}]) async {
  try {
    await withServer(
        (_) async => json({'success': false, 'error': code, ...extra}, status),
        () => anon().addDevice(
            login: 'budi.s', token: 'T', password: 'pw', deviceId: 'd'));
  } on ApiException catch (e) {
    return e;
  }
  fail('addDevice did not throw for $code');
}

void main() {
  test('addDevice posts the body to auth/add_device without an auth header',
      () async {
    late http.Request seen;
    final res = await withServer((req) async {
      seen = req;
      return json({
        'success': true,
        'access_token': 'A',
        'refresh_token': 'R',
        'auth_source': 'omni',
      });
    },
        () => anon().addDevice(
              login: ' Budi.S ',
              code: '123456',
              password: 'pw',
              deviceId: 'd',
              deviceLabel: 'Pixel 8',
              appVersion: '1.32.0',
            ));
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/v1/omni_mobile/auth/add_device');
    expect(seen.url.queryParameters['db'], 'testdb');
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(seen.body), {
      'login': 'budi.s',
      'code': '123456',
      'password': 'pw',
      'device_id': 'd',
      'device_label': 'Pixel 8',
      'app_version': '1.32.0',
    });
    expect(res['access_token'], 'A');
    expect(res['refresh_token'], 'R');
  });

  for (final (code, status, text) in [
    (
      'invalid_code',
      401,
      'That add-phone code is not right or has expired. Ask HR for a new one.'
    ),
    ('invalid_credentials', 401, 'Invalid login or password.'),
    (
      'not_active',
      409,
      'Your Omni HR account is not active yet. Activate it with the invite '
          'from HR first.'
    ),
    ('mobile_not_enabled', 403,
        'Mobile attendance is not enabled for your profile.'),
  ]) {
    test('$code ($status) is an ApiException with words', () async {
      final e = await failWith(code, status);
      expect(e.errorCode, code);
      expect(friendlyError(e), text);
    });
  }

  test('account_locked (423) carries retry_after into the words', () async {
    final e = await failWith('account_locked', 423, {'retry_after': 120});
    expect(e.errorCode, 'account_locked');
    expect(friendlyError(e), 'Too many attempts. Try again in 2 minutes.');
  });

  group('older connector (2.61, no auth/add_device)', () {
    Future<ApiException> htmlAnswer(int status) async {
      try {
        await withServer(
            (_) async => http.Response('<!doctype html><p>nope</p>', status),
            () => anon().addDevice(
                login: 'budi.s', token: 'T', password: 'pw', deviceId: 'd'));
      } on ApiException catch (e) {
        return e;
      }
      fail('addDevice did not throw');
    }

    const unavailable =
        "Adding a phone isn't available for your company yet. Ask HR.";

    test('an HTML 404 is server_error carrying the status; add-phone words',
        () async {
      final e = await htmlAnswer(404);
      expect(e.errorCode, 'server_error');
      expect(e.data?['http_status'], 404);
      expect(friendlyAddPhoneError(e), unavailable);
      // Everywhere else the generic words stay.
      expect(friendlyError(e),
          'Something went wrong on our end. Please try again in a moment.');
    });

    test('a JSON unknown_route gets the same words', () async {
      final e = await failWith('unknown_route', 404);
      expect(friendlyAddPhoneError(e), unavailable);
    });

    test('an HTML 500 is a real failure, not "not available"', () async {
      final e = await htmlAnswer(500);
      expect(e.data?['http_status'], 500);
      expect(friendlyAddPhoneError(e),
          'Something went wrong on our end. Please try again in a moment.');
    });
  });

  group('friendlyAddPhoneError', () {
    test('mobile_not_enabled reads as app access, not attendance', () {
      expect(friendlyAddPhoneError(ApiException('mobile_not_enabled')),
          'App access is off for you. Ask HR.');
    });

    test('a lost answer after the post may hide an added phone', () {
      const text = 'If this phone was added, sign in with your app login '
          'and password. If not, try again.';
      expect(friendlyAddPhoneError(ApiException('timeout')), text);
      expect(friendlyAddPhoneError(ApiException('network_error')), text);
    });

    test('before the post (company lookup) the usual network words stay', () {
      expect(
          friendlyAddPhoneError(ApiException('network_error'),
              requestSent: false),
          'No internet connection. Check your network and try again.');
      expect(
          friendlyAddPhoneError(
              ApiException('server_error', data: {'http_status': 404}),
              requestSent: false),
          'Something went wrong on our end. Please try again in a moment.');
    });

    test('other codes fall through to friendlyError', () {
      expect(friendlyAddPhoneError(ApiException('invalid_code')),
          friendlyError(ApiException('invalid_code')));
      expect(friendlyAddPhoneError(ApiException('not_active')),
          friendlyError(ApiException('not_active')));
    });
  });
}
