import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/expense_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';

// MVP cap for a single expense submission. Big enough for almost any
// SGD/USD expense, small enough that bad input ("1e25") is unambiguous.
// TODO(configurable_limit): move to
// ir.config_parameter("omni_hrms_mobile.expense_max_amount") if a
// customer ever needs a higher cap.
const double _kExpenseAmountMax = 99999.99;

/// Returns (parsed value, error). When error != null the value is
/// null. Empty input gets its own error so the disabled-submit state
/// and the inline message stay in sync. The backend runs the same
/// rules in Decimal — see controllers/main.py `_validate_expense_amount`.
(double?, String?) _parseExpenseAmount(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (null, 'Amount is required.');
  if (s.contains(RegExp(r'[eE,]'))) {
    return (null,
        'Enter a valid amount up to 99,999.99 with max 2 decimals.');
  }
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) {
    return (null,
        'Enter a valid amount up to 99,999.99 with max 2 decimals.');
  }
  if (v <= 0) return (null, 'Amount must be greater than zero.');
  if (v > _kExpenseAmountMax) {
    return (null,
        'Enter a valid amount up to 99,999.99 with max 2 decimals.');
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    return (null, 'Max 2 decimal places.');
  }
  return (v, null);
}

/// Rejects any keystroke that would leave the field in an invalid
/// state — bounds the input to "up to 5 digits + optional .DD". The
/// runtime parser still has the final say (catches blank, leading
/// dot, etc.).
class _AmountInputFormatter extends TextInputFormatter {
  static final _re = RegExp(r'^\d{0,5}(\.\d{0,2})?$');
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

  bool _loadingCategories = true;
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
      _amountController.text = r.totalAmount.toStringAsFixed(2);
      _paymentMode = r.paymentMode;
      final parsedDate = DateTime.tryParse(r.date);
      if (parsedDate != null) _selectedDate = parsedDate;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final session = context.read<SessionService>();
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
        _error = 'Could not load categories: $e';
      });
    }
  }

  /// Camera is the primary "Attach receipt" action — receipts are
  /// usually paper in front of you. Library is the secondary link
  /// for receipts that arrived via email. Both pipe through the same
  /// state setter.
  Future<void> _pickReceiptFromCamera() => _pickReceipt(ImageSource.camera);
  Future<void> _pickReceiptFromLibrary() =>
      _pickReceipt(ImageSource.gallery);

  Future<void> _pickReceipt(ImageSource source) async {
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
      setState(() {
        _receiptBytes = bytes;
        _receiptName = xfile.name;
        _receiptMime = _mimeFromName(xfile.name);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not pick a receipt: $e');
    }
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
    final (parsed, _) = _parseExpenseAmount(_amountController.text);
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
    return _parseExpenseAmount(_amountController.text).$2;
  }

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
      final ocr = await api.scanReceipt(
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
      // OCR amounts can be way off (misread decimals, embedded year as
      // amount, etc.). Validate before applying so we don't pre-fill
      // garbage the user then has to clear.
      bool ocrAmountValid = false;
      if (ocr.amount != null) {
        final (v, _) =
            _parseExpenseAmount(ocr.amount!.toStringAsFixed(2));
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
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Receipt scanned. Please review before submitting.'),
          duration: Duration(seconds: 3),
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
      final r = widget.editingRecord;
      if (r != null) {
        // Edit mode: only the new receipt (if any) is sent; the
        // server preserves the existing one when attachment is omitted.
        await api.modifyExpense(
          expenseId: r.id,
          productId: _selectedCategory!.id,
          name: _descriptionController.text.trim(),
          totalAmount: amount,
          date: dateStr,
          paymentMode: _paymentMode,
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
      setState(() => _error = 'Submit failed: $e');
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
            LabeledField(
              label: 'Amount',
              controller: _amountController,
              prefixIcon: Icons.attach_money_rounded,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              inputFormatters: [_AmountInputFormatter()],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _receiptBytes!,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
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
              onPressed: _pickReceiptFromCamera,
              child: const Text('Replace'),
            ),
          ],
        ),
        if (DevConstants.enableOcrScan &&
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
