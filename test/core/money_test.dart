import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/money.dart';

void main() {
  const sgd = CurrencyInfo(
      id: 1, code: 'SGD', symbol: r'$', position: 'before',
      decimalPlaces: 2);
  const idr = CurrencyInfo(
      id: 2, code: 'IDR', symbol: 'Rp', position: 'before',
      decimalPlaces: 0);
  const eur = CurrencyInfo(
      id: 3, code: 'EUR', symbol: '€', position: 'after',
      decimalPlaces: 2);
  // Old-server fallback: no symbol served → code prefix, 2 decimals.
  const legacy = CurrencyInfo(id: 1, code: 'SGD');

  group('MoneyFormatter.format', () {
    test('symbol before, en grouping', () {
      expect(MoneyFormatter.format(1234.56, sgd), r'$ 1,234.56');
    });
    test('IDR: zero decimals, id-style grouping', () {
      expect(MoneyFormatter.format(34500000, idr), 'Rp 34.500.000');
    });
    test('position after', () {
      expect(MoneyFormatter.format(1234.56, eur), '1,234.56 €');
    });
    test('legacy fallback reproduces pre-1.23 rendering exactly', () {
      // Must match expenses_screen.dart's old NumberFormat('#,##0.00')
      // + "CODE " prefix byte-for-byte.
      expect(MoneyFormatter.format(1234.56, legacy), 'SGD 1,234.56');
      expect(MoneyFormatter.format(42.1, legacy), 'SGD 42.10');
    });
    test('empty currency entirely → bare number', () {
      expect(MoneyFormatter.format(42.1, const CurrencyInfo()), '42.10');
    });
    test('clamps insane and negative values', () {
      expect(MoneyFormatter.format(1.3e25, sgd), r'$ —');
      expect(MoneyFormatter.format(-5, sgd), r'$ —');
      expect(MoneyFormatter.format(double.nan, legacy), 'SGD —');
      expect(MoneyFormatter.format(1.3e25, const CurrencyInfo()),
          'Invalid amount');
    });
  });

  group('CurrencyInfo.fromApiFields', () {
    test('defaults for absent metadata (old server)', () {
      final c = CurrencyInfo.fromApiFields(id: 7, code: 'SGD');
      expect(c.symbol, '');
      expect(c.position, 'before');
      expect(c.decimalPlaces, 2);
    });
    test('full metadata', () {
      final c = CurrencyInfo.fromApiFields(
          id: 7, code: 'IDR', symbol: 'Rp', position: 'before',
          decimalPlaces: 0);
      expect(c.decimalPlaces, 0);
    });
  });
}
