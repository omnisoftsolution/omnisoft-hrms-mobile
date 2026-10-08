import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/leave_history/leave_history_screen.dart';

void main() {
  test('validate1 uses the pending chip colour, not the approved one', () {
    expect(leaveStateColor('validate1'), leaveStateColor('confirm'));
    expect(leaveStateColor('validate1'), isNot(leaveStateColor('validate')));
    expect(leaveStateColor('validate'), AppTheme.primary);
    expect(leaveStateColor('refuse'), AppTheme.error);
  });
}
