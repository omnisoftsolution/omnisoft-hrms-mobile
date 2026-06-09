/// Auto-fill result from `POST /api/v1/omni_mobile/expense/ocr_scan`.
/// Every field has already been server-validated — `amount` is either
/// a finite positive number or null; `suggestedCategoryId` is either
/// one of the user's actual expense categories or null; `date` is
/// either a valid YYYY-MM-DD string in a sane window or empty.
class OcrResult {
  final String description;
  final double? amount;
  final String currency;
  final String date;
  final int? suggestedCategoryId;
  final String suggestedCategoryName;
  final String rawText;

  /// How many pages the server OCR'd. 1 for a photo or single-page PDF;
  /// >1 when a multi-page PDF was scanned (amount is the summed total).
  final int pagesScanned;

  OcrResult({
    this.description = '',
    this.amount,
    this.currency = '',
    this.date = '',
    this.suggestedCategoryId,
    this.suggestedCategoryName = '',
    this.rawText = '',
    this.pagesScanned = 1,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      description: json['description']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      suggestedCategoryId: (json['suggested_category_id'] as num?)?.toInt(),
      suggestedCategoryName:
          json['suggested_category_name']?.toString() ?? '',
      rawText: json['raw_text']?.toString() ?? '',
      pagesScanned: (json['pages_scanned'] as num?)?.toInt() ?? 1,
    );
  }
}
