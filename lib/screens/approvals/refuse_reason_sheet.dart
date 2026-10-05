import 'package:flutter/material.dart';

import '../../core/error_messages.dart';
import '../../core/theme.dart';

/// Limits the connector enforces on a refusal reason (after trimming).
const int kRefuseReasonMin = 3;
const int kRefuseReasonMax = 500;

/// Opens the "Refuse this request" sheet. Returns true when the refusal
/// was submitted, false when the approver cancelled.
///
/// [onSubmit] gets the trimmed reason. It returns null when the sheet
/// should close (the caller then handles the outcome), or a message to
/// show under the field, in which case the sheet stays open.
Future<bool> showRefuseReasonSheet(
  BuildContext context, {
  required String employeeName,
  required Future<String?> Function(String reason) onSubmit,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // HomeShell owns the bottom nav and each tab has its own Navigator:
    // the root navigator puts the sheet above the nav bar.
    useRootNavigator: true,
    // No drag-to-dismiss: a drag would bypass the in-flight lock below.
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        RefuseReasonSheet(employeeName: employeeName, onSubmit: onSubmit),
  );
  return submitted == true;
}

class RefuseReasonSheet extends StatefulWidget {
  const RefuseReasonSheet({
    super.key,
    required this.employeeName,
    required this.onSubmit,
  });

  final String employeeName;
  final Future<String?> Function(String reason) onSubmit;

  @override
  State<RefuseReasonSheet> createState() => _RefuseReasonSheetState();
}

class _RefuseReasonSheetState extends State<RefuseReasonSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _serverError;

  String get _reason => _controller.text.trim();

  bool get _valid =>
      _reason.length >= kRefuseReasonMin && _reason.length <= kRefuseReasonMax;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _serverError = null;
    });
    String? message;
    try {
      message = await widget.onSubmit(_reason);
    } catch (e) {
      message = friendlyError(e);
    }
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _serverError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // While the refusal is in flight the sheet cannot be closed (back
    // button, barrier tap), so the result always reaches the caller.
    return PopScope(
      canPop: !_busy,
      child: Padding(
        // viewInsets = keyboard; viewPadding = system nav inset (the
        // sheet renders above the bottom nav via the root navigator).
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, mq.viewInsets.bottom + mq.viewPadding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Refuse this request',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.employeeName} will see your reason in the app and in Odoo.',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              maxLength: kRefuseReasonMax,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _serverError = null),
              decoration: InputDecoration(
                hintText: 'Reason (required)',
                errorText: _serverError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.onSurfaceVariant,
                      side: const BorderSide(
                          color: AppTheme.outlineVariant, width: 1.5),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (_valid && !_busy) ? _submit : null,
                    child: const Text('Refuse'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
