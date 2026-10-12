import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  test('a legacy sign-in asked for push settings is told to sign in again', () {
    expect(
      friendlyError(ApiException('session_required')),
      'Sign out and sign in again to change notifications.',
    );
  });
}
