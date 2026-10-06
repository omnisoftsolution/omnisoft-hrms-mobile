import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

OmniMobileApi api() =>
    OmniMobileApi(baseUrl: 'https://example.test', db: 'testdb', token: 'tok');

const row = <String, dynamic>{
  'id': 148,
  'employee': {'id': 51, 'name': 'Lim Say Puay', 'department': 'Accounts'},
  'leave_type': {'id': 74, 'name': 'Annual Leave'},
  'state': 'confirm',
  'assigned_to_me': true,
  'can_approve': true,
  'can_refuse': true,
};

void main() {
  test('request bodies', () {
    expect(buildApproveBody(leaveId: 148, expectedState: 'confirm'),
        {'leave_id': 148, 'expected_state': 'confirm'});
    expect(
        buildRefuseBody(
            leaveId: 148, expectedState: 'validate1', reason: '  Coverage  '),
        {'leave_id': 148, 'expected_state': 'validate1', 'reason': 'Coverage'});
  });

  test('getPendingApprovals posts to the pending route and parses items',
      () async {
    late http.Request seen;
    final items = await withServer((req) async {
      seen = req;
      return json({'success': true, 'items': [row]});
    }, () => api().getPendingApprovals());
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/v1/omni_mobile/leave/approvals/pending');
    expect(seen.url.queryParameters['db'], 'testdb');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(seen.body), <String, dynamic>{});
    expect(items.single.id, 148);
    expect(items.single.employeeName, 'Lim Say Puay');
  });

  test('getRecentApprovals posts to the recent route; missing items is empty',
      () async {
    late http.Request seen;
    final items = await withServer((req) async {
      seen = req;
      return json({'success': true});
    }, () => api().getRecentApprovals());
    expect(seen.url.path, '/api/v1/omni_mobile/leave/approvals/recent');
    expect(items, isEmpty);
  });

  test('getApprovalDetail sends leave_id and parses the leave', () async {
    late http.Request seen;
    final d = await withServer((req) async {
      seen = req;
      return json({
        'success': true,
        'leave': {...row, 'name': 'Family trip', 'steps': [], 'attachments': []},
      });
    }, () => api().getApprovalDetail(148));
    expect(seen.url.path, '/api/v1/omni_mobile/leave/approvals/get');
    expect(jsonDecode(seen.body), {'leave_id': 148});
    expect(d.item.id, 148);
    expect(d.note, 'Family trip');
  });

  test('approveLeave sends expected_state and returns the new state',
      () async {
    late http.Request seen;
    final state = await withServer((req) async {
      seen = req;
      return json({'success': true, 'leave_id': 148, 'state': 'validate1'});
    }, () => api().approveLeave(leaveId: 148, expectedState: 'confirm'));
    expect(seen.url.path, '/api/v1/omni_mobile/leave/approvals/approve');
    expect(jsonDecode(seen.body), {'leave_id': 148, 'expected_state': 'confirm'});
    expect(state, 'validate1');
  });

  test('refuseLeave sends the trimmed reason and returns the new state',
      () async {
    late http.Request seen;
    final state = await withServer((req) async {
      seen = req;
      return json({'success': true, 'leave_id': 148, 'state': 'refuse'});
    },
        () => api().refuseLeave(
            leaveId: 148, expectedState: 'confirm', reason: ' Month-end '));
    expect(seen.url.path, '/api/v1/omni_mobile/leave/approvals/refuse');
    expect(jsonDecode(seen.body),
        {'leave_id': 148, 'expected_state': 'confirm', 'reason': 'Month-end'});
    expect(state, 'refuse');
  });

  test('state_changed (409) surfaces the code, state and decided_by', () async {
    final call = withServer(
        (req) async => json({
              'success': false,
              'error': 'state_changed',
              'state': 'validate',
              'decided_by': 'Teoh Yit Ngoh',
            }, 409),
        () => api().approveLeave(leaveId: 148, expectedState: 'confirm'));
    await expectLater(
        call,
        throwsA(isA<ApiException>()
            .having((e) => e.errorCode, 'errorCode', 'state_changed')
            .having((e) => e.data?['state'], 'state', 'validate')
            .having((e) => e.data?['decided_by'], 'decided_by', 'Teoh Yit Ngoh')));
  });

  test('not_allowed (403), reason_required (400) and not_found (404)',
      () async {
    Future<void> expectCode(String code, int status, Future<Object?> Function() run) =>
        expectLater(
            withServer(
                (req) async => json({'success': false, 'error': code}, status), run),
            throwsA(isA<ApiException>()
                .having((e) => e.errorCode, 'errorCode', code)));
    await expectCode('not_allowed', 403,
        () => api().approveLeave(leaveId: 1, expectedState: 'confirm'));
    await expectCode('reason_required', 400,
        () => api().refuseLeave(leaveId: 1, expectedState: 'confirm', reason: 'x'));
    await expectCode('not_found', 404, () => api().getApprovalDetail(1));
  });

  test('an old connector without the routes (HTML 404) is a server_error',
      () async {
    final call = withServer(
        (req) async => http.Response('<html>Not Found</html>', 404),
        () => api().getPendingApprovals());
    await expectLater(
        call,
        throwsA(isA<ApiException>()
            .having((e) => e.errorCode, 'errorCode', 'server_error')));
  });
}
