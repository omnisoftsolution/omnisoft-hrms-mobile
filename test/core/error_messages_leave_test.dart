import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  // FB-8: leave cancel / modify codes the History screen can meet, and the
  // plan gate, read as sentences instead of raw codes.
  test('leave history codes read as sentences', () {
    String text(String code) => friendlyError(ApiException(code));
    // M4: the History screen reloads by itself, so no "Pull down".
    const decided = 'This request was already decided.';
    expect(text('not_cancellable'), decided);
    expect(text('not_modifiable'), decided);
    expect(
      text('feature_unavailable'),
      "This feature isn't included in your company's plan. Ask HR.",
    );
    expect(
      text('leave_type_not_allowed'),
      "This leave type can't be requested from the app. Ask HR.",
    );
    expect(text('invalid_hours'), 'Pick a start time before the end time.');
    expect(text('invalid_period'), 'Pick a valid half of the day.');
  });

  test('a concurrent update asks to try again (V-6)', () {
    expect(
      friendlyError(ApiException('busy_retry')),
      'Someone else is updating this request. Try again.',
    );
  });

  test('a raw exception never shows as "Error: ..."', () {
    expect(friendlyError(Exception('not_cancellable')),
        'This request was already decided.');
  });

  test('isLeaveChangedError: decided, deleted or changed requests', () {
    for (final code in [
      'not_cancellable',
      'not_modifiable',
      'not_found',
      'state_changed',
    ]) {
      expect(isLeaveChangedError(ApiException(code)), isTrue, reason: code);
    }
    expect(isLeaveChangedError(Exception('not_cancellable')), isTrue);
    for (final code in ['network_error', 'busy_retry', 'overlap', 'not_owner']) {
      expect(isLeaveChangedError(ApiException(code)), isFalse, reason: code);
    }
  });
}
