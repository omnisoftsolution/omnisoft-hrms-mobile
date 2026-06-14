import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/utils/leave_backdate.dart';

void main() {
  final now = DateTime(2026, 6, 14, 15, 30); // arbitrary time-of-day
  final midnight = DateTime(2026, 6, 14);

  group('backdateFirstDate', () {
    test('backdating off -> today', () {
      expect(backdateFirstDate(false, DateTime(2026, 1, 1), now), midnight);
    });
    test('explicit floor -> that date (midnight-normalised)', () {
      expect(backdateFirstDate(true, DateTime(2026, 4, 17, 9), now),
          DateTime(2026, 4, 17));
    });
    test('allowed + null floor -> today minus 365', () {
      expect(backdateFirstDate(true, null, now),
          midnight.subtract(const Duration(days: 365)));
    });
  });
}
