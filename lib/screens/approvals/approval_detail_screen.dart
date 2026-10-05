import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/approval_detail.dart';
import '../../models/leave_record.dart' show LeaveAttachment;
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/employee_avatar.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/file_viewer.dart';
import 'refuse_reason_sheet.dart';

/// One leave request, as an approver sees it: who, what, when, the
/// approval steps, attachments, and Approve / Refuse.
///
/// The buttons follow the connector's `can_approve` / `can_refuse` flags
/// (computed by Odoo as this user) and disappear once the state is
/// final. Pops with `true` after a decision or when the request is gone,
/// so the list behind it reloads.
class ApprovalDetailScreen extends StatefulWidget {
  const ApprovalDetailScreen({super.key, required this.leaveId, this.apiBuilder});

  final int leaveId;

  /// Test seam: builds the API client from the session. Defaults to the
  /// real [OmniMobileApi] for the session's company and token.
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  @override
  State<ApprovalDetailScreen> createState() => _ApprovalDetailScreenState();
}

class _ApprovalDetailScreenState extends State<ApprovalDetailScreen> {
  late final SessionService _session;
  late final OmniMobileApi _api;
  ApprovalDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = context.read<SessionService>();
    _api = widget.apiBuilder?.call(_session) ??
        OmniMobileApi(
          baseUrl: _session.clientUrl,
          db: _session.clientDb,
          token: _session.token,
        );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _api.getApprovalDetail(widget.leaveId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (e is ApiException && e.errorCode == 'not_found') {
        // The request is gone: the pending count may be stale too.
        _refreshCount();
        if (!mounted) return;
        _toast(friendlyError(e), error: true);
        Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppTheme.error : AppTheme.primary,
      ));
  }

  /// Re-pull /me so `leaveApprovalsPendingCount` (Home card, My day row)
  /// is right after anything that may have changed it. Fire-and-forget.
  void _refreshCount() => unawaited(_session.refreshMe());

  /// A decision went through: toast, refresh the count, back to the list.
  void _finish(String message) {
    _refreshCount();
    if (!mounted) return;
    _toast(message);
    Navigator.of(context).pop(true);
  }

  Future<void> _onDecisionError(Object e) async {
    final code = e is ApiException ? e.errorCode : '';
    if (code == 'not_found') {
      _refreshCount();
      if (!mounted) return;
      _toast(friendlyError(e), error: true);
      Navigator.of(context).pop(true);
      return;
    }
    if (code == 'state_changed' || code == 'not_allowed') {
      _refreshCount();
      if (!mounted) return;
      _toast(friendlyError(e), error: true);
      // Reload: the fresh can_* flags and state hide the buttons.
      await _load();
      return;
    }
    if (!mounted) return;
    // Anything else (no network, or Odoo refused the change with a
    // validation message): say so, the request stays as it was.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request not changed'),
        content: Text(friendlyDecisionError(e)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _approve() async {
    final item = _detail!.item;
    setState(() => _busy = true);
    try {
      final state = await _api.approveLeave(
          leaveId: item.id, expectedState: item.state);
      _finish(state == 'validate1'
          ? 'Approved · now waiting for HR'
          : 'Approved');
    } catch (e) {
      await _onDecisionError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refuse() async {
    final item = _detail!.item;
    var refused = false;
    Object? failure;
    final submitted = await showRefuseReasonSheet(
      context,
      employeeName: item.employeeName,
      onSubmit: (reason) async {
        try {
          await _api.refuseLeave(
              leaveId: item.id, expectedState: item.state, reason: reason);
          refused = true;
          return null;
        } on ApiException catch (e) {
          // Errors the approver can fix or retry inside the sheet: the
          // sheet stays open and the typed reason is kept.
          if (e.errorCode == 'reason_required' ||
              e.errorCode == 'network_error' ||
              e.errorCode == 'timeout') {
            return friendlyError(e);
          }
          failure = e;
          return null;
        } catch (e) {
          failure = e;
          return null;
        }
      },
    );
    if (!submitted) return;
    if (refused) {
      _finish('Refused');
      return;
    }
    final f = failure;
    if (f != null) await _onDecisionError(f);
  }

  Future<void> _openAttachment(LeaveAttachment a) async {
    try {
      final res = await _api.getAttachment(a.id);
      final dataB64 = (res['data_b64'] ?? '').toString();
      if (dataB64.isEmpty) {
        if (mounted) showFileViewError(context, 'the file is empty.');
        return;
      }
      final err = await openBase64File(name: a.name, dataB64: dataB64);
      if (err != null && mounted) showFileViewError(context, err);
    } catch (e) {
      if (mounted) showFileViewError(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Request')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [ErrorStateView(message: _error!, onRetry: _load)],
      );
    }
    final d = _detail!;
    final item = d.item;
    final showApprove = item.isPending && item.canApprove;
    final showRefuse = item.isPending && item.canRefuse;
    final subtitle = [
      if (item.department.isNotEmpty) item.department,
      if (d.resourceCalendar.isNotEmpty) d.resourceCalendar,
    ].join(' · ');
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // viewPadding (not SafeArea): the system inset below the last
        // button, whatever an ancestor did to MediaQuery.padding.
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.viewPaddingOf(context).bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card([
              Row(
                children: [
                  EmployeeAvatar(
                      avatarB64: d.avatarB64, name: item.employeeName, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.employeeName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _kv('Type', item.leaveTypeName),
              _kv('Dates', item.datesLabel),
              _kv('Duration', item.durationLong),
              if (d.balanceAfter != null)
                _kv('Balance after', d.balanceAfter!.label),
              if (d.note.isNotEmpty) _kv('Note', d.note),
            ]),
            if (d.steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card([
                _sectionLabel('Approval steps'),
                const SizedBox(height: 8),
                for (final s in d.steps) _stepRow(s),
              ]),
            ],
            if (d.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card([
                _sectionLabel('Attachments'),
                const SizedBox(height: 4),
                for (final a in d.attachments) _attachmentRow(a),
              ]),
            ],
            if (showApprove || showRefuse) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  if (showRefuse)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(
                              color: AppTheme.error, width: 1.5),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : _refuse,
                        child: const Text('Refuse'),
                      ),
                    ),
                  if (showRefuse && showApprove) const SizedBox(width: 12),
                  if (showApprove)
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.onPrimary,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : _approve,
                        child: const Text('Approve'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.glassShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppTheme.onSurfaceVariant,
        ),
      );

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                key,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, color: AppTheme.onSurface),
              ),
            ),
          ],
        ),
      );

  Widget _stepRow(ApprovalStep s) {
    final Color dot = s.isRefused
        ? AppTheme.error
        : s.isDone
            ? AppTheme.primary
            : s.isCurrent
                ? AppTheme.secondary
                : AppTheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            s.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurface,
            ),
          ),
          if (s.subtitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.subtitle,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentRow(LeaveAttachment a) => InkWell(
        onTap: () => _openAttachment(a),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.description_outlined,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${a.name} · ${a.sizeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppTheme.primary),
                ),
              ),
            ],
          ),
        ),
      );
}
