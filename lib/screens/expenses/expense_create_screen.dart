import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../core/money.dart';
import '../../core/pdf_raster.dart';
import '../../models/currency_option.dart';
import '../../models/expense_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';

/// Returns (parsed value, error). When error != null the value is
/// null. Empty input gets its own error so the disabled-submit state
/// and the inline message stay in sync. The backend runs the same
/// rules in Decimal — see controllers/main.py `_validate_expense_amount`.
/// [maxAmount]/[decimalPlaces] vary per selected currency (spec §6);
/// callers without a currency list keep the legacy defaults.
(double?, String?) _parseExpenseAmount(
  String raw, {
  int decimalPlaces = 2,
  double maxAmount = 99999.99,
}) {
  final capStr = decimalPlaces > 0
      ? NumberFormat('#,##0.00').format(maxAmount)
      : NumberFormat('#,##0').format(maxAmount);
  final generic =
      'Enter a valid amount up to $capStr with max $decimalPlaces decimals.';
  final s = raw.trim();
  if (s.isEmpty) return (null, 'Amount is required.');
  if (s.contains(RegExp(r'[eE,]'))) return (null, generic);
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) return (null, generic);
  if (v <= 0) return (null, 'Amount must be greater than zero.');
  if (v > maxAmount) return (null, generic);
  final decRe = decimalPlaces > 0
      ? RegExp('^\\d+(\\.\\d{1,$decimalPlaces})?\$')
      : RegExp(r'^\d+$');
  if (!decRe.hasMatch(s)) {
    return (null,
        decimalPlaces > 0
            ? 'Max $decimalPlaces decimal places.'
            : 'This currency does not use decimals.');
  }
  return (v, null);
}

/// Rejects any keystroke that would leave the field in an invalid
/// state — bounds the input to "up to [maxIntDigits] digits + optional
/// .DD" (digit count varies with [decimalPlaces]). The runtime parser
/// still has the final say (catches blank, leading dot, etc.).
class _AmountInputFormatter extends TextInputFormatter {
  final RegExp _re;
  _AmountInputFormatter({int decimalPlaces = 2, int maxIntDigits = 5})
      : _re = decimalPlaces > 0
            ? RegExp('^\\d{0,$maxIntDigits}(\\.\\d{0,$decimalPlaces})?\$')
            : RegExp('^\\d{0,$maxIntDigits}\$');
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty || _re.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Create + submit a single expense. Each submission is one
/// hr.expense; the connector auto-creates a singleton expense sheet
/// and flips state to 'submitted'. Receipt photo is required.
class ExpenseCreateScreen extends StatefulWidget {
  /// Pass an existing record to switch into "edit mode" — title,
  /// prefill values, submit-as-modify. Null = create mode (default).
  final ExpenseRecord? editingRecord;

  const ExpenseCreateScreen({super.key, this.editingRecord});

  bool get isEditing => editingRecord != null;

  @override
  State<ExpenseCreateScreen> createState() => _ExpenseCreateScreenState();
}

class _ExpenseCreateScreenState extends State<ExpenseCreateScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  List<ExpenseCategory> _categories = const [];
  ExpenseCategory? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  Uint8List? _receiptBytes;
  String _receiptName = '';
  String _receiptMime = 'image/jpeg';
  String _paymentMode = 'own_account';

  /// PDF receipt support. When the attached receipt is a PDF,
  /// `_receiptBytes` holds the ORIGINAL PDF (uploaded as-is), while these
  /// hold the locally-rasterized page images used for the preview
  /// thumbnail and for OCR. `_pdfPages` is empty when the attachment is
  /// an image, or when a PDF failed to rasterize (then it degrades to a
  /// file-chip and Scan is hidden, but the PDF still uploads/attaches).
  bool get _receiptIsPdf => _receiptMime == 'application/pdf';
  List<Uint8List> _pdfPages = const [];
  int _pdfPageCount = 0;
  bool _rasterizingPdf = false;

  CurrencyListResult? _currencyList;
  CurrencyOption? _selectedCurrency;

  bool get _showCurrencyPicker =>
      _currencyList?.hasMultipleCurrencies ?? false;
  int get _decimalPlaces => _selectedCurrency?.info.decimalPlaces ?? 2;
  double get _maxAmount => amountCapFor(_selectedCurrency, _currencyList);
  int get _maxIntDigits => _maxAmount >= 1000000 ? 9 : 5;

  bool _loadingCategories = true;
  /// Friendly message set when the category fetch itself FAILED (offline,
  /// server error). Distinct from "loaded fine but the company has zero
  /// categories" — that case shows the "ask your administrator" hint.
  /// Kept separate from the form-level _error so a transient load failure
  /// doesn't look like a submit error.
  String? _categoryError;
  bool _submitting = false;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the record being edited. Category is resolved
    // after categories load (we need the list to find the matching
    // ExpenseCategory object).
    final r = widget.editingRecord;
    if (r != null) {
      _descriptionController.text = r.name;
      // The receipt (original) figure — decimals are corrected once
      // currencies load; acceptable transitional state.
      _amountController.text = r.origAmount.toStringAsFixed(2);
      _paymentMode = r.paymentMode;
      final parsedDate = DateTime.tryParse(r.date);
      if (parsedDate != null) _selectedDate = parsedDate;
    }
    _loadCategories();
    _loadCurrencies();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final session = context.read<SessionService>();
    if (mounted) {
      setState(() {
        _loadingCategories = true;
        _categoryError = null;
      });
    }
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final list = await api.getExpenseCategories();
      if (!mounted) return;
      // In edit mode, find the category matching the record's
      // productId so the dropdown is pre-selected.
      ExpenseCategory? preselected;
      final r = widget.editingRecord;
      if (r != null && r.productId > 0) {
        for (final c in list) {
          if (c.id == r.productId) {
            preselected = c;
            break;
          }
        }
      }
      setState(() {
        _categories = list;
        _selectedCategory = preselected ?? _selectedCategory;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoryError = friendlyError(e);
      });
    }
  }

  Future<void> _loadCurrencies() async {
    final session = context.read<SessionService>();
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'currency_list_cache';
    final api = OmniMobileApi(
      baseUrl: session.clientUrl,
      db: session.clientDb,
      token: session.token,
    );
    var result = await api.getCurrencyList();
    if (result != null) {
      await prefs.setString(cacheKey, jsonEncode(result.toJson()));
    } else {
      // Old server or transient failure: last-known-good keeps the
      // picker stable across network blips; a genuinely old server
      // never wrote the cache, so this stays null there.
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        try {
          result = CurrencyListResult.fromJson(
              jsonDecode(cached) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _currencyList = result;
      _selectedCurrency ??= _initialCurrency(result);
    });
  }

  CurrencyOption? _initialCurrency(CurrencyListResult? list) {
    if (list == null) return null;
    final r = widget.editingRecord;
    if (r != null && r.origCurrency.id != 0) {
      for (final c in list.currencies) {
        if (c.info.id == r.origCurrency.id) return c;
      }
    }
    return list.companyOption;
  }

  /// Camera is the primary "Attach receipt" action — receipts are
  /// usually paper in front of you. Library is the secondary link for
  /// receipts that arrived via email, and accepts PDFs as well as images.
  Future<void> _pickReceiptFromCamera() => _pickReceiptImage(ImageSource.camera);

  Future<void> _pickReceiptImage(ImageSource source) async {
    try {
      // imageQuality:85 keeps receipt photos around 200-500KB while
      // staying readable. Well under the connector's 10MB attachment
      // cap and gentle on uploads over cellular. Gallery picks can
      // still return arbitrary-size library images (4K screenshots,
      // long-side panoramas), so the post-pick size check is the
      // actual ceiling.
      final xfile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 10 * 1024 * 1024) {
        setState(() => _error = 'Receipt is too large. Max 10 MB.');
        return;
      }
      _applyImageReceipt(bytes, xfile.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not attach the receipt. Please try again.');
    }
  }

  /// "Pick from library" — a file picker that accepts both images and
  /// PDF. PDF receipts are common when expenses arrive by email.
  Future<void> _pickReceiptFromLibrary() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final bytes = f.bytes;
      final name = f.name;
      if (bytes == null) {
        if (!mounted) return;
        setState(() => _error = 'Could not read that file. Please try again.');
        return;
      }
      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        setState(() => _error = 'Receipt is too large. Max 10 MB.');
        return;
      }
      final ext = name.toLowerCase().split('.').last;
      if (ext == 'pdf') {
        await _applyPdfReceipt(bytes, name);
      } else {
        if (!mounted) return;
        _applyImageReceipt(bytes, name);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not attach the receipt. Please try again.');
    }
  }

  /// Set an image receipt and clear any PDF state.
  void _applyImageReceipt(Uint8List bytes, String name) {
    setState(() {
      _receiptBytes = bytes;
      _receiptName = name;
      _receiptMime = _mimeFromName(name);
      _pdfPages = const [];
      _pdfPageCount = 0;
      _error = null;
    });
  }

  /// Set a PDF receipt. The ORIGINAL PDF is what we upload; we also try
  /// to rasterize its pages for the preview thumbnail and OCR. If
  /// rasterization fails (encrypted/corrupt PDF, platform hiccup), the
  /// PDF still attaches and uploads — only the thumbnail and Scan are
  /// unavailable (the field degrades to a file-chip).
  Future<void> _applyPdfReceipt(Uint8List pdfBytes, String name) async {
    setState(() {
      _receiptBytes = pdfBytes;
      _receiptName = name;
      _receiptMime = 'application/pdf';
      _pdfPages = const [];
      _pdfPageCount = 0;
      _error = null;
      _rasterizingPdf = true;
    });
    final count = await PdfRaster.pageCount(pdfBytes);
    final pages = await PdfRaster.renderPages(pdfBytes);
    if (!mounted) return;
    setState(() {
      _pdfPageCount = count ?? pages.length;
      _pdfPages = pages;
      _rasterizingPdf = false;
    });
  }

  String _mimeFromName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  bool get _canSubmit {
    final (parsed, _) = _parseExpenseAmount(_amountController.text,
        decimalPlaces: _decimalPlaces, maxAmount: _maxAmount);
    // In edit mode the existing receipt is preserved server-side
    // when we omit the attachment field. So a new pick is OPTIONAL
    // even when the dev flag would normally require one.
    final receiptOk = widget.isEditing
        ? true
        : !DevConstants.requireReceiptOnExpense || _receiptBytes != null;
    return _selectedCategory != null &&
        _descriptionController.text.trim().isNotEmpty &&
        parsed != null &&
        receiptOk &&
        !_submitting;
  }

  /// Inline amount-field error. Only shown once the user has typed
  /// something — we don't shout "Amount is required." on first open.
  String? get _amountInlineError {
    if (_amountController.text.trim().isEmpty) return null;
    return _parseExpenseAmount(_amountController.text,
            decimalPlaces: _decimalPlaces, maxAmount: _maxAmount)
        .$2;
  }

  /// The "≈ $ 42.10 (estimate)" line under the amount field, or the
  /// [kRateNotConfigured] sentinel for a foreign currency with no
  /// configured rate. Null hides the row entirely.
  String? get _conversionLine => conversionPreview(
      _amountController.text, _selectedCurrency, _currencyList);

  String _humanize(String code) {
    switch (code) {
      case 'missing_receipt':
        return 'Receipt is required.';
      case 'missing_fields':
        return 'Please fill in all fields.';
      case 'invalid_fields':
        return 'Check your inputs and try again.';
      case 'invalid_category':
        return 'That category is not available for your company.';
      case 'invalid_amount':
        return 'Amount must be greater than zero.';
      case 'no_currency':
        return 'Your company has no currency configured.';
      case 'currency_invalid':
        return 'That currency is not enabled for your company. '
            'Pick another or ask your administrator.';
      case 'attachment_too_large':
        return 'Receipt is too large. Try a smaller image.';
      case 'invalid_attachment':
      case 'invalid_attachment_encoding':
        return 'Could not attach the receipt. Try a different image.';
      default:
        return 'Submit failed. Please try again or contact your '
            'administrator.';
    }
  }

  String _humanizeOcr(String code) {
    switch (code) {
      case 'ollama_unreachable':
        return 'OCR server is offline. Please fill in manually.';
      case 'ollama_timeout':
        return 'OCR took too long. Please fill in manually.';
      case 'ollama_bad_response':
        return 'OCR returned an unexpected reply. Please fill in manually.';
      case 'image_too_large':
        return 'Receipt image is too large to scan.';
      case 'invalid_image':
        return 'Could not read the receipt image.';
      default:
        return 'Could not scan the receipt. Please fill in manually.';
    }
  }

  /// Send the attached receipt to the connector for VLM auto-fill.
  /// Always overwrites the form fields — the user explicitly tapped
  /// "Scan receipt" so partial-fill gating would be confusing.
  /// Server-side validation guarantees amount/date/category are sane
  /// or null, so we just need to apply what came back.
  Future<void> _scanReceipt() async {
    if (_receiptBytes == null || _scanning) return;
    // For a PDF receipt we OCR the rasterized page images, not the raw
    // PDF bytes (the VLM can't read a PDF). If rasterization produced no
    // pages, Scan isn't offered — but guard anyway.
    if (_receiptIsPdf && _pdfPages.isEmpty) return;
    final session = context.read<SessionService>();
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final ocr = _receiptIsPdf
          ? await api.scanReceiptPages(pages: _pdfPages)
          : await api.scanReceipt(
              bytes: _receiptBytes!,
              mimetype: _receiptMime,
            );
      if (!mounted) return;
      // Match the suggested category against the loaded list. If the
      // server's id isn't in our local list (race window where the
      // admin changed categories mid-session) we just leave the
      // current selection alone.
      ExpenseCategory? matched;
      if (ocr.suggestedCategoryId != null) {
        for (final c in _categories) {
          if (c.id == ocr.suggestedCategoryId) {
            matched = c;
            break;
          }
        }
      }
      final parsedDate =
          ocr.date.isEmpty ? null : DateTime.tryParse(ocr.date);
      // Match OCR-detected currency against the active list.
      CurrencyOption? ocrCurrency;
      String? currencyNotice;
      if (ocr.currency.isNotEmpty && _showCurrencyPicker) {
        ocrCurrency = matchOcrCurrency(ocr.currency, _currencyList);
        if (ocrCurrency != null) {
          currencyNotice = '${ocrCurrency.info.code} detected from receipt.';
        } else {
          final companyCode =
              _currencyList?.companyOption?.info.code ?? '';
          currencyNotice =
              'Receipt currency ${ocr.currency.toUpperCase()} is not '
              'enabled; amount recorded in $companyCode.';
        }
      }
      // OCR amounts can be way off (misread decimals, embedded year as
      // amount, etc.). Validate before applying so we don't pre-fill
      // garbage the user then has to clear.
      bool ocrAmountValid = false;
      if (ocr.amount != null) {
        final (v, _) = _parseExpenseAmount(
            ocr.amount!.toStringAsFixed(2),
            decimalPlaces: ocrCurrency?.info.decimalPlaces ?? _decimalPlaces,
            maxAmount: amountCapFor(ocrCurrency ?? _selectedCurrency, _currencyList));
        ocrAmountValid = v != null;
      }
      setState(() {
        if (ocr.description.isNotEmpty) {
          _descriptionController.text = ocr.description;
        }
        if (ocrAmountValid) {
          _amountController.text = ocr.amount!.toStringAsFixed(2);
        }
        if (parsedDate != null) _selectedDate = parsedDate;
        if (matched != null) _selectedCategory = matched;
        if (ocrCurrency != null) _selectedCurrency = ocrCurrency;
      });
      // The model reads all pages together and returns one total (the
      // same receipt split across pages isn't double-counted; separate
      // receipts are summed). Nudge the user to verify either way.
      final scanMsg = ocr.pagesScanned > 1
          ? 'Scanned ${ocr.pagesScanned} pages. Please check the amount '
              'before submitting.'
          : 'Receipt scanned. Please review before submitting.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scanMsg),
          duration: const Duration(seconds: 4),
        ),
      );
      if (ocr.amount != null && !ocrAmountValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'OCR amount looks invalid. Please enter manually.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      if (currencyNotice != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currencyNotice),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanizeOcr(e.errorCode)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not scan: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final session = context.read<SessionService>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final amount = double.parse(_amountController.text.trim());
      final dateStr = _selectedDate.toIso8601String().substring(0, 10);
      final hasReceipt = _receiptBytes != null;
      final selected = _selectedCurrency;
      final sendCurrencyId =
          (selected != null && !selected.isCompanyCurrency)
              ? selected.info.id
              : null;
      final r = widget.editingRecord;
      if (r != null) {
        // Edit mode: only the new receipt (if any) is sent; the
        // server preserves the existing one when attachment is omitted.
        // Currency is trickier: omitting the key means "keep the
        // existing currency", which is correct when unchanged — but
        // if the record WAS foreign and the user switched back to
        // company currency, the server must be told explicitly.
        final modifyCurrencyId = (selected != null &&
                selected.info.id != r.origCurrency.id &&
                (r.origCurrency.id != 0 || !selected.isCompanyCurrency))
            ? selected.info.id
            : sendCurrencyId;
        await api.modifyExpense(
          expenseId: r.id,
          productId: _selectedCategory!.id,
          name: _descriptionController.text.trim(),
          totalAmount: amount,
          date: dateStr,
          paymentMode: _paymentMode,
          currencyId: modifyCurrencyId,
          attachmentName: hasReceipt
              ? (_receiptName.isEmpty ? 'receipt.jpg' : _receiptName)
              : null,
          attachmentMimeType: hasReceipt ? _receiptMime : null,
          attachmentDataB64:
              hasReceipt ? base64Encode(_receiptBytes!) : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      await api.submitExpense(
        productId: _selectedCategory!.id,
        name: _descriptionController.text.trim(),
        totalAmount: amount,
        date: dateStr,
        paymentMode: _paymentMode,
        currencyId: sendCurrencyId,
        attachmentName: hasReceipt
            ? (_receiptName.isEmpty ? 'receipt.jpg' : _receiptName)
            : null,
        attachmentMimeType: hasReceipt ? _receiptMime : null,
        attachmentDataB64: hasReceipt ? base64Encode(_receiptBytes!) : null,
        devSkipReceipt: !hasReceipt && !DevConstants.requireReceiptOnExpense,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = _humanize(e.errorCode));
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Expense' : 'New Expense'),
      ),
      // Bottom inset is owned by HomeShell's persistent NavigationBar
      // (this screen is pushed into a per-tab Navigator). No system-nav
      // math needed here — the page's bottom is the NavigationBar's top.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // OCR-first order: receipt at the top so a user can scan
          // before manually typing anything. Date next (most useful
          // post-scan sanity check), then Amount / Category /
          // Description / Paid By. Submit anchors the bottom.
          children: [
            _receiptField(),
            const SizedBox(height: 16),
            _dateField(),
            const SizedBox(height: 16),
            if (_showCurrencyPicker)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Amount',
                      controller: _amountController,
                      prefixIcon: Icons.attach_money_rounded,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        _AmountInputFormatter(
                            decimalPlaces: _decimalPlaces,
                            maxIntDigits: _maxIntDigits),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<CurrencyOption>(
                      initialValue: _selectedCurrency,
                      items: [
                        for (final c in _currencyList!.currencies)
                          DropdownMenuItem(
                            value: c,
                            child: Text(c.info.code),
                          ),
                      ],
                      onChanged: (c) =>
                          setState(() => _selectedCurrency = c),
                    ),
                  ),
                ],
              )
            else
              LabeledField(
                label: 'Amount',
                controller: _amountController,
                prefixIcon: Icons.attach_money_rounded,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  _AmountInputFormatter(
                      decimalPlaces: _decimalPlaces,
                      maxIntDigits: _maxIntDigits),
                ],
                onChanged: (_) => setState(() {}),
              ),
            if (_amountInlineError != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text(
                  _amountInlineError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.error,
                  ),
                ),
              ),
            if (_conversionLine != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text(
                  _conversionLine == kRateNotConfigured
                      ? 'Exchange rate not configured — the reimbursed '
                          'amount will be set by your administrator.'
                      : _conversionLine!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _categoryField(),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Description',
              controller: _descriptionController,
              prefixIcon: Icons.subject_rounded,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _paidByField(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _errorBanner(_error!),
            ],
            const SizedBox(height: 32),
            PrimaryButton(
              label: widget.isEditing ? 'UPDATE EXPENSE' : 'SUBMIT EXPENSE',
              icon: _submitting
                  ? null
                  : (widget.isEditing
                      ? Icons.save_rounded
                      : Icons.send_rounded),
              loading: _submitting,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryField() {
    if (_loadingCategories) {
      return _wrap(
        label: 'CATEGORY',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
      );
    }
    // The fetch FAILED (offline / server error) — say so plainly and
    // offer Retry. Do NOT show "ask your administrator", which would
    // wrongly blame configuration for what is really a connection issue.
    if (_categoryError != null) {
      return _wrap(
        label: 'CATEGORY',
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _categoryError!,
                style:
                    TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _loadCategories,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    // The fetch SUCCEEDED but the company genuinely has no categories.
    if (_categories.isEmpty) {
      return _wrap(
        label: 'CATEGORY',
        child: Text(
          'No expense categories available for your company. '
          'Ask your administrator to set them up.',
          style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return _wrap(
      label: 'CATEGORY',
      child: DropdownButton<ExpenseCategory>(
        value: _selectedCategory,
        hint: const Text('Select a category'),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: _categories
            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
            .toList(),
        onChanged: (c) => setState(() => _selectedCategory = c),
      ),
    );
  }

  Widget _dateField() {
    final iso = _selectedDate.toIso8601String().substring(0, 10);
    return _wrap(
      label: 'DATE',
      child: InkWell(
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 18, color: AppTheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(iso, style: const TextStyle(fontSize: 15)),
              const Spacer(),
              Icon(Icons.edit_rounded,
                  size: 16, color: AppTheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paidByField() {
    return _wrap(
      label: 'PAID BY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paidByOption(
            value: 'own_account',
            title: 'Employee (to reimburse)',
          ),
          _paidByOption(
            value: 'company_account',
            title: 'Company',
          ),
        ],
      ),
    );
  }

  Widget _paidByOption({required String value, required String title}) {
    final selected = _paymentMode == value;
    return InkWell(
      onTap: () => setState(() => _paymentMode = value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? AppTheme.primary : AppTheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptField() {
    final isEditing = widget.isEditing;
    final session = context.watch<SessionService>();
    final aiDisabled = !session.featureExpenseOcr;
    final label = isEditing
        ? 'RECEIPT'
        : (DevConstants.requireReceiptOnExpense
            ? 'RECEIPT (REQUIRED)'
            : 'RECEIPT (DEV: OPTIONAL)');
    final body = _receiptBytes == null
        ? _buildReceiptEmpty(isEditing)
        : _buildReceiptAttached();
    return _wrap(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (aiDisabled) ...[
            Text(
              'AI receipt scanning is disabled by your subscription.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          body,
        ],
      ),
    );
  }

  /// Empty state: wide "Attach receipt" button + (when OCR is
  /// enabled in this build) a compact disabled Scan affordance. The
  /// disabled Scan is intentional — it tells the user "scanning is a
  /// thing here" before they have a photo to scan.
  Widget _buildReceiptEmpty(bool isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isEditing) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  size: 16,
                  color: AppTheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Existing receipt attached',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(
                  isEditing ? 'Replace with camera' : 'Attach receipt',
                ),
                onPressed: _pickReceiptFromCamera,
              ),
            ),
            if (DevConstants.enableOcrScan &&
                context.watch<SessionService>().featureExpenseOcr) ...[
              const SizedBox(width: 8),
              _buildScanButton(),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _pickReceiptFromLibrary,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'or pick from library',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Attached state: thumbnail + filename / Replace row + full-width
  /// Scan as the next prominent action.
  Widget _buildReceiptAttached() {
    // Scan is offered only when there's something the VLM can read:
    // an image, or a PDF we successfully rasterized to page images.
    final scanReadable = !_receiptIsPdf || _pdfPages.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReceiptPreview(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _receiptName.isEmpty ? 'receipt' : _receiptName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: _pickReceiptFromLibrary,
              child: const Text('Replace'),
            ),
          ],
        ),
        if (scanReadable &&
            DevConstants.enableOcrScan &&
            context.watch<SessionService>().featureExpenseOcr) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _buildScanButton(),
          ),
        ],
      ],
    );
  }

  /// The preview box, chosen by attachment type:
  /// - image: the image itself
  /// - PDF (rasterized): page-1 thumbnail + an "N pages" badge
  /// - PDF (rasterizing): a spinner placeholder
  /// - PDF (raster failed): a generic PDF file-chip (still uploads fine)
  Widget _buildReceiptPreview() {
    if (!_receiptIsPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _receiptBytes!,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_rasterizingPdf) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const CircularProgressIndicator(),
      );
    }
    if (_pdfPages.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.memory(
              _pdfPages.first,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            if (_pdfPageCount > 1)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '$_pdfPageCount pages',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    // Rasterization failed — show a file-chip. The PDF still uploads.
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf_rounded,
              size: 32, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PDF attached',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Preview unavailable — the file will still be uploaded.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One Scan button definition for both states. Disabled when there
  /// is no receipt yet OR while a scan is in flight. Spinner+label
  /// swap to communicate the in-flight state. Only rendered when
  /// `session.featureExpenseOcr` is true — call sites filter; this
  /// function never sees the AI-disabled case.
  Widget _buildScanButton() {
    final hasReceipt = _receiptBytes != null;
    final enabled = hasReceipt && !_scanning;
    return OutlinedButton.icon(
      icon: _scanning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_rounded),
      label: Text(
        _scanning
            ? 'Scanning…'
            : (hasReceipt ? 'Scan receipt' : 'Scan'),
      ),
      onPressed: enabled ? _scanReceipt : null,
    );
  }

  Widget _wrap({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _errorBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
