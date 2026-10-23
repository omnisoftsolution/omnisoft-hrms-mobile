import 'package:flutter/material.dart';

import '../../../models/expense_record.dart';
import '../../../models/my_day.dart';
import '../../../services/omni_mobile_api.dart';
import '../../approvals/approvals_screen.dart';
import '../../expenses/expense_detail_screen.dart';
import '../../payroll/payslips_screen.dart';

/// Ignores a second For-you tap while one is being handled (the expense
/// lookup and the push). One per screen.
class ForYouTapGuard {
  bool opening = false;
}

/// The screen a For-you row pushes.
Widget forYouDestination(ForYouItem item, ExpenseRecord? expense) {
  switch (item.kind) {
    case 'leave_approvals':
      return const ApprovalsScreen();
    case 'my_expense':
      return ExpenseDetailScreen(record: expense!);
    default:
      return const PayslipsScreen();
  }
}

/// The expense behind a `my_expense` row, or null when it cannot be
/// loaded (the caller then opens the Expenses tab instead).
Future<ExpenseRecord?> findForYouExpense(
  OmniMobileApi Function() api,
  int id,
) async {
  try {
    final page = await api().getExpenseList();
    return page.records.where((record) => record.id == id).firstOrNull;
  } catch (_) {
    return null;
  }
}

/// A tap on a For-you row, shared by My day and the Team overview (moved
/// unchanged from `MyDayScreenState._onTap`). [context] is the screen's
/// own context: the push goes on the tab's Navigator, so the bottom bar
/// stays visible. [refresh] reloads the screen afterwards; [refreshSession]
/// re-pulls /me after a leave-approvals visit.
Future<void> openForYouItem(
  BuildContext context,
  ForYouItem item, {
  required ForYouTapGuard guard,
  required OmniMobileApi Function() api,
  required Future<void> Function() refreshSession,
  required Future<void> Function() refresh,
  void Function(int leaveId)? onOpenLeave,
  void Function(int expenseId)? onOpenExpense,
  Widget Function(ForYouItem item, ExpenseRecord? expense)? destinationBuilder,
}) async {
  if (!item.isKnown) return;
  // id 0 = the server omitted it: there is nothing to open.
  if (item.id == 0 && (item.kind == 'my_leave' || item.kind == 'my_expense')) {
    return;
  }
  if (item.kind == 'my_leave') {
    onOpenLeave?.call(item.id);
    return;
  }
  if (guard.opening) return;
  guard.opening = true;
  try {
    ExpenseRecord? expense;
    if (item.kind == 'my_expense') {
      expense = await findForYouExpense(api, item.id);
      if (!context.mounted) return;
      if (expense == null) {
        onOpenExpense?.call(item.id);
        return;
      }
    }
    final build = destinationBuilder ?? forYouDestination;
    // The tab's own Navigator: the bottom bar stays visible.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => build(item, expense)));
  } finally {
    guard.opening = false;
  }
  // The guard covers the lookup and the push only: the follow-up
  // refreshes can take up to the request timeout on a slow network, and
  // the (still visible) rows must stay tappable meanwhile.
  if (!context.mounted) return;
  if (item.kind == 'leave_approvals') {
    // A decision changes the approvals count kept in the session.
    await refreshSession();
    if (!context.mounted) return;
  }
  await refresh();
}
