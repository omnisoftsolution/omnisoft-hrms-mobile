import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/location_result.dart';

void main() {
  group('LocationResult.isMocked', () {
    test('defaults to false when not provided', () {
      final r = LocationResult.ready(latitude: 1.3, longitude: 103.8, accuracy: 10.0);
      expect(r.isMocked, isFalse);
    });

    test('carries through the ready factory', () {
      final r = LocationResult.ready(
          latitude: 1.3, longitude: 103.8, accuracy: 10.0, isMocked: true);
      expect(r.isMocked, isTrue);
      expect(r.accuracy, 10.0);
    });
  });
}
