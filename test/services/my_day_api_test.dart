import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

OmniMobileApi _api() =>
    OmniMobileApi(baseUrl: 'https://tenant.test', db: 'tenantdb', token: 'tok');

/// Runs [body] against a fake server that answers every request with
/// [reply]; [seen] collects the requests.
Future<T> _withServer<T>(
  Future<T> Function() body, {
  required int status,
  required Map<String, dynamic> reply,
  List<http.Request>? seen,
}) =>
    http.runWithClient(
      body,
      () => MockClient((request) async {
        seen?.add(request);
        return http.Response(jsonEncode(reply), status,
            headers: {'content-type': 'application/json'});
      }),
    );

void main() {
  tearDown(() => OmniMobileApi.onKioskOnly = null);

  test('fetchMyDay posts to /home/my_day and parses the body', () async {
    final seen = <http.Request>[];
    final day = await _withServer(
      () => _api().fetchMyDay(),
      status: 200,
      seen: seen,
      reply: {
        'success': true,
        'date': '2026-10-05',
        'tz': 'Asia/Jakarta',
        'today': {
          'kiosk_only': true,
          'state': 'on_break',
          'hours_today': 4.1,
          'shift': null,
          'punches': [],
        },
        'for_you': [
          {'kind': 'payslip', 'id': 51, 'period': 'September 2026', 'issued_on': '2026-09-30'},
        ],
      },
    );
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/omni_mobile/home/my_day');
    expect(seen.single.url.queryParameters['db'], 'tenantdb');
    expect(seen.single.headers['Authorization'], 'Bearer tok');
    expect(day.state, 'on_break');
    expect(day.kioskOnly, isTrue);
    expect(day.forYou.single.kind, 'payslip');
  });

  test('a kiosk_only refusal calls onKioskOnly and still throws', () async {
    var calls = 0;
    OmniMobileApi.onKioskOnly = () => calls++;
    await expectLater(
      _withServer(
        () => _api().checkIn(),
        status: 403,
        reply: {'success': false, 'error': 'kiosk_only'},
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.errorCode, 'errorCode', 'kiosk_only')),
    );
    expect(calls, 1);
  });

  test('other errors do not call onKioskOnly', () async {
    var calls = 0;
    OmniMobileApi.onKioskOnly = () => calls++;
    await expectLater(
      _withServer(
        () => _api().checkIn(),
        status: 403,
        reply: {'success': false, 'error': 'mobile_not_enabled'},
      ),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 0);
  });
}
