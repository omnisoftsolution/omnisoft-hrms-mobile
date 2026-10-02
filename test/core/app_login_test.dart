import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/app_login.dart';

void main() {
  test('mirrors the connector normaliser', () {
    const cases = {
      '  Say.Puay@Example.com ': 'say.puay@example.com',
      '+65 9106 2006': '6591062006',
      '(0812) 3456-7890': '081234567890',
      'EMP-0042': 'emp-0042',
      '12345': '12345',
      '': '',
    };
    cases.forEach((raw, expected) =>
        expect(normalizeAppLogin(raw), expected, reason: raw));
  });

  test('isHiddenOdooLogin flags only the omnihr.invalid placeholder', () {
    expect(isHiddenOdooLogin('omni+7@omnihr.invalid'), isTrue);
    expect(isHiddenOdooLogin('say.puay@example.com'), isFalse);
    expect(isHiddenOdooLogin(''), isFalse);
  });
}
