import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/models/push_prefs.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

/// Runs [run] with every `http.post` answered by [handler] (no network).
Future<T> withServer<T>(
  Future<http.Response> Function(http.Request request) handler,
  Future<T> Function() run,
) => http.runWithClient(run, () => MockClient(handler));

http.Response json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

OmniMobileApi api() =>
    OmniMobileApi(baseUrl: 'https://example.test', db: 'testdb', token: 'tok');

void main() {
  var signedOut = 0;

  setUp(() {
    signedOut = 0;
    OmniMobileApi.onInvalidSession = () => signedOut++;
  });

  tearDown(() => OmniMobileApi.onInvalidSession = null);

  test('pushRegister posts the FCM token and platform', () async {
    late http.Request seen;
    await withServer((req) async {
      seen = req;
      return json({'success': true});
    }, () => api().pushRegister('fcm-1', 'ios'));
    expect(seen.url.path, '/api/v1/omni_mobile/push/register');
    expect(seen.url.queryParameters['db'], 'testdb');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(seen.body), {'token': 'fcm-1', 'platform': 'ios'});
  });

  test('pushUnregister posts an empty body', () async {
    late http.Request seen;
    await withServer((req) async {
      seen = req;
      return json({'success': true});
    }, () => api().pushUnregister());
    expect(seen.url.path, '/api/v1/omni_mobile/push/unregister');
    expect(jsonDecode(seen.body), <String, dynamic>{});
  });

  test('pushUnregister on a revoked session does not sign the user out '
      'again (it runs inside clearSession)', () async {
    await expectLater(
      withServer(
        (_) async => json({'success': false, 'error': 'invalid_session'}, 401),
        () => api().pushUnregister(),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(signedOut, 0);
  });

  test('register, the prefs routes and notifications/get leave '
      'invalid_session to PushService (it signs out only for the current '
      'session)', () async {
    final calls = <Future<Object?> Function()>[
      () => api().pushRegister('fcm-1', 'android'),
      () => api().pushPrefsGet(),
      () => api().pushPrefsSet(['news']),
      () => api().notificationGet(41),
    ];
    for (final call in calls) {
      await expectLater(
        withServer(
          (_) async =>
              json({'success': false, 'error': 'invalid_session'}, 401),
          call,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errorCode,
            'code',
            'invalid_session',
          ),
        ),
      );
    }
    expect(signedOut, 0);
  });

  test('every other call still signs the user out on invalid_session', () async {
    await expectLater(
      withServer(
        (_) async => json({'success': false, 'error': 'invalid_session'}, 401),
        () => api().markNotificationsRead(ids: [41]),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(signedOut, 1);
  });

  test('pushPrefsGet parses the answer (unknown muted values dropped)', () async {
    late http.Request seen;
    final p = await withServer((req) async {
      seen = req;
      return json({
        'success': true,
        'push_available': true,
        'reminders_available': false,
        'muted': ['news', 7, 'approvals'],
      });
    }, () => api().pushPrefsGet());
    expect(seen.url.path, '/api/v1/omni_mobile/push/prefs/get');
    expect(p.pushAvailable, isTrue);
    expect(p.remindersAvailable, isFalse);
    expect(p.muted, {'news', 'approvals'});
  });

  test('pushPrefsSet sends the muted list and parses the answer', () async {
    late http.Request seen;
    final p = await withServer((req) async {
      seen = req;
      return json({
        'success': true,
        'push_available': true,
        'reminders_available': true,
        'muted': ['news'],
      });
    }, () => api().pushPrefsSet(['news']));
    expect(seen.url.path, '/api/v1/omni_mobile/push/prefs/set');
    expect(jsonDecode(seen.body), {
      'muted': ['news'],
    });
    expect(p.muted, {'news'});
  });

  test('PushPrefs: missing keys mean push is not available', () {
    final p = PushPrefs.fromJson({'success': true});
    expect(p.pushAvailable, isFalse);
    expect(p.remindersAvailable, isFalse);
    expect(p.muted, isEmpty);
  });

  test('notificationGet sends the id and parses one bell notice', () async {
    late http.Request seen;
    final n = await withServer((req) async {
      seen = req;
      return json({
        'success': true,
        'notification': {
          'id': 41,
          'kind': 'leave_approved',
          'title': 'Leave approved',
          'body': 'Your Annual Leave for 20 Oct was approved.',
          'payload': '{"leave_id": 12}',
          'read': false,
          'answered': false,
          'create_date': '2026-10-11 08:00:00',
        },
      });
    }, () => api().notificationGet(41));
    expect(seen.url.path, '/api/v1/omni_mobile/notifications/get');
    expect(jsonDecode(seen.body), {'id': 41});
    expect(n.id, 41);
    expect(n.isLeaveKind, isTrue);
    expect(n.leaveIdHint, 12);
  });

  test('notificationGet: 404 not_found throws not_found', () async {
    await expectLater(
      withServer(
        (_) async => json({'success': false, 'error': 'not_found'}, 404),
        () => api().notificationGet(41),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.errorCode, 'code', 'not_found'),
      ),
    );
  });
}
