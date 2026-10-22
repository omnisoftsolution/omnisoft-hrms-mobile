import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

OmniMobileApi _api() =>
    OmniMobileApi(baseUrl: 'https://tenant.test', db: 'tenantdb', token: 'tok');

/// Runs [body] against a fake server answering [reply] as JSON with
/// [status]; [seen] collects the requests.
Future<T> _withServer<T>(
  Future<T> Function() body, {
  int status = 200,
  Map<String, dynamic> reply = const {'success': true},
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

/// An older connector: Odoo's HTML page for a route it does not have.
Future<T> _withHtml<T>(Future<T> Function() body, {required int status}) =>
    http.runWithClient(
      body,
      () => MockClient((request) async => http.Response(
            '<!doctype html><html><body>Not Found</body></html>',
            status,
            headers: {'content-type': 'text/html'},
          )),
    );

Map<String, dynamic> _body(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;

void _expectRoute(http.Request r, String route) {
  expect(r.method, 'POST');
  expect(r.url.path, '/api/v1/omni_mobile/$route');
  expect(r.url.queryParameters['db'], 'tenantdb');
  expect(r.headers['Authorization'], 'Bearer tok');
}

Future<ApiException> _caught(Future<void> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('request shapes', () {
    test('fetchTeamOutlook: defaults, no department_id key', () async {
      final seen = <http.Request>[];
      final o = await _withServer(
        () => _api().fetchTeamOutlook(),
        seen: seen,
        reply: {
          'success': true,
          'context': 'team',
          'view': 'team',
          'range': {'from': '2026-10-22', 'to': '2026-11-20', 'days': 30},
          'summary': {'this_week_off': 2, 'label': 'Marketing', 'faces': []},
        },
      );
      _expectRoute(seen.single, 'leave/team_outlook');
      expect(_body(seen.single),
          {'days': 30, 'context': 'team', 'view': 'team'});
      expect(o.rangeDays, 30);
      expect(o.summary.thisWeekOff, 2);
    });

    test('fetchTeamOutlook: overview context with a department', () async {
      final seen = <http.Request>[];
      await _withServer(
        () => _api().fetchTeamOutlook(
            days: 90, context: 'overview', departmentId: 5),
        seen: seen,
      );
      expect(_body(seen.single), {
        'days': 90,
        'context': 'overview',
        'view': 'team',
        'department_id': 5,
      });
    });

    test('fetchTeamOutlook: another view', () async {
      final seen = <http.Request>[];
      await _withServer(
        () => _api().fetchTeamOutlook(days: 60, view: 'approvees'),
        seen: seen,
      );
      expect(_body(seen.single),
          {'days': 60, 'context': 'team', 'view': 'approvees'});
    });

    test('fetchTeamOverlap sends plain dates', () async {
      final seen = <http.Request>[];
      final o = await _withServer(
        () => _api().fetchTeamOverlap(
            DateTime(2026, 11, 12, 15, 30), DateTime(2026, 11, 13)),
        seen: seen,
        reply: {
          'success': true,
          'people': [
            {'name': 'Rachel Wong', 'date_from': '2026-11-12', 'date_to': '2026-11-12'},
          ],
          'more': 0,
          'empty_reason': null,
        },
      );
      _expectRoute(seen.single, 'leave/team_overlap');
      expect(_body(seen.single),
          {'date_from': '2026-11-12', 'date_to': '2026-11-13'});
      expect(o.people.single.name, 'Rachel Wong');
    });

    test('fetchOverview: today, then yesterday with a department', () async {
      final seen = <http.Request>[];
      await _withServer(() => _api().fetchOverview(), seen: seen);
      await _withServer(
        () => _api().fetchOverview(day: 'yesterday', departmentId: 7),
        seen: seen,
      );
      _expectRoute(seen.first, 'home/overview');
      expect(_body(seen.first), {'day': 'today'});
      expect(_body(seen.last), {'day': 'yesterday', 'department_id': 7});
    });

    test('fetchOverview parses the answer', () async {
      final o = await _withServer(
        () => _api().fetchOverview(),
        reply: {
          'success': true,
          'day': 'today',
          'as_of': '09:12',
          'live': true,
          'names': true,
          'counts': {'on_time': 3, 'late': 1},
        },
      );
      expect(o.asOf, '09:12');
      expect(o.counts!.totalCheckedIn, 4);
      expect(o.raw['as_of'], '09:12');
    });

    test('fetchOverviewList: defaults, then a department and the next page',
        () async {
      final seen = <http.Request>[];
      final page = await _withServer(
        () => _api().fetchOverviewList(bucket: 'late'),
        seen: seen,
        reply: {
          'success': true,
          'bucket': 'late',
          'total': 6,
          'next_offset': null,
          'rows': [
            {'id': 40, 'name': 'Jason Lee', 'late_minutes': 28},
          ],
        },
      );
      await _withServer(
        () => _api().fetchOverviewList(
            bucket: 'not_in_yet', departmentId: 5, offset: 50, limit: 50),
        seen: seen,
      );
      _expectRoute(seen.first, 'home/overview/list');
      expect(_body(seen.first), {'bucket': 'late', 'offset': 0, 'limit': 50});
      expect(_body(seen.last), {
        'bucket': 'not_in_yet',
        'department_id': 5,
        'offset': 50,
        'limit': 50,
      });
      expect(page.total, 6);
      expect(page.rows.single.lateMinutes, 28);
    });

    test('fetchOverviewPerson', () async {
      final seen = <http.Request>[];
      final p = await _withServer(
        () => _api().fetchOverviewPerson(40),
        seen: seen,
        reply: {
          'success': true,
          'person': {'id': 40, 'name': 'Jason Lee'},
          'today': {'bucket': 'late', 'late_minutes': 28},
        },
      );
      _expectRoute(seen.single, 'home/overview/person');
      expect(_body(seen.single), {'employee_id': 40});
      expect(p.name, 'Jason Lee');
      expect(p.bucket, 'late');
    });
  });

  group('error mapping', () {
    test('403 not_allowed: access lost, not a missing route', () async {
      final e = await _caught(() => _withServer(
            () => _api().fetchOverview(),
            status: 403,
            reply: {'success': false, 'error': 'not_allowed'},
          ));
      expect(e.errorCode, 'not_allowed');
      expect(isAccessLost(e), isTrue);
      expect(isMissingRoute(e), isFalse);
    });

    test('403 names_hidden from the list: access lost', () async {
      final e = await _caught(() => _withServer(
            () => _api().fetchOverviewList(bucket: 'late'),
            status: 403,
            reply: {'success': false, 'error': 'names_hidden'},
          ));
      expect(e.errorCode, 'names_hidden');
      expect(isAccessLost(e), isTrue);
    });

    test('200 feature_unavailable: access lost', () async {
      final e = await _caught(() => _withServer(
            () => _api().fetchTeamOutlook(),
            reply: {'success': false, 'error': 'feature_unavailable'},
          ));
      expect(e.errorCode, 'feature_unavailable');
      expect(isAccessLost(e), isTrue);
    });

    test('400 invalid_department and 404 not_found are neither', () async {
      final bad = await _caught(() => _withServer(
            () => _api().fetchOverview(departmentId: 99),
            status: 400,
            reply: {'success': false, 'error': 'invalid_department'},
          ));
      expect(bad.errorCode, 'invalid_department');
      expect(isAccessLost(bad), isFalse);
      expect(isMissingRoute(bad), isFalse);

      final gone = await _caught(() => _withServer(
            () => _api().fetchOverviewPerson(41),
            status: 404,
            reply: {'success': false, 'error': 'not_found'},
          ));
      expect(gone.errorCode, 'not_found');
      expect(isAccessLost(gone), isFalse);
      expect(isMissingRoute(gone), isFalse);
    });

    test('an HTML 404 (connector before 2.65.0) is a missing route', () async {
      for (final call in <Future<void> Function()>[
        () => _api().fetchTeamOutlook(),
        () => _api().fetchTeamOverlap(DateTime(2026, 11, 12), DateTime(2026, 11, 12)),
        () => _api().fetchOverview(),
        () => _api().fetchOverviewList(bucket: 'late'),
        () => _api().fetchOverviewPerson(40),
      ]) {
        final e = await _caught(() => _withHtml(call, status: 404));
        expect(e.errorCode, 'server_error');
        expect(e.data?['http_status'], 404);
        expect(isMissingRoute(e), isTrue);
        expect(isAccessLost(e), isFalse);
      }
    });

    test('an HTML 500 is a real failure, not a missing route', () async {
      final e = await _caught(
          () => _withHtml(() => _api().fetchOverview(), status: 500));
      expect(e.errorCode, 'server_error');
      expect(isMissingRoute(e), isFalse);
    });

    test('a JSON unknown_route is a missing route', () async {
      final e = await _caught(() => _withServer(
            () => _api().fetchTeamOutlook(),
            status: 404,
            reply: {'success': false, 'error': 'unknown_route'},
          ));
      expect(isMissingRoute(e), isTrue);
    });

    test('anything that is not an ApiException is neither', () {
      expect(isMissingRoute(Exception('server_error')), isFalse);
      expect(isAccessLost('not_allowed'), isFalse);
      expect(isMissingRoute(ApiException('timeout')), isFalse);
      expect(isAccessLost(ApiException('network_error')), isFalse);
    });
  });
}
