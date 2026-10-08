import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

OmniMobileApi _api() =>
    OmniMobileApi(baseUrl: 'https://tenant.test', db: 'tenantdb', token: 'tok');

Future<T> _withServer<T>(
  Future<T> Function() body, {
  required Map<String, dynamic> reply,
  required List<http.Request> seen,
}) => http.runWithClient(
  body,
  () => MockClient((request) async {
    seen.add(request);
    return http.Response(
      jsonEncode(reply),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test('buildDeclareBody: UTC time, trimmed note, empty keys left out', () {
    expect(
      buildDeclareBody(
        attendanceId: 812,
        trigger: 'break_long',
        answerCode: 'back_at',
        declaredTime: DateTime.utc(2026, 10, 7, 5),
        note: '  bus  ',
      ),
      {
        'attendance_id': 812,
        'trigger': 'break_long',
        'answer_code': 'back_at',
        'declared_time': '2026-10-07 05:00:00',
        'note': 'bus',
      },
    );
    expect(
      buildDeclareBody(
        attendanceId: 812,
        trigger: 'break_long',
        answerCode: 'long_break',
      ),
      {
        'attendance_id': 812,
        'trigger': 'break_long',
        'answer_code': 'long_break',
      },
    );
    final local = DateTime.utc(2026, 10, 7, 5).toLocal();
    expect(
      buildDeclareBody(
        attendanceId: 1,
        trigger: 'yesterday',
        answerCode: 'left_at',
        declaredTime: local,
      )['declared_time'],
      '2026-10-07 05:00:00',
    );
  });

  test('declare posts to /attendance/declare and reports recorded', () async {
    final seen = <http.Request>[];
    final recorded = await _withServer(
      () => _api().declare(
        attendanceId: 812,
        trigger: 'late_first_in',
        answerCode: 'started_at',
        declaredTime: DateTime.utc(2026, 10, 7, 1),
      ),
      reply: {'success': true, 'recorded': true, 'day_id': 3},
      seen: seen,
    );
    expect(recorded, isTrue);
    expect(seen.single.url.path, '/api/v1/omni_mobile/attendance/declare');
    expect(jsonDecode(seen.single.body), {
      'attendance_id': 812,
      'trigger': 'late_first_in',
      'answer_code': 'started_at',
      'declared_time': '2026-10-07 01:00:00',
    });
  });

  test('undoPunch posts the id and parses the returned status', () async {
    final seen = <http.Request>[];
    final status = await _withServer(
      () => _api().undoPunch(812),
      reply: {
        'success': true,
        'undone': 'check_in',
        'status': {
          'success': true,
          'checked_in': false,
          'hours_today': 1.5,
          'employee_id': 4,
        },
      },
      seen: seen,
    );
    expect(seen.single.url.path, '/api/v1/omni_mobile/attendance/undo');
    expect(jsonDecode(seen.single.body), {'attendance_id': 812});
    expect(status.checkedIn, isFalse);
    expect(status.hoursToday, 1.5);
    expect(status.employeeId, 4);
  });

  test(
    'answerReview sends a corrected time as UTC (connector 2.55.0)',
    () async {
      final seen = <http.Request>[];
      await _withServer(
        () => _api().answerReview(
          notificationId: 22,
          answerCode: 'declared_change',
          time: DateTime.utc(2026, 10, 8, 0, 30),
        ),
        reply: {'success': true, 'day_id': 6, 'answer_code': 'declared_change'},
        seen: seen,
      );
      expect(jsonDecode(seen.single.body), {
        'notification_id': 22,
        'answer_code': 'declared_change',
        'time': '2026-10-08 00:30:00',
      });
    },
  );

  test('answerReview posts to the review/answer route', () async {
    final seen = <http.Request>[];
    await _withServer(
      () => _api().answerReview(
        notificationId: 21,
        answerCode: 'early',
        note: ' doctor ',
      ),
      reply: {'success': true, 'day_id': 5, 'answer_code': 'early'},
      seen: seen,
    );
    expect(
      seen.single.url.path,
      '/api/v1/omni_mobile/attendance/review/answer',
    );
    expect(jsonDecode(seen.single.body), {
      'notification_id': 21,
      'answer_code': 'early',
      'note': 'doctor',
    });
  });
}
