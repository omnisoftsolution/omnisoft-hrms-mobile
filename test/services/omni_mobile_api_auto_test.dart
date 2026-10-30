import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

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
  test(
    'fetchAutoKey posts {} with the bearer and returns key + device id',
    () async {
      late http.Request seen;
      final r = await withServer((req) async {
        seen = req;
        return json({'success': true, 'key': 'abc', 'device_id': 'dev-1'});
      }, () => api().fetchAutoKey());
      expect(r.key, 'abc');
      expect(r.deviceId, 'dev-1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/omni_mobile/attendance/auto/key');
      expect(seen.url.queryParameters['db'], 'testdb');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body), <String, dynamic>{});
    },
  );

  test('403 not_enabled throws ApiException(not_enabled)', () async {
    await expectLater(
      withServer(
        (_) async => json({'success': false, 'error': 'not_enabled'}, 403),
        () => api().fetchAutoKey(),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.errorCode, 'code', 'not_enabled'),
      ),
    );
  });

  test(
    'device_required and feature_unavailable surface as ApiException',
    () async {
      for (final code in ['device_required', 'feature_unavailable']) {
        await expectLater(
          withServer(
            (_) async => json({'success': false, 'error': code}),
            () => api().fetchAutoKey(),
          ),
          throwsA(isA<ApiException>().having((e) => e.errorCode, 'code', code)),
        );
      }
    },
  );

  test('a reply without a key or device id is an ApiException', () async {
    await expectLater(
      withServer(
        (_) async => json({'success': true}),
        () => api().fetchAutoKey(),
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
