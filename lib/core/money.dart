import 'package:intl/intl.dart';

import '../models/currency_option.dart';
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

/// Sentinel returned by [conversionPreview] when the selected foreign
/// currency has no configured rate — the caller renders it as a
/// warning instead of an estimate.
const String kRateNotConfigured = 'rate not configured';

/// Input cap in the SELECTED currency (spec §6): the server's
/// company-currency cap divided by the informational rate. Falls back
/// to the generic sanity bound when the rate is unknown, and to the
/// legacy 99,999.99 when there is no currency list at all (old
/// server — identical to pre-1.23 behavior).
double amountCapFor(CurrencyOption? selected, CurrencyListResult? list) {
  const legacyCap = 99999.99;
  const sanityCap = 999999999.0;
  if (list == null) return legacyCap;
  final serverCap = list.expenseAmountMax ?? legacyCap;
  if (selected == null || selected.isCompanyCurrency) return serverCap;
  final rate = selected.rateToCompany;
  if (rate == null || rate <= 0) return sanityCap;
  return serverCap / rate;
}

/// The "≈ $ 42.10 (estimate)" line under the amount field. Null =
/// show nothing (company currency, nothing selected, or the typed
/// amount doesn't parse). [kRateNotConfigured] = show the warning.
String? conversionPreview(
    String rawAmount, CurrencyOption? selected, CurrencyListResult? list) {
  if (list == null || selected == null || selected.isCompanyCurrency) {
    return null;
  }
  final v = double.tryParse(rawAmount.trim());
  if (v == null || !v.isFinite || v <= 0) return null;
  final rate = selected.rateToCompany;
  if (rate == null || rate <= 0) return kRateNotConfigured;
  final company = list.companyOption;
  if (company == null) return null;
  final converted = MoneyFormatter.format(v * rate, company.info);
  return '≈ $converted (estimate)';
}

/// OCR wiring (spec §5.2): the scanned ISO code selects a currency
/// only when the tenant actually has it active. Empty/unknown codes
/// return null — caller keeps the current selection and shows the
/// "not enabled" notice for the unknown case.
CurrencyOption? matchOcrCurrency(String ocrCode, CurrencyListResult? list) {
  final code = ocrCode.trim().toUpperCase();
  if (code.isEmpty || list == null) return null;
  for (final c in list.currencies) {
    if (c.info.code.toUpperCase() == code) return c;
  }
  return null;
}
