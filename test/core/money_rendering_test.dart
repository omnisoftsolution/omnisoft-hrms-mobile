import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/money.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/models/payslip_record.dart';

void main() {
  test('expense list shows the ORIGINAL (receipt) amount', () {
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
    expect(expenseListAmount(r), '100.00 €');
  });

  test('expense list legacy payload renders exactly as 1.22.0 did', () {
    final r = ExpenseRecord.fromJson({
      'id': 1, 'name': 'Lunch', 'state': 'submitted',
      'total_amount': 1234.56,
      'currency_id': 21, 'currency_name': 'SGD',
    });
    expect(expenseListAmount(r), 'SGD 1,234.56');
  });

  test('payslip amount uses served metadata', () {
    final p = PayslipRecord.fromJson({
      'id': 1, 'name': 'SLIP/1', 'date_from': '', 'date_to': '',
      'state': 'paid', 'net_amount': 34500000.0,
      'currency_id': 12, 'currency_name': 'IDR',
      'currency_symbol': 'Rp', 'currency_position': 'before',
      'currency_decimal_places': 0,
    });
    expect(payslipAmount(p), 'Rp 34.500.000');
  });
}
