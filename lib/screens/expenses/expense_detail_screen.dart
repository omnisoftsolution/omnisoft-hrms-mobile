import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/datetime_utils.dart';
import '../../core/money.dart';
import '../../models/expense_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/file_viewer.dart';
import 'expense_create_screen.dart';

/// Read-only detail view. When the expense is still pending approval
/// (state in {draft, submitted}) we surface an Edit action that
/// pushes ExpenseCreateScreen in edit mode; on a successful update
/// the screen pops `true` so the parent list refreshes.
class ExpenseDetailScreen extends StatelessWidget {
  final ExpenseRecord record;
  const ExpenseDetailScreen({super.key, required this.record});

  bool get _isModifiable =>
      record.state == 'draft' || record.state == 'submitted';

  /// Same gate as edit — pre-approval expenses can be hard-deleted.
  /// Approved / posted / refused stay so HR has a record.
  bool get _isDeletable => _isModifiable;

  Future<void> _openEdit(BuildContext context) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseCreateScreen(editingRecord: record),
      ),
    );
    if (updated == true && context.mounted) {
      // Bubble the refresh signal up to the list. The detail screen
      // itself will be rebuilt next time the user opens it via the
      // refreshed list.
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          'This will permanently remove '
          '"${record.name.isEmpty ? "this expense" : record.name}". '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final session = context.read<SessionService>();
    final api = OmniMobileApi(
      baseUrl: session.clientUrl,
      db: session.clientDb,
      token: session.token,
    );
    try {
      await api.deleteExpense(record.id);
      if (!context.mounted) return;
      Navigator.of(context).pop(true); // refresh signal up to list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted.')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      // Prefer the server's `message` field when present — Odoo's
      // own ValidationError text is far more useful than our canned
      // humanizer for unanticipated constraint failures.
      final serverMsg = e.data?['message']?.toString();
      final msg = (serverMsg != null && serverMsg.isNotEmpty)
          ? serverMsg
          : _humanizeDeleteError(e.errorCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  String _humanizeDeleteError(String code) {
    switch (code) {
      case 'invalid_state':
        return 'This expense is past the deletable stage.';
      case 'not_owner':
        return 'You can only delete your own expenses.';
      case 'cannot_delete':
        return 'Server rejected the delete. Please contact HR.';
      case 'not_found':
        return 'This expense no longer exists.';
      default:
        return 'Could not delete this expense. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          if (_isModifiable)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _openEdit(context),
            ),
          if (_isDeletable)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppTheme.error),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _stateColor(record.state).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                record.stateLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _stateColor(record.state),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _formatAmount(),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (record.state == 'refused' &&
              record.refuseReason.isNotEmpty) ...[
            _refuseBanner(),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildDetailRows(),
              ),
            ),
          ),
          if (record.attachments.isNotEmpty) ...[
            const SizedBox(height: 24),
            _receiptHeader(),
            const SizedBox(height: 8),
            for (final att in record.attachments)
              _AttachmentCard(parent: this, att: att),
          ],
        ],
      ),
    );
  }

  Widget _refuseBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, color: AppTheme.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REFUSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reason: ${record.refuseReason}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptHeader() {
    return Text(
      'RECEIPT',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppTheme.onSurfaceVariant,
      ),
    );
  }

  // _attachmentCard was inlined here; rendering now lives in the
  // private _AttachmentCard StatefulWidget below so each card owns
  // its own cached Future. Without that, every parent rebuild (scroll,
  // focus, etc.) triggered a fresh getExpenseAttachment network call.

  Widget _imagePreview(
      BuildContext context, ExpenseAttachment att, String dataB64) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(dataB64);
    } catch (_) {
      // Fall through to file fallback if bytes are malformed.
    }
    if (bytes == null) {
      return _placeholderCard(
        child: _fileFallback(context, att, dataB64: dataB64),
      );
    }
    final imageBytes = bytes;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final err = await openBase64File(
            name: att.name.isEmpty ? 'receipt.jpg' : att.name,
            dataB64: dataB64);
        if (err != null && context.mounted) {
          showFileViewError(context, err);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: AppTheme.surfaceContainer,
          constraints: const BoxConstraints(maxHeight: 320),
          width: double.infinity,
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _placeholderCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _fileFallback(BuildContext context, ExpenseAttachment att,
      {String? dataB64, String? reason}) {
    return Row(
      children: [
        Icon(Icons.description_outlined, color: AppTheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                att.name.isEmpty ? 'Receipt' : att.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reason ??
                    '${att.mimetype.isEmpty ? "file" : att.mimetype}'
                        ' · ${att.sizeLabel}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (dataB64 != null && dataB64.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('VIEW'),
            onPressed: () async {
              final err = await openBase64File(
                  name: att.name.isEmpty ? 'receipt' : att.name,
                  dataB64: dataB64);
              if (err != null && context.mounted) {
                showFileViewError(context, err);
              }
            },
          ),
      ],
    );
  }

  String _formatAmount() =>
      MoneyFormatter.format(record.origAmount, record.origCurrency);

  /// Build the detail rows with a divider between each one. Tax rows
  /// only render when Odoo actually applied a tax (taxAmount > 0).
  List<Widget> _buildDetailRows() {
    final entries = <List<String>>[
      ['Description', record.name.isEmpty ? '—' : record.name],
      [
        'Category',
        record.productName.isEmpty ? '—' : record.productName,
      ],
      [
        'Date',
        record.date.isEmpty
            ? '—'
            : DateTimeUtils.formatLocalDate(record.date),
      ],
      ['Paid By', record.paymentModeLabel],
    ];
    if (record.isForeignCurrency) {
      entries.add([
        'Reimbursed as',
        MoneyFormatter.format(record.totalAmount, record.currency),
      ]);
    }
    if (record.taxAmount > 0) {
      entries.add(['Untaxed', MoneyFormatter.format(record.untaxedAmount, record.currency)]);
      entries.add(['Inc. tax', MoneyFormatter.format(record.taxAmount, record.currency)]);
    }
    // "Receipt attached" row removed — the inline preview below the
    // card makes the boolean redundant.

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) rows.add(const Divider(height: 24));
      rows.add(_row(entries[i][0], entries[i][1]));
    }
    return rows;
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.onSurfaceVariant, fontSize: 13)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'draft':
        return AppTheme.onSurfaceVariant;
      case 'submitted':
        return AppTheme.secondary;
      case 'approved':
      case 'posted':
      case 'in_payment':
        return AppTheme.primary;
      case 'paid':
        return const Color(0xFF22C55E);
      case 'refused':
        return AppTheme.error;
      default:
        return AppTheme.onSurfaceVariant;
    }
  }
}

/// Per-attachment renderer owning a single cached Future. The parent
/// StatelessWidget can't memoize the future itself (no State to store
/// it on), so wrapping each attachment in a State-backed widget gives
/// us a stable Future across rebuilds. Parent rebuilds (scroll, focus,
/// etc.) no longer refire `getExpenseAttachment`.
class _AttachmentCard extends StatefulWidget {
  final ExpenseDetailScreen parent;
  final ExpenseAttachment att;
  const _AttachmentCard({required this.parent, required this.att});

  @override
  State<_AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<_AttachmentCard> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionService>();
    final api = OmniMobileApi(
      baseUrl: session.clientUrl,
      db: session.clientDb,
      token: session.token,
    );
    _future = api.getExpenseAttachment(widget.att.id);
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.att;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return widget.parent._placeholderCard(
              child: const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (snap.hasError || snap.data == null) {
            return widget.parent._placeholderCard(
              child: widget.parent._fileFallback(
                  context, att, dataB64: null,
                  reason: 'Could not load receipt.'),
            );
          }
          final dataB64 = snap.data!['data_b64']?.toString() ?? '';
          if (att.isImage && dataB64.isNotEmpty) {
            return widget.parent._imagePreview(context, att, dataB64);
          }
          return widget.parent._placeholderCard(
            child: widget.parent._fileFallback(context, att, dataB64: dataB64),
          );
        },
      ),
    );
  }
}
