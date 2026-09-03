import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  group('buildLeavePreviewBody', () {
    test('custom hours: sends hour_from/hour_to on a single date', () {
      final body = buildLeavePreviewBody(
        holidayStatusId: 74,
        dateFrom: '2026-09-04',
        dateTo: '2026-09-04',
        hourFrom: 11.0,
        hourTo: 15.0,
      );
      expect(body['holiday_status_id'], 74);
      expect(body['date_from'], '2026-09-04');
      expect(body['date_to'], '2026-09-04');
      expect(body['hour_from'], 11.0);
      expect(body['hour_to'], 15.0);
      expect(body.containsKey('date_from_period'), isFalse);
      expect(body.containsKey('date_to_period'), isFalse);
    });

    test('full-day range: omits hour fields entirely (not JSON null)', () {
      final body = buildLeavePreviewBody(
        holidayStatusId: 74,
        dateFrom: '2026-09-03',
        dateTo: '2026-09-04',
      );
      expect(body.containsKey('hour_from'), isFalse);
      expect(body.containsKey('hour_to'), isFalse);
    });

    test('half day: sends periods, no hours', () {
      final body = buildLeavePreviewBody(
        holidayStatusId: 77,
        dateFrom: '2026-09-04',
        dateTo: '2026-09-04',
        dateFromPeriod: 'am',
        dateToPeriod: 'am',
      );
      expect(body['date_from_period'], 'am');
      expect(body['date_to_period'], 'am');
      expect(body.containsKey('hour_from'), isFalse);
    });

    test('never carries reason or attachment', () {
      final body = buildLeavePreviewBody(
        holidayStatusId: 74,
        dateFrom: '2026-09-04',
        dateTo: '2026-09-04',
      );
      expect(body.containsKey('reason'), isFalse);
      expect(body.containsKey('attachment'), isFalse);
    });
  });
}
