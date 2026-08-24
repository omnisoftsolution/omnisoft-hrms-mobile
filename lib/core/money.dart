import 'package:intl/intl.dart';

import '../models/expense_record.dart';
import '../models/payslip_record.dart';

/// Formatting identity of one currency, served by the connector
/// (2.40.0+) per res.currency. Constructed with fallbacks so an old
/// server (no symbol/position/decimals in the payload) reproduces the
/// pre-1.23 "CODE 1,234.56" rendering exactly.
class CurrencyInfo {
  final int id;
  final String code; // ISO 4217, e.g. 'SGD'
  final String symbol; // '' when the server didn't send one
  final String position; // 'before' | 'after'
  final int decimalPlaces;

  const CurrencyInfo({
    this.id = 0,
    this.code = '',
    this.symbol = '',
    this.position = 'before',
    this.decimalPlaces = 2,
  });

  factory CurrencyInfo.fromApiFields({
    int? id,
    String? code,
    String? symbol,
    String? position,
    int? decimalPlaces,
  }) =>
      CurrencyInfo(
        id: id ?? 0,
        code: code ?? '',
        symbol: symbol ?? '',
        position: position ?? 'before',
        decimalPlaces: decimalPlaces ?? 2,
      );

  bool get isEmpty => id == 0 && code.isEmpty && symbol.isEmpty;
}

/// THE money renderer — replaces the three per-screen formatters and
/// mirrors the connector's format_amount output. Grouping style: a
/// small per-currency locale map (IDR/VND read natively as
/// 34.500.000); everything else uses en-style 1,234.56.
class MoneyFormatter {
  MoneyFormatter._();

  static const _idStyleCodes = {'IDR', 'VND'};

  /// Sanity backstop, NOT the input cap: pre-validation legacy rows
  /// can hold absurd values (1.3e25) that would crater layouts.
  /// 12 digits clears any valid zero-decimal amount.
  static const double _clampMax = 999999999999.99;

  static String format(double v, CurrencyInfo c) {
    final label = c.symbol.isNotEmpty ? c.symbol : c.code;
    if (!v.isFinite || v < 0 || v > _clampMax) {
      return label.isEmpty ? 'Invalid amount' : '$label —';
    }
    final locale =
        _idStyleCodes.contains(c.code) ? 'id_ID' : 'en_US';
    final fmt = NumberFormat.decimalPatternDigits(
        locale: locale, decimalDigits: c.decimalPlaces);
    final number = fmt.format(v);
    if (label.isEmpty) return number;
    return c.position == 'after' ? '$number $label' : '$label $number';
  }
}

/// List/hero amount for an expense: the RECEIPT (original) figure —
/// what the employee actually spent (spec §5.3). Legacy payloads fall
/// back to total_amount + code-prefix rendering via the model defaults.
String expenseListAmount(ExpenseRecord r) =>
    MoneyFormatter.format(r.origAmount, r.origCurrency);

/// Net amount for a payslip row, in the payslip's actual currency.
String payslipAmount(PayslipRecord r) =>
    MoneyFormatter.format(r.netAmount, r.currency);
