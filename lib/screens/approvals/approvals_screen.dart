import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/omni_colors.dart';
import '../../models/approval_item.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/employee_avatar.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/pill_segments.dart';
import 'approval_detail_screen.dart';

/// Leave approvals for Time Off Approvers and Officers.
///
/// Pending = the requests Odoo lets this user act on now, in two
/// sections: "Waiting for you" (`assigned_to_me`) and "You can also
/// approve". Recent = this user's own decisions of the last 30 days. Both
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

  /// Both lists answered once: later reloads run in the background.
  bool _loaded = false;

  /// Drops an answer a newer reload has overtaken.
  int _seq = 0;

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

  /// Loads both lists. Once they have loaded, a reload (pull-down, back
  /// from a request) runs in the background (P1, 1.34.1): the lists stay
  /// instead of the full spinner. A reload that fails for a transient
  /// reason ([isTransientError]) keeps them and says so in a snackbar; any
  /// other failure (access lost, session gone, …) clears both lists and
  /// shows the error state — other people's requests never stay on screen
  /// after the access went. Only the newest call's answer is applied.
  Future<void> _load() async {
    final quiet = _loaded;
    final seq = ++_seq;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _api.getPendingApprovals(),
        _api.getRecentApprovals(),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _pending = results[0];
        _recent = results[1];
        _loaded = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (quiet && isTransientError(e)) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(friendlyError(e))));
        return;
      }
      setState(() {
        _pending = const [];
        _recent = const [];
        _loaded = false;
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
    final c = context.omni;
    final recent = _segment == 1;
    final items = recent ? _recent : _pending;
    final ready = !_loading && _error == null;
    // Pending in two sections, server order kept inside each: what waits
    // for this user now (assigned_to_me), then what Odoo also lets them
    // decide.
    final mine = _pending.where((i) => i.assignedToMe).toList();
    final others = _pending.where((i) => !i.assignedToMe).toList();
    return Scaffold(
      backgroundColor: c.background,
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
            PillSegments(
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
                    Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: c.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recent
                          ? 'No decisions in the last 30 days'
                          : 'Nothing waiting for you',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: c.textSub,
                      ),
                    ),
                  ],
                ),
              )
            else if (recent)
              _card(c, items, recent: true)
            else ...[
              _sectionTitle(c, 'Waiting for you'),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    'Nothing waiting for you.',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSub,
                    ),
                  ),
                )
              else
                _card(c, mine, recent: false),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionTitle(c, 'You can also approve'),
                _card(c, others, recent: false),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The white rounded card holding a list of rows.
  Widget _card(OmniColors c, List<ApprovalItem> items, {required bool recent}) => Container(
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(24),
      boxShadow: c.cardShadow,
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 64, endIndent: 16),
            _ApprovalRow(
              item: items[i],
              recent: recent,
              onTap: () => _open(items[i]),
            ),
          ],
        ],
      ),
    ),
  );

  /// Heading above a Pending section.
  Widget _sectionTitle(OmniColors c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: c.textSub,
      ),
    ),
  );
}

/// The row's first line: the employee name with the step / outcome chip at
/// the end. A chip that would take more than [_maxChipShare] of the line
/// (a long "Waiting for Christopher +1 (manager)", a narrow phone, large
/// text) moves under the name instead, so the name keeps its width and
/// the chip its words.
class _NameAndChip extends StatelessWidget {
  const _NameAndChip({
    required this.name,
    required this.chip,
    required this.color,
    required this.nameColor,
  });

  final String name;
  final String chip;
  final Color color;
  final Color nameColor;

  static const _maxChipShare = 0.45;
  static const _gap = 8.0;
  static const _chipPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 3);
  TextStyle get _nameStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: nameColor,
  );

  TextStyle get _chipStyle =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color);

  @override
  Widget build(BuildContext context) {
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _nameStyle,
    );
    if (chip.isEmpty) return nameText;
    final chipBox = Container(
      padding: _chipPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        chip,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _chipStyle,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: chip,
            style: DefaultTextStyle.of(context).style.merge(_chipStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final chipWidth = painter.width + _chipPadding.horizontal;
        painter.dispose();
        if (chipWidth + _gap <= constraints.maxWidth * _maxChipShare) {
          return Row(
            children: [
              Expanded(child: nameText),
              const SizedBox(width: _gap),
              chipBox,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [nameText, const SizedBox(height: 4), chipBox],
        );
      },
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

  Color _chipColor(OmniColors c) {
    if (!recent) return item.assignedToMe ? c.accent : c.textMuted;
    switch (item.outcome) {
      case 'approved':
        return c.accent;
      case 'refused':
        return c.error;
      default:
        return c.secondary;
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
    final c = context.omni;
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
                  _NameAndChip(
                    name: item.employeeName,
                    chip: chip,
                    color: _chipColor(c),
                    nameColor: c.text,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.leaveTypeName} · ${item.datesLabel}',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.text,
                    ),
                  ),
                  if (meta.isNotEmpty || item.hasAttachment) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (item.hasAttachment) ...[
                          Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 2),
                        ],
                        Expanded(
                          child: Text(
                            meta,
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSub,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSub,
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
