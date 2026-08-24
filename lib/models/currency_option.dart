import '../core/money.dart';

/// One pickable currency from `POST /currency/list` (connector
/// 2.40.0+, spec §4.1).
class CurrencyOption {
  final CurrencyInfo info;
  /// Units of company currency per 1 unit of this currency, today.
  /// Null when the tenant has no rate configured — the create screen
  /// then hides the ≈ preview and shows "rate not configured".
  final double? rateToCompany;
  final bool isCompanyCurrency;

  const CurrencyOption({
    required this.info,
    this.rateToCompany,
    this.isCompanyCurrency = false,
  });

  factory CurrencyOption.fromJson(Map<String, dynamic> json) =>
      CurrencyOption(
        info: CurrencyInfo.fromApiFields(
          id: (json['id'] as num?)?.toInt(),
          code: json['name']?.toString(),
          symbol: json['symbol']?.toString(),
          position: json['position']?.toString(),
          decimalPlaces: (json['decimal_places'] as num?)?.toInt(),
        ),
        rateToCompany: (json['rate_to_company'] as num?)?.toDouble(),
        isCompanyCurrency: json['is_company_currency'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': info.id,
        'name': info.code,
        'symbol': info.symbol,
        'position': info.position,
        'decimal_places': info.decimalPlaces,
        'rate_to_company': rateToCompany,
        'is_company_currency': isCompanyCurrency,
      };
}

class CurrencyListResult {
  final int companyCurrencyId;
  /// Per-expense cap in COMPANY currency (server truth; spec §6).
  final double? expenseAmountMax;
  final List<CurrencyOption> currencies;

  const CurrencyListResult({
    this.companyCurrencyId = 0,
    this.expenseAmountMax,
    this.currencies = const [],
  });

  factory CurrencyListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['currencies'] as List<dynamic>? ?? const [];
    return CurrencyListResult(
      companyCurrencyId:
          (json['company_currency_id'] as num?)?.toInt() ?? 0,
      expenseAmountMax: (json['expense_amount_max'] as num?)?.toDouble(),
      currencies: [
        for (final e in raw)
          if (e is Map<String, dynamic>) CurrencyOption.fromJson(e),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'company_currency_id': companyCurrencyId,
        'expense_amount_max': expenseAmountMax,
        'currencies': [for (final c in currencies) c.toJson()],
      };

  CurrencyOption? get companyOption {
    for (final c in currencies) {
      if (c.isCompanyCurrency) return c;
    }
    return null;
  }

  /// Picker is shown only for real multi-currency tenants (spec §2).
  bool get hasMultipleCurrencies => currencies.length > 1;
}
