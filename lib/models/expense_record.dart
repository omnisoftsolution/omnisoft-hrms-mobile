import '../core/money.dart';

/// One row in the user's expense list, sourced from
/// `POST /api/v1/omni_mobile/expense/list`. Matches the shape built
/// in `controllers/main.py` `expense_list()`.
class ExpenseRecord {
  final int id;
  final String name;
  final double totalAmount;
  final int currencyId;
  final String currencyName;
  final String date;
  /// Submission timestamp (Odoo `create_date`) — ISO `YYYY-MM-DD HH:MM:SS`.
  /// Used as the primary "Submitted X" label on the list so an OCR'd
  /// receipt-date in the past doesn't bury today's submission.
  final String createDate;
  final int productId;
  final String productName;
  final String state;
  final String approvalState;
  final List<ExpenseAttachment> attachments;
  final String paymentMode; // 'own_account' | 'company_account'
  final double untaxedAmount;
  final double taxAmount;
  /// Populated when state == 'refused' — the reason the admin gave
  /// in the refuse wizard. Empty for any other state, or if Odoo's
  /// refuse template was customised and the server couldn't extract.
  final String refuseReason;
  final double origAmount;
  final CurrencyInfo currency;
  final CurrencyInfo origCurrency;

  ExpenseRecord({
    required this.id,
    required this.name,
    required this.totalAmount,
    this.currencyId = 0,
    this.currencyName = '',
    this.date = '',
    this.createDate = '',
    this.productId = 0,
    this.productName = '',
    required this.state,
    this.approvalState = '',
    this.attachments = const [],
    this.paymentMode = 'own_account',
    this.untaxedAmount = 0.0,
    this.taxAmount = 0.0,
    this.refuseReason = '',
    this.origAmount = 0.0,
    this.currency = const CurrencyInfo(),
    this.origCurrency = const CurrencyInfo(),
  });

  /// Back-compat for call sites that only need the boolean.
  bool get hasAttachment => attachments.isNotEmpty;

  /// True when the receipt was in a different currency than the company.
  bool get isForeignCurrency => origCurrency.id != 0 && currency.id != 0 && origCurrency.id != currency.id;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    // Parse new attachments list. Fall back to the legacy
    // has_attachment boolean shape so a stale server (pre-2.13.0)
    // doesn't break the mobile — list will be empty but the badge
    // can still be set.
    final attachments = <ExpenseAttachment>[];
    final attsRaw = json['attachments'];
    if (attsRaw is List) {
      for (final item in attsRaw) {
        if (item is Map<String, dynamic>) {
          attachments.add(ExpenseAttachment.fromJson(item));
        }
      }
    }
    final currency = CurrencyInfo.fromApiFields(
      id: (json['currency_id'] as num?)?.toInt(),
      code: json['currency_name']?.toString(),
      symbol: json['currency_symbol']?.toString(),
      position: json['currency_position']?.toString(),
      decimalPlaces: (json['currency_decimal_places'] as num?)?.toInt(),
    );
    final origCurrency = json.containsKey('orig_currency_id')
        ? CurrencyInfo.fromApiFields(
            id: (json['orig_currency_id'] as num?)?.toInt(),
            code: json['orig_currency_name']?.toString(),
            symbol: json['orig_currency_symbol']?.toString(),
            position: json['orig_currency_position']?.toString(),
            decimalPlaces:
                (json['orig_currency_decimal_places'] as num?)?.toInt(),
          )
        : currency; // old server: one currency for everything
    return ExpenseRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      currencyId: (json['currency_id'] as num?)?.toInt() ?? 0,
      currencyName: json['currency_name']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      createDate: json['create_date']?.toString() ?? '',
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: json['product_name']?.toString() ?? '',
      state: json['state']?.toString() ?? 'draft',
      approvalState: json['approval_state']?.toString() ?? '',
      attachments: attachments,
      paymentMode: json['payment_mode']?.toString() ?? 'own_account',
      untaxedAmount: (json['untaxed_amount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      refuseReason: json['refuse_reason']?.toString() ?? '',
      origAmount: (json['orig_amount'] as num?)?.toDouble() ?? ((json['total_amount'] as num?)?.toDouble() ?? 0.0),
      currency: currency,
      origCurrency: origCurrency,
    );
  }

  /// Human-readable label for the Paid By column. Mirrors the Odoo
  /// hr.expense.payment_mode selection labels.
  String get paymentModeLabel {
    switch (paymentMode) {
      case 'company_account':
        return 'Company';
      case 'own_account':
      default:
        return 'Employee (to reimburse)';
    }
  }

  /// Human-readable label for the badge.
  String get stateLabel {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'submitted':
        return 'Submitted';
      case 'approved':
        return 'Approved';
      case 'posted':
        return 'Posted';
      case 'in_payment':
        return 'In Payment';
      case 'paid':
        return 'Paid';
      case 'refused':
        return 'Refused';
      default:
        return state;
    }
  }
}

/// Static expense category sourced from
/// `POST /api/v1/omni_mobile/expense/categories`. Each is a
/// product.product where `can_be_expensed=True`.
class ExpenseCategory {
  final int id;
  final String name;
  final double defaultUnitAmount;
  final int currencyId;
  final String currencyName;
  final CurrencyInfo currency;

  ExpenseCategory({
    required this.id,
    required this.name,
    this.defaultUnitAmount = 0.0,
    this.currencyId = 0,
    this.currencyName = '',
    this.currency = const CurrencyInfo(),
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    final currency = CurrencyInfo.fromApiFields(
      id: (json['currency_id'] as num?)?.toInt(),
      code: json['currency_name']?.toString(),
      symbol: json['currency_symbol']?.toString(),
      position: json['currency_position']?.toString(),
      decimalPlaces: (json['currency_decimal_places'] as num?)?.toInt(),
    );
    return ExpenseCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      defaultUnitAmount:
          (json['default_unit_amount'] as num?)?.toDouble() ?? 0.0,
      currencyId: (json['currency_id'] as num?)?.toInt() ?? 0,
      currencyName: json['currency_name']?.toString() ?? '',
      currency: currency,
    );
  }
}

/// One attachment bound to an `hr.expense` record. Returned in the
/// list payload so the detail screen can fetch bytes on demand via
/// the `/expense/attachment/get` endpoint.
class ExpenseAttachment {
  final int id;
  final String name;
  final String mimetype;
  final int fileSize;

  ExpenseAttachment({
    required this.id,
    required this.name,
    this.mimetype = '',
    this.fileSize = 0,
  });

  factory ExpenseAttachment.fromJson(Map<String, dynamic> json) {
    return ExpenseAttachment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      mimetype: json['mimetype']?.toString() ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isImage => mimetype.startsWith('image/');

  String get sizeLabel {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(0)}KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
