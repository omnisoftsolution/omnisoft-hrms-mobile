import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/session_service.dart';

/// The approver's way into the Approvals screen from the Leave tab (spec
/// 2026-10-07 §4.5): teal with the count while something waits, white
/// "Nothing waiting · Recent decisions" otherwise, nothing for
/// non-approvers.
class LeaveApprovalsRow extends StatelessWidget {
  const LeaveApprovalsRow({
    super.key,
    required this.onTap,
    this.breakdown = '',
  });

  final VoidCallback onTap;

  /// "1 Childcare Leave · 1 Sick Leave"; shown under the count only.
  final String breakdown;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    if (!session.leaveApprovalsEnabled) return const SizedBox.shrink();
    final count = session.leaveApprovalsPendingCount;
    final waiting = count > 0;
    final fg = waiting ? Colors.white : AppTheme.onSurface;
    final muted = waiting
        ? Colors.white.withValues(alpha: 0.85)
        : AppTheme.onSurfaceVariant;
    return Card(
      key: const ValueKey('leave-approvals-row'),
      margin: EdgeInsets.zero,
      color: waiting ? AppTheme.primary : Colors.white,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: waiting
                ? Colors.white.withValues(alpha: 0.18)
                : AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            Icons.fact_check_outlined,
            color: waiting ? Colors.white : AppTheme.primary,
          ),
        ),
        title: Text(
          waiting ? '$count waiting for you' : 'Leave approvals',
          style: TextStyle(fontWeight: FontWeight.w600, color: fg),
        ),
        subtitle: Text(
          waiting
              ? (breakdown.isEmpty ? 'Leave approvals' : breakdown)
              : 'Nothing waiting · Recent decisions',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (waiting)
              Badge(backgroundColor: AppTheme.error, label: Text('$count')),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }
}
