import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/notification_record.dart';
import '../../services/notification_service.dart';
import '../../services/push_service.dart';
import 'notification_tap.dart';

export 'notification_tap.dart' show ReviewAnswerPoster;

/// In-app notifications inbox. Pushed from the bell icon on
/// MyDayScreen. Tap a kind-routable notification → marks read and
/// invokes the appropriate callback; the parent (HomeShell) wires
/// these to HomeShell.navigateToLeave / navigateToExpense.
class NotificationsScreen extends StatefulWidget {
  /// Called when the user taps a leave-kind notification.
  final void Function(int leaveId)? onLeaveTap;

  /// Called when the user taps an expense-kind notification.
  final void Function(int expenseId)? onExpenseTap;

  /// Called when an approver taps an "Approval needed" notification.
  final void Function(int leaveId)? onApprovalTap;

  /// Called when the user taps "HR updated your attendance" (My day).
  final VoidCallback? onMyDayTap;

  /// Test seam: posts the answer to HR's question (defaults to the
  /// review/answer route through the session).
  @visibleForTesting
  final ReviewAnswerPoster? answerReview;

  const NotificationsScreen({
    super.key,
    this.onLeaveTap,
    this.onExpenseTap,
    this.onApprovalTap,
    this.onMyDayTap,
    this.answerReview,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final svc = context.read<NotificationService>();
      // Opening the bell clears Omni HR's system notifications and sets
      // the iOS badge to the bell's unread count (spec 2026-10-11 §6.5) —
      // the badge only when the list came (not a cached count offline);
      // PushService skips both if the session ended or the bell closed
      // while the list loaded.
      await context.read<PushService>().onBellOpened(
        refresh: () async {
          await svc.refreshList();
          return svc.lastError == null;
        },
        unread: () => svc.unreadCount,
        stillOpen: () => mounted,
      );
    });
  }

  /// The shared bell handler (notification_tap.dart), also used by push
  /// taps (spec 2026-10-11 §6.4).
  Future<void> _handleTap(NotificationRecord n) => handleNotificationTap(
    context,
    n,
    targets: NotificationTapTargets(
      onLeaveTap: widget.onLeaveTap,
      onExpenseTap: widget.onExpenseTap,
      onApprovalTap: widget.onApprovalTap,
      onMyDayTap: widget.onMyDayTap,
    ),
    answerReview: widget.answerReview,
  );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<NotificationService>();
    final items = svc.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (svc.unreadCount > 0)
            TextButton(
              onPressed: () => svc.markAllRead(),
              child: Text(
                'Mark all read',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: svc.refreshList,
        child: svc.loading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : svc.lastError != null && items.isEmpty
            ? _emptyState(svc.lastError!, isError: true)
            : items.isEmpty
            ? _emptyState('No notifications yet')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _tile(items[i]),
              ),
      ),
    );
  }

  Widget _emptyState(String text, {bool isError = false}) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline
                      : Icons.notifications_none_rounded,
                  size: 56,
                  color: isError ? AppTheme.error : AppTheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(NotificationRecord n) {
    final iconData = switch (n.kind) {
      'leave_approved' => Icons.event_available_rounded,
      'leave_first_approved' => Icons.event_available_rounded,
      'leave_refused' => Icons.event_busy_rounded,
      'leave_approval_requested' => Icons.fact_check_outlined,
      'expense_approved' => Icons.receipt_long_rounded,
      'expense_refused' => Icons.receipt_long_rounded,
      'attendance_query' => Icons.help_outline,
      'attendance_declaration_applied' => Icons.event_available,
      _ => Icons.notifications_rounded,
    };
    final iconColor = switch (n.kind) {
      'leave_approved' => AppTheme.primary,
      'leave_first_approved' => AppTheme.secondary,
      'leave_refused' => AppTheme.error,
      'leave_approval_requested' => AppTheme.primary,
      'expense_approved' => AppTheme.primary,
      'expense_refused' => AppTheme.error,
      'attendance_query' => AppTheme.secondary,
      'attendance_declaration_applied' => AppTheme.primary,
      _ => AppTheme.outline,
    };
    final created = n.createDate;
    final timeLabel = created != null ? _relativeTime(created) : '';
    // APP-5: an answered HR question says so next to the time.
    final answered = n.isAttendanceQuery && n.answered;
    final meta = GoogleFonts.inter(fontSize: 11, color: AppTheme.outline);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _handleTap(n),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.glassShadow,
            border: !n.read
                ? Border.all(
                    color: AppTheme.primaryContainer.withValues(alpha: 0.4),
                    width: 1.5,
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(iconData, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ),
                        if (!n.read) ...[
                          const SizedBox(width: 6),
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryContainer,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        n.body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (timeLabel.isNotEmpty || answered) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (timeLabel.isNotEmpty)
                            Text(timeLabel, style: meta),
                          if (timeLabel.isNotEmpty && answered)
                            Text('  ·  ', style: meta),
                          if (answered) ...[
                            Icon(
                              Icons.check_circle_outline,
                              size: 12,
                              color: AppTheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Answered',
                              style: meta.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM yyyy').format(t);
  }
}
