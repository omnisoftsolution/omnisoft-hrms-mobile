import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  test('Forgot something? codes read as sentences', () {
    String text(String code) => friendlyError(ApiException(code));
    expect(
      text('undo_expired'),
      'It is too late to undo this punch. Ask HR to correct it.',
    );
    expect(text('undo_not_last'), 'That punch was already undone.');
    expect(
      text('bad_time'),
      "That time doesn't fit this punch. Pick another time.",
    );
    expect(
      text('too_old'),
      'This day can no longer be changed from the app. Tell HR directly.',
    );
    expect(text('not_yours'), 'This punch is not yours.');
    expect(text('already_answered'), 'You already answered this question.');
    expect(
      text('invalid_answer'),
      'That answer is no longer available. Pull down to refresh.',
    );
  });

  test('busy_retry: attendance context says Please try again.', () {
    final e = ApiException('busy_retry');
    expect(
      friendlyError(e, context: ErrorContext.attendance),
      'Please try again.',
    );
    // Every other screen keeps its wording.
    expect(
      friendlyError(e),
      'Someone else is updating this request. Try again.',
    );
    expect(
      friendlyError(
        ApiException('undo_not_last'),
        context: ErrorContext.attendance,
      ),
      'That punch was already undone.',
    );
  });
}
