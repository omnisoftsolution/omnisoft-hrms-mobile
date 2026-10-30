import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/services/auto/auto_api.dart';
import 'package:omni_hr/services/auto/auto_event.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

final _event = AutoEvent(
  eventUid: 'a-0123456789abcdef01234567',
  kind: AutoKind.arrive,
  eventAt: DateTime.utc(2026, 10, 30, 1, 2, 3),
  latitude: 1.3,
  longitude: 103.8,
  accuracy: 12,
  isMocked: false,
  deviceId: 'dev-1',
  appVersion: '1.36.0',
  source: AutoSource.geofence,
);

AutoApi _api(
  Future<http.Response> Function(http.Request) handler, {
  String? autoKey,
  String? bearer,
  Duration timeout = const Duration(seconds: 30),
}) => AutoApi(
  baseUrl: 'https://example.test',
  db: 'testdb',
  autoKey: autoKey,
  bearer: bearer,
  client: MockClient(handler),
  timeout: timeout,
);

void main() {
  group('postEvent answers', () {
    test(
      '200 success -> AutoAccepted with state, reason, confirmAfter UTC',
      () async {
        final api = _api(
          (_) async => _json({
            'success': true,
            'state': 'waiting_wifi',
            'reason': 'wifi_mismatch',
            'confirm_after': '2026-10-30 01:32:03',
          }),
        );
        final r = await api.postEvent(_event);
        expect(r, isA<AutoAccepted>());
        r as AutoAccepted;
        expect(r.state, 'waiting_wifi');
        expect(r.reason, 'wifi_mismatch');
        expect(r.confirmAfter, DateTime.utc(2026, 10, 30, 1, 32, 3));
        expect(r.confirmAfter!.isUtc, isTrue);
      },
    );

    test('202 success -> AutoAccepted, optional fields null', () async {
      final api = _api(
        (_) async => _json({'success': true, 'state': 'checked_in'}, 202),
      );
      final r = await api.postEvent(_event) as AutoAccepted;
      expect(r.state, 'checked_in');
      expect(r.reason, isNull);
      expect(r.confirmAfter, isNull);
    });

    test('unparseable confirm_after is ignored, not fatal', () async {
      final api = _api(
        (_) async => _json({
          'success': true,
          'state': 'waiting_wifi',
          'confirm_after': 'soon',
        }),
      );
      final r = await api.postEvent(_event) as AutoAccepted;
      expect(r.confirmAfter, isNull);
    });

    test('409 busy_retry -> AutoRetry', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'busy_retry'}, 409),
      );
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('500 server_error -> AutoRetry', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'server_error'}, 500),
      );
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('503 -> AutoRetry', () async {
      final api = _api((_) async => http.Response('down', 503));
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('422 html -> AutoRetry', () async {
      final api = _api(
        (_) async => http.Response('<!doctype html><p>no</p>', 422),
      );
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('422 json -> AutoRetry', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'x'}, 422),
      );
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('200 non-JSON -> AutoRetry', () async {
      final api = _api((_) async => http.Response('<html>', 200));
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('200 JSON that is not an object -> AutoRetry', () async {
      final api = _api((_) async => http.Response('[1]', 200));
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('timeout -> AutoRetry', () async {
      final never = Completer<http.Response>();
      final api = _api(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('network error -> AutoRetry', () async {
      final api = _api((_) async => throw http.ClientException('no route'));
      expect(await api.postEvent(_event), isA<AutoRetry>());
    });

    test('400 invalid_event -> AutoFinal', () async {
      final api = _api(
        (_) async => _json({
          'success': false,
          'error': 'invalid_event',
          'field': 'kind',
        }, 400),
      );
      final r = await api.postEvent(_event);
      expect(r, isA<AutoFinal>());
      expect((r as AutoFinal).error, 'invalid_event');
    });

    test('400 invalid_request -> AutoFinal', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'invalid_request'}, 400),
      );
      expect(
        (await api.postEvent(_event) as AutoFinal).error,
        'invalid_request',
      );
    });

    test('404 no_employee_linked -> AutoFinal', () async {
      final api = _api(
        (_) async =>
            _json({'success': false, 'error': 'no_employee_linked'}, 404),
      );
      expect(
        (await api.postEvent(_event) as AutoFinal).error,
        'no_employee_linked',
      );
    });

    test('other 4xx (403) -> AutoFinal with the server code', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'not_enabled'}, 403),
      );
      expect((await api.postEvent(_event) as AutoFinal).error, 'not_enabled');
    });

    test('4xx without a code -> AutoFinal(http_<status>)', () async {
      final api = _api((_) async => http.Response('nope', 400));
      expect((await api.postEvent(_event) as AutoFinal).error, 'http_400');
    });

    for (final code in ['invalid_key', 'invalid_session', 'invalid_token']) {
      test('401 $code -> AutoKeyInvalid', () async {
        final api = _api(
          (_) async => _json({'success': false, 'error': code}, 401),
        );
        expect(await api.postEvent(_event), isA<AutoKeyInvalid>());
      });
    }

    test('401 non-JSON -> AutoKeyInvalid', () async {
      final api = _api((_) async => http.Response('', 401));
      expect(await api.postEvent(_event), isA<AutoKeyInvalid>());
    });

    test('200 feature_unavailable -> AutoFinal', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'feature_unavailable'}),
      );
      expect(
        (await api.postEvent(_event) as AutoFinal).error,
        'feature_unavailable',
      );
    });

    test('200 success:false with another error -> AutoFinal(error)', () async {
      final api = _api(
        (_) async => _json({'success': false, 'error': 'weird_thing'}),
      );
      expect((await api.postEvent(_event) as AutoFinal).error, 'weird_thing');
    });
  });

  group('postEvent request', () {
    test('URL, body, JSON content type', () async {
      late http.Request seen;
      final api = _api((req) async {
        seen = req;
        return _json({'success': true, 'state': 'checked_in'});
      }, autoKey: 'k-1');
      await api.postEvent(_event);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), startsWith('https://example.test/api/v1/'));
      expect(seen.url.path, '/api/v1/omni_mobile/attendance/auto/event');
      expect(seen.url.queryParameters['db'], 'testdb');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), _event.toBody());
    });

    test(
      'sends X-Omni-Auto-Key and no Authorization when a key is set',
      () async {
        late http.Request seen;
        final api = _api(
          (req) async {
            seen = req;
            return _json({'success': true, 'state': 'checked_in'});
          },
          autoKey: 'k-1',
          bearer: 'tok',
        );
        await api.postEvent(_event);
        expect(seen.headers['X-Omni-Auto-Key'], 'k-1');
        expect(seen.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('sends the bearer when no key is set', () async {
      late http.Request seen;
      final api = _api((req) async {
        seen = req;
        return _json({'success': true, 'state': 'checked_in'});
      }, bearer: 'tok');
      await api.postEvent(_event);
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers.containsKey('X-Omni-Auto-Key'), isFalse);
    });

    test('an empty key falls back to the bearer', () async {
      late http.Request seen;
      final api = _api(
        (req) async {
          seen = req;
          return _json({'success': true, 'state': 'checked_in'});
        },
        autoKey: '',
        bearer: 'tok',
      );
      await api.postEvent(_event);
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers.containsKey('X-Omni-Auto-Key'), isFalse);
    });
  });

  group('postStatus', () {
    test('posts the status body to /attendance/auto/status', () async {
      late http.Request seen;
      final api = _api((req) async {
        seen = req;
        return _json({'success': true});
      }, bearer: 'tok');
      final r = await api.postStatus(
        permission: 'always',
        enabled: true,
        platform: 'ios',
      );
      expect(r, isA<AutoAccepted>());
      expect(seen.url.path, '/api/v1/omni_mobile/attendance/auto/status');
      expect(seen.url.queryParameters['db'], 'testdb');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body), {
        'permission': 'always',
        'enabled': true,
        'platform': 'ios',
      });
    });

    test('works with the auto key too', () async {
      late http.Request seen;
      final api = _api((req) async {
        seen = req;
        return _json({'success': true});
      }, autoKey: 'k-1');
      await api.postStatus(
        permission: 'denied',
        enabled: false,
        platform: 'android',
      );
      expect(seen.headers['X-Omni-Auto-Key'], 'k-1');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('401 -> AutoKeyInvalid, 503 -> AutoRetry', () async {
      final a = _api(
        (_) async => _json({'success': false, 'error': 'invalid_key'}, 401),
      );
      expect(
        await a.postStatus(
          permission: 'always',
          enabled: true,
          platform: 'ios',
        ),
        isA<AutoKeyInvalid>(),
      );
      final b = _api((_) async => http.Response('x', 503));
      expect(
        await b.postStatus(
          permission: 'always',
          enabled: true,
          platform: 'ios',
        ),
        isA<AutoRetry>(),
      );
    });
  });

  test('an injected client is not closed by the api', () async {
    final client = _CountingClient();
    final api = AutoApi(
      baseUrl: 'https://example.test',
      db: 'd',
      autoKey: 'k',
      client: client,
    );
    await api.postEvent(_event);
    expect(client.closed, isFalse);
  });
}

class _CountingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('{"success":true,"state":"checked_in"}')),
        200,
        headers: {'content-type': 'application/json'},
      );

  @override
  void close() => closed = true;
}
