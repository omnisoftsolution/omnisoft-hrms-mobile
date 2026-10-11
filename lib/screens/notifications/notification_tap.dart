import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/datetime_utils.dart';
import '../../core/error_messages.dart';
import '../../core/push_groups.dart';
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

/// Where a tapped notice may send the user. The bell wires these to
/// HomeShell (after popping itself); a push tap wires them to HomeShell
/// directly.
class NotificationTapTargets {
  const NotificationTapTargets({
    this.onLeaveTap,
    this.onExpenseTap,
    this.onApprovalTap,
    this.onMyDayTap,
  });

  /// A decision on the user's own leave.
  final void Function(int leaveId)? onLeaveTap;

  /// A decision on the user's own expense.
  final void Function(int expenseId)? onExpenseTap;

  /// "Approval needed": someone else's request waits for this user.
  final void Function(int leaveId)? onApprovalTap;

  /// "HR updated your attendance".
  final VoidCallback? onMyDayTap;
}

/// The bell's tap handler, shared by the bell list and push taps (spec
/// 2026-10-11 §6.4): marks the notice read, then an unanswered HR question
/// opens the answer sheet; leave / expense / approval / "HR updated your
/// attendance" go to their screen through [targets]; anything else stays
/// where it is. [context] must sit under the [NotificationService]
/// provider and a ScaffoldMessenger.
Future<void> handleNotificationTap(
  BuildContext context,
  NotificationRecord n, {
  NotificationTapTargets targets = const NotificationTapTargets(),
  ReviewAnswerPoster? answerReview,
}) async {
  final svc = context.read<NotificationService>();
  if (n.isAttendanceQuery &&
      !n.answered &&
      AskOption.listFrom(n.payload['options']).isNotEmpty) {
    await _answer(context, n, svc, answerReview);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  if (!n.read) await svc.markRead(n.id);
  if (!context.mounted) return;
  // APP-5: one answer only — say so instead of a tap that does nothing.
  if (n.isAttendanceQuery && n.answered) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('You already answered this question.')),
      );
    return;
  }
  if (n.isDeclarationApplied) {
    targets.onMyDayTap?.call();
    return;
  }
  if (n.isApprovalRequestKind) {
    final leaveId = n.leaveIdHint;
    final open = targets.onApprovalTap;
    if (leaveId != null && open != null) {
      open(leaveId);
      return;
    }
  } else if (n.isLeaveKind) {
    final leaveId = n.leaveIdHint;
    final open = targets.onLeaveTap;
    if (leaveId != null && open != null) {
      open(leaveId);
      return;
    }
  } else if (n.isExpenseKind) {
    final expenseId = n.expenseIdHint;
    final open = targets.onExpenseTap;
    if (expenseId != null && open != null) {
      open(expenseId);
      return;
    }
  }
  // System / unknown — no navigation, but keep the screen open so
  // the user sees the read-state flip.
}

/// HR's "Ask the employee" (spec 2026-10-07 §4.5): the payload's options
/// in the declaration sheet, posted to review/answer, then marked read.
Future<void> _answer(
  BuildContext context,
  NotificationRecord n,
  NotificationService svc,
  ReviewAnswerPoster? answerReview,
) async {
  final post = answerReview ?? _reviewAnswer(context.read<SessionService>());
  final messenger = ScaffoldMessenger.of(context);
  final question = n.payload['question'];
  final answer = await showDeclarationSheet(
    context,
    heading: 'Question from HR',
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
  if (!context.mounted || answer == null) return;
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

ReviewAnswerPoster _reviewAnswer(SessionService session) =>
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

/// Whether [handleNotificationTap] has somewhere to take this notice; the
/// rest (announcements, system notices, a notice without its id) open the
/// bell when tapped from a push — the app has no announcement screen in v1.
bool tapsThroughHandler(NotificationRecord n) {
  if (n.isAttendanceQuery || n.isDeclarationApplied) return true;
  if (n.isApprovalRequestKind || n.isLeaveKind) return n.leaveIdHint != null;
  if (n.isExpenseKind) return n.expenseIdHint != null;
  return false;
}

/// A tap on a system notification (spec §6.4, push data per the contract):
/// a reminder opens Home; a notice is fetched with `notifications/get` and
/// run through the bell's handler, or opens the bell when it has nowhere
/// else to go, is gone (404) or cannot be fetched (offline).
///
/// [stillCurrent] is asked once the fetch is over: false (a sign-out or a
/// new access token while it ran) opens nothing — the answer belongs to a
/// session that is no longer the app's.
Future<void> openPushTap(
  Map<String, dynamic> data, {
  required Future<NotificationRecord> Function(int id) fetch,
  required Future<void> Function() openHome,
  required Future<void> Function() openBell,
  required Future<void> Function(NotificationRecord n) runHandler,
  bool Function()? stillCurrent,
}) async {
  if (isReminderKind(data['kind']?.toString() ?? '')) return openHome();
  final id = int.tryParse(data['notification_id']?.toString() ?? '');
  if (id == null) return openBell();
  NotificationRecord? n;
  try {
    n = await fetch(id);
  } catch (_) {
    n = null;
  }
  if (stillCurrent != null && !stillCurrent()) return;
  if (n == null || !tapsThroughHandler(n)) return openBell();
  return runHandler(n);
}

/// Closes every page the root navigator shows above the page holding
/// [context]: Profile, Payslips, the bell, the explainer — all pushed with
/// `rootNavigator: true`, above HomeShell's tabs. A push tap calls it first
/// (HomeShell passes its own context), so what the tap opens is not hidden
/// underneath (spec §6.4). Pages below that page stay.
void popAbove(BuildContext context) {
  final page = ModalRoute.of(context);
  if (page == null || page.isCurrent) return;
  Navigator.of(
    context,
    rootNavigator: true,
  ).popUntil((r) => r == page || r.isFirst);
}
