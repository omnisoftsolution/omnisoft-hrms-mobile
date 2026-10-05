import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/approval_item.dart';
import '../services/session_service.dart';

/// "2 Annual Leave · 1 Sick Leave" for the requests waiting on this
/// user's own step. Most frequent type first, then by name.
String approvalsBreakdown(List<ApprovalItem> items) {
  final counts = <String, int>{};
  for (final it in items) {
    if (!it.assignedToMe || it.leaveTypeName.isEmpty) continue;
    counts[it.leaveTypeName] = (counts[it.leaveTypeName] ?? 0) + 1;
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return names.map((n) => '${counts[n]} $n').join(' · ');
}

/// Home-tab entry point for approvers. Renders nothing unless the
/// connector says the user can approve something
/// (`SessionService.leaveApprovalsEnabled`), so non-approvers and
/// companies on a connector older than 2.43.0 never see it. An approver
/// with nothing waiting still gets the card, to reach Recent.
///
/// Sits at the top of Home and carries its own bottom spacing, so the
/// caller needs no conditional gap.
class ApprovalsHomeCard extends StatelessWidget {
  const ApprovalsHomeCard({super.key, required this.onTap, this.breakdown = ''});

  final VoidCallback onTap;

  /// Per-type line under the count, from [approvalsBreakdown].
  final String breakdown;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    if (!session.leaveApprovalsEnabled) return const SizedBox.shrink();
    final count = session.leaveApprovalsPendingCount;
    final value = count == 0 ? 'Nothing waiting' : '$count waiting for you';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.glassShadow,
        ),
        child: Material(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leave approvals',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                        if (count > 0 && breakdown.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            breakdown,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
