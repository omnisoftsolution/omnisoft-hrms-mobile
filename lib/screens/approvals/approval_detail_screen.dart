import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/omni_colors.dart';
import '../../models/approval_detail.dart';
import '../../models/leave_record.dart' show LeaveAttachment;
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/busy_button_label.dart';
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
    final c = context.omni;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? c.errorFill : c.brandFill,
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
    if (code == 'server_error') {
      // The server may have saved the decision and failed after it
      // (connector 2.65.3 answers server_error when its commit raised), so
      // never say "not changed": show the request as it is now.
      _refreshCount();
      if (!mounted) return;
      _toast("Couldn't confirm the result. Showing the latest.", error: true);
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
      // Stop "Approving…" before the error is shown, not after it closes.
      if (mounted) setState(() => _busy = false);
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
      backgroundColor: context.omni.background,
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
    final c = context.omni;
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
            _card(c, [
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 12, color: c.textSub),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _kv(c, 'Type', item.leaveTypeName),
              _kv(c, 'Dates', item.datesLabel),
              _kv(c, 'Duration', item.durationLong),
              if (d.balanceAfter != null)
                _kv(c, 'Balance after', d.balanceAfter!.label),
              if (d.note.isNotEmpty) _kv(c, 'Note', d.note),
            ]),
            if (d.steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(c, [
                _sectionLabel(c, 'Approval steps'),
                const SizedBox(height: 8),
                for (final s in d.steps) _stepRow(c, s),
              ]),
            ],
            if (d.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(c, [
                _sectionLabel(c, 'Attachments'),
                const SizedBox(height: 4),
                for (final a in d.attachments) _attachmentRow(c, a),
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
                          foregroundColor: c.error,
                          side: BorderSide(color: c.error, width: 1.5),
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
                          backgroundColor: c.brandFill,
                          foregroundColor: Colors.white,
                          // In flight: keep the button's colours so the
                          // spinner reads as "working", not "disabled".
                          disabledBackgroundColor: _busy ? c.brandFill : null,
                          disabledForegroundColor: _busy ? Colors.white : null,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : _approve,
                        child: BusyButtonLabel(
                            busy: _busy,
                            label: 'Approve',
                            busyLabel: 'Approving…'),
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

  Widget _card(OmniColors c, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _sectionLabel(OmniColors c, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: c.textSub,
        ),
      );

  Widget _kv(OmniColors c, String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                key,
                style: TextStyle(fontSize: 13, color: c.textSub),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontSize: 13, color: c.text),
              ),
            ),
          ],
        ),
      );

  Widget _stepRow(OmniColors c, ApprovalStep s) {
    final Color dot = s.isRefused
        ? c.error
        : s.isDone
            ? c.accent
            : s.isCurrent
                ? c.secondary
                : c.line;
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
          // Title, then who: on one line when both fit, else the subtitle
          // moves under the title. A long current-step title ("Waiting for
          // Christopher +1 (manager)") wraps instead of overflowing.
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                if (s.subtitle.isNotEmpty)
                  Text(
                    s.subtitle,
                    style: TextStyle(fontSize: 13, color: c.textSub),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentRow(OmniColors c, LeaveAttachment a) => InkWell(
        onTap: () => _openAttachment(a),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${a.name} · ${a.sizeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.accent),
                ),
              ),
            ],
          ),
        ),
      );
}
