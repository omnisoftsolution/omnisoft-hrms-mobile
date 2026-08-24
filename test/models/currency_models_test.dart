import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/currency_option.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/models/payslip_record.dart';

void main() {
  group('ExpenseRecord multi-currency parsing', () {
    test('new-server foreign expense', () {
      final r = ExpenseRecord.fromJson({
        'id': 1, 'name': 'EUR hotel', 'state': 'submitted',
        'total_amount': 50.0,
        'currency_id': 21, 'currency_name': 'SGD',
        'currency_symbol': r'$', 'currency_position': 'before',
        'currency_decimal_places': 2,
        'orig_amount': 100.0,
        'orig_currency_id': 3, 'orig_currency_name': 'EUR',
        'orig_currency_symbol': '€', 'orig_currency_position': 'after',
        'orig_currency_decimal_places': 2,
      });
      expect(r.origAmount, 100.0);
      expect(r.origCurrency.code, 'EUR');
      expect(r.origCurrency.position, 'after');
      expect(r.currency.code, 'SGD');
      expect(r.isForeignCurrency, isTrue);
    });

    test('old-server payload falls back to legacy single-currency', () {
      final r = ExpenseRecord.fromJson({
        'id': 1, 'name': 'Lunch', 'state': 'submitted',
        'total_amount': 42.1,
        'currency_id': 21, 'currency_name': 'SGD',
      });
      expect(r.origAmount, 42.1); // mirrors total_amount
      expect(r.origCurrency.code, 'SGD');
      expect(r.origCurrency.symbol, ''); // → code-prefix rendering
      expect(r.currency.decimalPlaces, 2);
      expect(r.isForeignCurrency, isFalse);
    });
  });

  test('PayslipRecord parses metadata with fallback', () {
    final withMeta = PayslipRecord.fromJson({
      'id': 1, 'name': 'SLIP/1', 'date_from': '2026-08-01',
      'date_to': '2026-08-31', 'state': 'paid',
      'net_amount': 34500000.0,
      'currency_id': 12, 'currency_name': 'IDR',
      'currency_symbol': 'Rp', 'currency_position': 'before',
      'currency_decimal_places': 0,
    });
    expect(withMeta.currency.decimalPlaces, 0);
    expect(withMeta.currency.symbol, 'Rp');
    final legacy = PayslipRecord.fromJson({
      'id': 1, 'name': 'SLIP/1', 'date_from': '', 'date_to': '',
      'state': 'paid', 'net_amount': 100.0,
      'currency_id': 21, 'currency_name': 'SGD',
    });
    expect(legacy.currency.code, 'SGD');
    expect(legacy.currency.decimalPlaces, 2);
  });

  group('CurrencyListResult', () {
    final json = {
      'success': true,
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
    };

    test('fromJson', () {
      final r = CurrencyListResult.fromJson(json);
      expect(r.companyCurrencyId, 21);
      expect(r.expenseAmountMax, 99999.99);
      expect(r.currencies.length, 3);
      expect(r.currencies[1].info.code, 'MYR');
      expect(r.currencies[2].rateToCompany, isNull);
      expect(r.companyOption?.info.code, 'SGD');
    });

    test('toJson→fromJson round-trips (cache path)', () {
      final r = CurrencyListResult.fromJson(json);
      final again = CurrencyListResult.fromJson(r.toJson());
      expect(again.currencies.length, 3);
      expect(again.currencies[2].rateToCompany, isNull);
      expect(again.expenseAmountMax, 99999.99);
    });
  });
}
