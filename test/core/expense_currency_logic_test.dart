import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/money.dart';
import 'package:omni_hr/models/currency_option.dart';

CurrencyListResult _list() => CurrencyListResult.fromJson({
      'company_currency_id': 21,
      'expense_amount_max': 99999.99,
      'currencies': [
        {'id': 21, 'name': 'SGD', 'symbol': r'$', 'position': 'before',
         'decimal_places': 2, 'rate_to_company': 1.0,
         'is_company_currency': true},
        {'id': 111, 'name': 'MYR', 'symbol': 'RM', 'position': 'before',
         'decimal_places': 2, 'rate_to_company': 0.29,
         'is_company_currency': false},
        {'id': 7, 'name': 'THB', 'symbol': '฿', 'position': 'before',
         'decimal_places': 2, 'rate_to_company': null,
         'is_company_currency': false},
      ],
    });

void main() {
  final list = _list();
  final sgd = list.currencies[0];
  final myr = list.currencies[1];
  final thb = list.currencies[2];

  group('amountCapFor', () {
    test('company currency: server cap as-is', () {
      expect(amountCapFor(sgd, list), 99999.99);
    });
    test('foreign with rate: cap / rate', () {
      expect(amountCapFor(myr, list), closeTo(344827.55, 0.1));
    });
    test('no rate → generic sanity bound', () {
      expect(amountCapFor(thb, list), 999999999);
    });
    test('no list (old server) → legacy cap', () {
      expect(amountCapFor(null, null), 99999.99);
    });
  });

  group('conversionPreview', () {
    test('company currency → null (no preview)', () {
      expect(conversionPreview('100', sgd, list), isNull);
    });
    test('foreign with rate → estimate line', () {
      expect(conversionPreview('100', myr, list),
          '≈ \$ 29.00 (estimate)');
    });
    test('foreign without rate → rate-not-configured sentinel', () {
      expect(conversionPreview('100', thb, list),
          kRateNotConfigured);
    });
    test('unparseable amount → null', () {
      expect(conversionPreview('', myr, list), isNull);
      expect(conversionPreview('abc', myr, list), isNull);
    });
  });

  group('matchOcrCurrency', () {
    test('matches active code case-insensitively', () {
      expect(matchOcrCurrency('MYR', list)?.info.id, 111);
      expect(matchOcrCurrency('myr', list)?.info.id, 111);
    });
    test('no match / no list / empty → null', () {
      expect(matchOcrCurrency('JPY', list), isNull);
      expect(matchOcrCurrency('', list), isNull);
      expect(matchOcrCurrency('MYR', null), isNull);
    });
  });
}
