import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

void main() {
  test('login and device-code-unavailable codes are human', () {
    expect(friendlyErrorCode('login_invalid'),
        'Use 3 to 64 characters without spaces.');
    expect(friendlyErrorCode('login_taken'),
        'That login is already used. Choose another.');
    expect(friendlyErrorCode('device_verification_unavailable'),
        'This phone needs a sign-in code, but there is no email on file '
        'for you. Ask HR for a new QR code.');
    expect(friendlyError(ApiException('login_taken')),
        'That login is already used. Choose another.');
  });
}
