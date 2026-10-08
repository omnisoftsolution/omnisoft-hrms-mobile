import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/datetime_utils.dart';
import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/attendance_ask.dart';
import '../../models/notification_record.dart';
import '../../services/notification_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../home/my_day/declaration_sheet.dart';

/// Posts the answer to HR's question (the review/answer route).
typedef ReviewAnswerPoster =
    Future<void> Function({
      required int notificationId,
      required String answerCode,
      required String note,
      DateTime? time,
    });

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<NotificationService>().refreshList(),
    );
  }

  Future<void> _handleTap(NotificationRecord n) async {
    final svc = context.read<NotificationService>();
    if (n.isAttendanceQuery &&
        !n.answered &&
        AskOption.listFrom(n.payload['options']).isNotEmpty) {
      await _answer(n, svc);
      return;
    }
    if (!n.read) await svc.markRead(n.id);
    if (!mounted) return;
    if (n.isDeclarationApplied) {
      widget.onMyDayTap?.call();
      return;
    }
    if (n.isApprovalRequestKind) {
      final leaveId = n.leaveIdHint;
      if (leaveId != null && widget.onApprovalTap != null) {
        widget.onApprovalTap!(leaveId);
        return;
      }
    } else if (n.isLeaveKind) {
      final leaveId = n.leaveIdHint;
      if (leaveId != null && widget.onLeaveTap != null) {
        widget.onLeaveTap!(leaveId);
        return;
      }
    } else if (n.isExpenseKind) {
      final expenseId = n.expenseIdHint;
      if (expenseId != null && widget.onExpenseTap != null) {
        widget.onExpenseTap!(expenseId);
        return;
      }
    }
    // System / unknown — no navigation, but keep the screen open so
    // the user sees the read-state flip.
  }

  /// HR's "Ask the employee" (spec 2026-10-07 §4.5): the payload's options
  /// in the declaration sheet, posted to review/answer, then marked read.
  Future<void> _answer(NotificationRecord n, NotificationService svc) async {
    final post =
        widget.answerReview ?? _reviewAnswer(context.read<SessionService>());
    final messenger = ScaffoldMessenger.of(context);
    final question = n.payload['question'];
    final answer = await showDeclarationSheet(
      context,
      title: question is String && question.isNotEmpty ? question : n.title,
      // Connector 2.55.0: a question about the employee's own declaration
      // suggests the declared time for "No, the right time is".
      options: AskOption.listFrom(
        n.payload['options'],
        fallbackTime: DateTimeUtils.parseOdooUtc(
          n.payload['suggested_time']?.toString(),
        ),
      ),
      day:
          DateTime.tryParse(n.payload['date']?.toString() ?? '') ??
          DateTime.now(),
      footnote: 'HR will review your answer.',
    );
    if (!mounted || answer == null) return;
    try {
      await post(
        notificationId: n.id,
        answerCode: answer.code,
        note: answer.note,
        time: answer.time,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: AppTheme.error,
        ),
      );
      // A 409 already_answered must not reopen the sheet on the next tap.
      await svc.refreshList();
      return;
    }
    await svc.markRead(n.id);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sent to HR'),
        backgroundColor: AppTheme.primary,
      ),
    );
    await svc.refreshList();
  }

  static ReviewAnswerPoster _reviewAnswer(SessionService session) =>
      ({
        required int notificationId,
        required String answerCode,
        required String note,
        DateTime? time,
      }) =>
          OmniMobileApi(
            baseUrl: session.clientUrl,
            db: session.clientDb,
            token: session.token,
          ).answerReview(
            notificationId: notificationId,
            answerCode: answerCode,
            note: note,
            time: time,
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
                    if (timeLabel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        timeLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.outline,
                        ),
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
