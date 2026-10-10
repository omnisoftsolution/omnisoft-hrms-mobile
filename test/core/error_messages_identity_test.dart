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

  test('add-phone codes are human (connector 2.62.0)', () {
    expect(friendlyError(ApiException('invalid_code')),
        'That add-phone code is not right or has expired. Ask HR for a new one.');
    expect(friendlyError(ApiException('invalid_credentials')),
        'Invalid login or password.');
    expect(friendlyError(ApiException('not_active')),
        'Your Omni HR account is not active yet. Activate it with the invite '
        'from HR first.');
    expect(
        friendlyError(ApiException('account_locked', data: {'retry_after': 60})),
        'Too many attempts. Try again in 1 minute.');
    expect(friendlyError(ApiException('mobile_not_enabled')),
        'Mobile attendance is not enabled for your profile.');
    expect(friendlyError(ApiException('seat_limit_exceeded')),
        'Your organization has reached its mobile seat limit. Contact your '
        'administrator to request access.');
    expect(friendlyError(ApiException('rate_limit_exceeded')),
        'Too many attempts. Try again in a few minutes.');
  });
}
