import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/theme.dart';
import '../../../models/expense_record.dart';
import '../../../models/my_day.dart';
import '../../../services/omni_mobile_api.dart';
import '../../../services/session_service.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/omni_app_bar.dart';
import '../../approvals/approvals_screen.dart';
import '../../expenses/expense_detail_screen.dart';
import '../../payroll/payslips_screen.dart';
import 'day_timeline.dart';
import 'for_you_list.dart';
import 'status_tile.dart';

/// The Home tab for employees whose attendance is kiosk-only (spec
/// 2026-10-05 §5.3): a fixed Today card, the day's timeline and a short
/// "For you" list, all from one endpoint.
class MyDayScreen extends StatefulWidget {
  const MyDayScreen({
    super.key,
    this.onOpenLeave,
    this.onOpenExpense,
    this.apiBuilder,
    this.appBar,
    this.destinationBuilder,
    this.refreshSession,
  });

  /// Opens leave history on one request (HomeShell.navigateToLeave, the
  /// route the leave notifications use).
  final void Function(int leaveId)? onOpenLeave;

  /// Opens the Expenses tab (HomeShell.navigateToExpense); used when the
  /// expense's own record could not be loaded for the detail screen.
  final void Function(int expenseId)? onOpenExpense;

  /// Test seam: builds the API client from the session.
  @visibleForTesting
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// Test seam: replaces [OmniAppBar], which needs the notification and
  /// session services.
  @visibleForTesting
  final PreferredSizeWidget? appBar;

  /// Test seam: replaces the screen a For-you row pushes.
  @visibleForTesting
  final Widget Function(ForYouItem item, ExpenseRecord? expense)?
  destinationBuilder;

  /// Test seam: replaces SessionService.refreshMe.
  @visibleForTesting
  final Future<void> Function()? refreshSession;

  @override
  State<MyDayScreen> createState() => MyDayScreenState();
}

class MyDayScreenState extends State<MyDayScreen> {
  /// The last successfully loaded day; kept in memory only.
  MyDay? _day;
  String? _firstLoadError;
  bool _refreshFailed = false;

  /// The fetch currently running; every overlapping [refresh] shares it.
  Future<void>? _inFlight;

  /// Guards [_onTap] against a second tap while one is being handled.
  bool _opening = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        refresh();
      },
    );
    refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  OmniMobileApi _api() {
    final session = context.read<SessionService>();
    return widget.apiBuilder?.call(session) ??
        OmniMobileApi(
          baseUrl: session.clientUrl,
          db: session.clientDb,
          token: session.token,
        );
  }

  /// Reload the day. Called on first build, pull-to-refresh, on return
  /// from a pushed screen, on app resume, and by HomeShell on a Home tab
  /// tap. No polling: a kiosk punch shows on the next refresh. Overlapping
  /// calls share the one request in flight.
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _load() async {
    try {
      final day = await _api().fetchMyDay();
      if (!mounted) return;
      setState(() {
        _day = day;
        _firstLoadError = null;
        _refreshFailed = false;
      });
      // HR cleared the flag: re-pull /me so the Home tab flips back to the
      // classic home (the session listener swaps it).
      if (!day.kioskOnly &&
          context.read<SessionService>().attendanceKioskOnly) {
        unawaited(_refreshSession());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_day == null) {
          _firstLoadError = friendlyError(e);
        } else {
          _refreshFailed = true;
        }
      });
    }
  }

  Future<void> _retry() {
    setState(() => _firstLoadError = null);
    return refresh();
  }

  Future<ExpenseRecord?> _findExpense(int id) async {
    try {
      final page = await _api().getExpenseList();
      return page.records.where((record) => record.id == id).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static Widget _destination(ForYouItem item, ExpenseRecord? expense) {
    switch (item.kind) {
      case 'leave_approvals':
        return const ApprovalsScreen();
      case 'my_expense':
        return ExpenseDetailScreen(record: expense!);
      default:
        return const PayslipsScreen();
    }
  }

  Future<void> _refreshSession() async {
    final session = context.read<SessionService>();
    final custom = widget.refreshSession;
    if (custom != null) {
      await custom();
    } else {
      await session.refreshMe();
    }
  }

  Future<void> _onTap(ForYouItem item) async {
    if (!item.isKnown) return;
    // id 0 = the server omitted it: there is nothing to open.
    if (item.id == 0 &&
        (item.kind == 'my_leave' || item.kind == 'my_expense')) {
      return;
    }
    if (item.kind == 'my_leave') {
      widget.onOpenLeave?.call(item.id);
      return;
    }
    if (_opening) return;
    _opening = true;
    try {
      ExpenseRecord? expense;
      if (item.kind == 'my_expense') {
        expense = await _findExpense(item.id);
        if (!mounted) return;
        if (expense == null) {
          widget.onOpenExpense?.call(item.id);
          return;
        }
      }
      final build = widget.destinationBuilder ?? _destination;
      // The tab's own Navigator: the bottom bar stays visible.
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => build(item, expense)));
    } finally {
      _opening = false;
    }
    // The guard covers the lookup and the push only: the follow-up
    // refreshes can take up to the request timeout on a slow network, and
    // the (still visible) rows must stay tappable meanwhile.
    if (!mounted) return;
    if (item.kind == 'leave_approvals') {
      // A decision changes the approvals count kept in the session.
      await _refreshSession();
      if (!mounted) return;
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar ?? const OmniAppBar(title: 'My day'),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final day = _day;
    if (day == null) {
      final error = _firstLoadError;
      if (error == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorStateView(message: error, onRetry: _retry),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final sectionStyle = text.labelLarge?.copyWith(
      color: AppTheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        if (_refreshFailed)
          Container(
            width: double.infinity,
            color: AppTheme.error.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              friendlyError(myDayRefreshFailed),
              style: text.bodySmall?.copyWith(color: AppTheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: StatusTile(day: day),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewPadding.bottom,
              ),
              children: [
                Text('Timeline', style: sectionStyle),
                DayTimeline(day: day),
                const SizedBox(height: 16),
                Text('For you', style: sectionStyle),
                const SizedBox(height: 8),
                ForYouList(items: day.forYou, onTap: _onTap),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
