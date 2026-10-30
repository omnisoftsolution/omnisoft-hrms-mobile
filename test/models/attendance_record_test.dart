import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/attendance_record.dart';

AttendanceRecord _record({String? inMode, String? outMode}) =>
    AttendanceRecord.fromJson({
      'id': 1,
      'in_mode': inMode,
      'out_mode': outMode,
    });

void main() {
  group('AttendanceRecord.modeLabel', () {
    test('the existing labels stay', () {
      expect(_record(inMode: 'mobile').modeLabel, 'Mobile');
      expect(_record(inMode: 'kiosk').modeLabel, 'Kiosk');
      expect(_record(inMode: 'systray').modeLabel, 'Web');
      expect(_record(inMode: 'manual').modeLabel, 'Manual');
      expect(_record(inMode: 'auto_check_out').modeLabel, 'Auto check-out');
      expect(_record().modeLabel, '—');
      expect(_record(inMode: 'mobile', outMode: 'mobile').modeLabel, 'Mobile');
    });

    test('history auto in/out -> Automatic (AA-F09)', () {
      expect(_record(inMode: 'auto', outMode: 'auto').modeLabel, 'Automatic');
      expect(_record(inMode: 'auto').modeLabel, 'Automatic');
      expect(_record(inMode: 'auto', outMode: 'mobile').modeLabel, 'Automatic');
    });

    test('mixed: a hand check-in with an automatic check-out', () {
      expect(
        _record(inMode: 'mobile', outMode: 'auto').modeLabel,
        'Mobile · Automatic out',
      );
      expect(
        _record(inMode: 'kiosk', outMode: 'auto').modeLabel,
        'Kiosk · Automatic out',
      );
      expect(_record(outMode: 'auto').modeLabel, 'Automatic');
    });
  });
}
