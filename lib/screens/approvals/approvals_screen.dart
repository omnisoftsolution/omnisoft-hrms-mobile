import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/approval_item.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/employee_avatar.dart';
import '../../widgets/error_state_view.dart';
import 'approval_detail_screen.dart';

/// Leave approvals for Time Off Approvers and Officers.
///
/// Pending = the requests Odoo lets this user act on now ("my step"
/// first). Recent = this user's own decisions of the last 30 days. Both
/// come from the connector; this screen decides nothing itself.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.apiBuilder, this.initialSegment = 0});

  /// Test seam: builds the API client from the session. Defaults to the
  /// real [OmniMobileApi] for the session's company and token. Passed on
  /// to the detail screen this one opens.
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// 0 = Pending (default), 1 = Recent — the Leave tab row opens Recent
  /// when nothing waits.
  final int initialSegment;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  late final OmniMobileApi _api;
  late int _segment; // 0 = Pending, 1 = Recent
  List<ApprovalItem> _pending = const [];
  List<ApprovalItem> _recent = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionService>();
    _api =
        widget.apiBuilder?.call(session) ??
        OmniMobileApi(
          baseUrl: session.clientUrl,
          db: session.clientDb,
          token: session.token,
        );
    _segment = widget.initialSegment;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getPendingApprovals(),
        _api.getRecentApprovals(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0];
        _recent = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(ApprovalItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApprovalDetailScreen(
          leaveId: item.id,
          apiBuilder: widget.apiBuilder,
        ),
      ),
    );
    // Whatever happened there (decided, already decided, gone), the
    // lists are stale now.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _segment == 1;
    final items = recent ? _recent : _pending;
    final ready = !_loading && _error == null;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Leave approvals')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          children: [
            _Segments(
              labels: [
                ready ? 'Pending · ${_pending.length}' : 'Pending',
                'Recent',
              ],
              value: _segment,
              onChanged: (v) => setState(() => _segment = v),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              ErrorStateView(message: _error!, onRetry: _load)
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: AppTheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recent
                          ? 'No decisions in the last 30 days'
                          : 'Nothing waiting for you',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.glassShadow,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 64, endIndent: 16),
                        _ApprovalRow(
                          item: items[i],
                          recent: recent,
                          onTap: () => _open(items[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Two-option pill switch (Pending / Recent).
class _Segments extends StatelessWidget {
  const _Segments({
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == value
                        ? AppTheme.surfaceContainerLowest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == value
                          ? AppTheme.primary
                          : AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.item,
    required this.recent,
    required this.onTap,
  });

  final ApprovalItem item;
  final bool recent;
  final VoidCallback onTap;

  Color get _chipColor {
    if (!recent) return item.assignedToMe ? AppTheme.primary : AppTheme.outline;
    switch (item.outcome) {
      case 'approved':
        return AppTheme.primary;
      case 'refused':
        return AppTheme.error;
      default:
        return AppTheme.secondary;
    }
  }

  /// Recent only: the refusal reason, who approved, or what is pending.
  String get _recentNote {
    if (item.outcome == 'refused') {
      return item.refusalReason.isEmpty ? '' : '"${item.refusalReason}"';
    }
    if (item.outcome == 'waiting_hr') return 'Second approval pending';
    final names = [
      item.firstApproverName,
      item.secondApproverName,
    ].where((n) => n.isNotEmpty).toList();
    return names.isEmpty ? '' : 'Approved by ${names.join(' and ')}';
  }

  @override
  Widget build(BuildContext context) {
    final chip = recent ? item.outcomeLabel : item.stepLabel;
    final meta = [
      item.durationLong,
      recent ? item.decidedLabel : item.submittedLabel,
    ].where((s) => s.isNotEmpty).join(' · ');
    final note = recent ? _recentNote : '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmployeeAvatar(name: item.employeeName, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                      if (chip.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _chipColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            chip,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _chipColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.leaveTypeName} · ${item.datesLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  if (meta.isNotEmpty || item.hasAttachment) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (item.hasAttachment) ...[
                          const Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: AppTheme.outline,
                          ),
                          const SizedBox(width: 2),
                        ],
                        Expanded(
                          child: Text(
                            meta,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
