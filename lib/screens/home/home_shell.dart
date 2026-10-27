import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'arrival_snack_tracker.dart';
import 'home_root.dart';
import 'leave_tab_icon.dart';
import 'my_day/my_day_screen.dart';
import 'side_tab_column.dart';
import 'overview/team_overview_screen.dart';
import '../approvals/approval_detail_screen.dart';
import '../expenses/expenses_screen.dart';
import '../history/history_shell.dart';
import '../leave/leave_screen.dart';
import '../notifications/notification_tap.dart';
import '../notifications/notifications_screen.dart';
import '../../core/omni_colors.dart';
import '../../models/notification_record.dart';
import '../../services/face_recognition_service.dart';
import '../../services/holiday_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_service.dart';
import '../../widgets/push_explainer_card.dart';
import '../../services/session_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Per-tab screen state keys (for tab-switch refresh + notification
  // deep-linking into HistoryShell / ExpensesScreen).
  final _homeRootKey = GlobalKey<HomeRootState>();
  final _myDayKey = GlobalKey<MyDayScreenState>();
  final _overviewKey = GlobalKey<TeamOverviewScreenState>();
  final _leaveKey = GlobalKey<LeaveScreenState>();
  final _historyKey = GlobalKey<HistoryShellState>();
  final _expensesKey = GlobalKey<ExpensesScreenState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  // Per-tab Navigator keys. Pushes from inside a tab go to this
  // tab's Navigator, so the bottom NavigationBar (owned by this
  // shell's Scaffold) stays visible across sub-screens.
  final _homeNavKey = GlobalKey<NavigatorState>();
  final _leaveNavKey = GlobalKey<NavigatorState>();
  final _historyNavKey = GlobalKey<NavigatorState>();
  final _expensesNavKey = GlobalKey<NavigatorState>();

  NotificationService? _notifSvc;
  PushService? _push;

  /// Two push taps whose fetches overlap: only the latest opens anything.
  final _pushTaps = LatestTap();

  /// The arrival snackbar on screen, for a push tap on its notice (F1).
  final _arrivalSnack = ArrivalSnackTracker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<SessionService>();
      context.read<HolidayService>().loadFromSession(session);
      context.read<FaceRecognitionService>().refreshEnrolledStatus(session);
      // Begin polling notifications now that we know we're signed in.
      _notifSvc = context.read<NotificationService>();
      _notifSvc!.start(session);
      _notifSvc!.addListener(_onNotificationChange);
      // Pushes (spec 2026-10-11 §6.4) hand reminders, taps and the
      // explainer over here. Run once now: something may already wait.
      _push = context.read<PushService>();
      _push!.addListener(_onPushChange);
      _onPushChange();
    });
  }

  @override
  void dispose() {
    // Stop the notification poller when the shell is torn down (e.g.
    // session.clearSession on invalid_session reroutes us to Login).
    _notifSvc?.removeListener(_onNotificationChange);
    _notifSvc?.stop();
    _push?.removeListener(_onPushChange);
    _sideHost?.withdraw(this);
    super.dispose();
  }

  GlobalKey<NavigatorState> _navKeyForIndex(int i) {
    switch (i) {
      case 0:
        return _homeNavKey;
      case 1:
        return _leaveNavKey;
      case 2:
        return _historyNavKey;
      case 3:
        return _expensesNavKey;
      default:
        return _homeNavKey;
    }
  }

  /// Pops a transient snackbar for the newest notification queued by
  /// NotificationService (consume-and-clear semantics on the service),
  /// and runs the side effects of every arrival in the batch — one poll
  /// can bring a leave decision and a newer expense update together.
  void _onNotificationChange() {
    if (!mounted) return;
    if (_notifSvc?.consumeUnreadDrop() ?? false) {
      // Something was read or closed elsewhere (F3), e.g. a request
      // someone else decided: the approvals count on Home / Leave follows.
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshMe();
    }
    final arrivals = _notifSvc?.consumeFreshArrivals() ?? const [];
    if (arrivals.isEmpty) return;
    final fresh = arrivals.first;
    if (refreshesApprovals(arrivals)) {
      // A new request waits for this user: re-pull /me so the approvals
      // count in SessionService (Home card) is current.
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshMe();
    }
    if (reloadsLeaveHistory(arrivals, tabIndex: _index)) {
      // ignore: discarded_futures — fire-and-forget
      _historyKey.currentState?.reloadLeaveQuietly();
    }
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    // Read before the builder: it may run again later (re-wrap).
    final colors = context.omni;
    showArrivalSnack(
      messenger,
      _arrivalSnack,
      fresh.id,
      (wrap) => notificationArrivalSnackBar(
        fresh,
        onAction: () => _openArrival(fresh),
        wrapContent: wrap,
        colors: colors,
      ),
    );
  }

  /// The arrival snackbar's VIEW / Review action.
  void _openArrival(NotificationRecord fresh) {
    if (fresh.isApprovalRequestKind) {
      final id = fresh.leaveIdHint;
      if (id != null) {
        _notifSvc?.markRead(fresh.id);
        navigateToApproval(id);
      }
    } else if (fresh.isLeaveKind) {
      final id = fresh.leaveIdHint;
      if (id != null) {
        _notifSvc?.markRead(fresh.id);
        navigateToLeave(id);
      }
    } else if (fresh.isExpenseKind) {
      final id = fresh.expenseIdHint;
      if (id != null) {
        _notifSvc?.markRead(fresh.id);
        navigateToExpense(id);
      }
    }
  }

  /// What PushService handed over: a reminder that arrived while the app
  /// is open becomes a snackbar whose "Open" goes Home; a tap on a system
  /// notification is opened (spec §6.4).
  void _onPushChange() {
    final push = _push;
    if (push == null || !mounted) return;
    if (push.consumeApprovalsChanged()) {
      // A request this user could decide was closed elsewhere (F3): the
      // approvals count on Home / Leave follows.
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshMe();
    }
    final arrivals = push.consumeArrivals();
    final messenger = _scaffoldMessengerKey.currentState;
    if (arrivals.isNotEmpty && messenger != null) {
      _arrivalSnack.replaced();
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          pushArrivalSnackBar(
            arrivals.first,
            onOpen: () => unawaited(navigateToMyDay()),
            colors: context.omni,
          ),
        );
    }
    final tap = push.consumePendingTap();
    if (tap != null) unawaited(_openPushTap(push, tap));
    // Home's one-time explainer (spec §6.2).
    if (push.consumeExplainerDue()) unawaited(showPushExplainer(context, push));
  }

  /// A push tap: reminders → Home; notices → `notifications/get` (on the
  /// push session snapshot) → the bell's handler run from the Home tab
  /// (under this shell's messenger), else the bell. Whatever covers the
  /// tabs (Profile, Payslips, the bell, the explainer — root-navigator
  /// pages) is closed first. An answer that comes back after a sign-out or
  /// a new access token, after this shell is gone, or after a newer tap,
  /// opens nothing (the latest tap wins).
  Future<void> _openPushTap(PushService push, Map<String, dynamic> data) {
    final current = push.sessionStillCurrent();
    final latest = _pushTaps.next();
    bool still() => mounted && current() && latest();
    // F1: the notice the tap opens is not announced again by the bell's
    // arrival snackbar — hidden when it is already on screen.
    final noticeId = int.tryParse(data['notification_id']?.toString() ?? '');
    if (noticeId != null) {
      _notifSvc?.suppressArrival(noticeId);
      if (_arrivalSnack.takeIfShowing(noticeId)) {
        _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      }
    }
    if (pushTapRefreshesApprovals(data)) {
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshMe();
    }
    popAbove(context);
    return openPushTap(
      data,
      fetch: push.fetchNotice,
      openHome: navigateToMyDay,
      openBell: openNotifications,
      stillCurrent: still,
      runHandler: (n) async {
        // My day, Team overview or the Home tab's navigator, whichever is
        // mounted (A-L8: My day is not mounted while the overview shows).
        final ctx = homeTabContext(
          myDayKey: _myDayKey,
          overviewKey: _overviewKey,
          homeNavKey: _homeNavKey,
        );
        if (ctx == null || !ctx.mounted) return openNotifications();
        await handleNotificationTap(
          ctx,
          n,
          targets: NotificationTapTargets(
            onLeaveTap: navigateToLeave,
            onExpenseTap: navigateToExpense,
            onApprovalTap: navigateToApproval,
            onMyDayTap: navigateToMyDay,
          ),
          stillCurrent: still,
        );
      },
    );
  }

  void _onTabTap(int i) {
    // Tap-active-tab pops that tab's nav back to its root (Instagram
    // pattern). Avoids stranding users deep inside a sub-screen.
    if (i == _index) {
      final nav = _navKeyForIndex(i).currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
      // Home reloads its visible screen (My day or Team overview) on a
      // re-tap (a kiosk punch shows on the next refresh).
      if (i == 0) _homeRootKey.currentState?.refresh();
      return;
    }
    setState(() => _index = i);
    // Refresh data when switching to these tabs.
    if (i == 0) _homeRootKey.currentState?.refresh();
    if (i == 1) _leaveKey.currentState?.refresh();
    if (i == 2) _historyKey.currentState?.refresh();
    // For feature-gated tabs (Leave, Expenses) also re-pull the
    // subscription state so a lock/unlock from the SaaS side
    // propagates without waiting for app background+foreground.
    // Best-effort, non-blocking — the tab opens immediately; the
    // FeatureLockedPane appears one network round-trip later if the
    // flag flipped.
    if (i == 1 || i == 3) {
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshSubscription();
    }
  }

  /// Reached via the bell → notification tap chain. Switches the
  /// bottom-nav to History, then asks HistoryShell to flip to Leave
  /// and scroll-highlight the matching record.
  Future<void> navigateToLeave(int leaveId) async {
    // Pop the History tab's nav stack to root first so the deep-link
    // lands on a clean HistoryShell view.
    _historyNavKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _index = 2);
    // Wait until the end of the next frame so the new IndexedStack
    // child (HistoryShell) is built + laid out. `Future.delayed(zero)`
    // is a single-microtask stopgap that races on complex trees.
    await WidgetsBinding.instance.endOfFrame;
    await _historyKey.currentState?.openLeaveAndHighlight(leaveId);
  }

  /// Reached via the bell → expense notification tap chain. Switches
  /// the bottom-nav to Expenses and re-pulls the list so the new
  /// state badge is visible. No row-highlight in v1 (the leave path
  /// has scroll-and-highlight; expenses gets just-refresh — symmetry
  /// can be added later).
  Future<void> navigateToExpense(int expenseId) async {
    _expensesNavKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _index = 3);
    await WidgetsBinding.instance.endOfFrame;
    await _expensesKey.currentState?.refresh();
  }

  /// Reached from an "Approval needed" notification (snackbar "Review"
  /// or the bell list). Switches to the Home tab and opens the request
  /// on that tab's Navigator, so the bottom nav stays visible and Back
  /// returns to Home. Home is refreshed once the request is closed.
  Future<void> navigateToApproval(int leaveId) async {
    _homeNavKey.currentState?.popUntil((r) => r.isFirst);
    if (_index != 0) setState(() => _index = 0);
    await WidgetsBinding.instance.endOfFrame;
    final nav = _homeNavKey.currentState;
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute(builder: (_) => ApprovalDetailScreen(leaveId: leaveId)),
    );
    _homeRootKey.currentState?.refresh();
  }

  /// Reached from "HR updated your attendance" (spec 2026-10-07 §3.7) and
  /// a reminder's Open: the Home tab at its root, showing My day (dual
  /// mode switches to it for this visit), reloaded.
  Future<void> navigateToMyDay() async {
    _homeNavKey.currentState?.popUntil((r) => r.isFirst);
    if (_index != 0) setState(() => _index = 0);
    await WidgetsBinding.instance.endOfFrame;
    await _homeRootKey.currentState?.showMyDay();
  }

  /// The bell, on the root navigator above the tabs. A routable tap pops
  /// it and lets this shell switch tab. Opened by the AppBar bell and by a
  /// push tap whose notice has nowhere else to go (spec 2026-10-11 §6.4).
  Future<void> openNotifications() async {
    final nav = Navigator.of(context, rootNavigator: true);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          onLeaveTap: (leaveId) async {
            nav.pop();
            await navigateToLeave(leaveId);
          },
          onExpenseTap: (expenseId) async {
            nav.pop();
            await navigateToExpense(expenseId);
          },
          onApprovalTap: (leaveId) async {
            nav.pop();
            await navigateToApproval(leaveId);
          },
          onMyDayTap: () async {
            nav.pop();
            await navigateToMyDay();
          },
        ),
      ),
    );
  }

  /// Wraps the given root screen in its own Navigator so that pushes
  /// from inside the screen stay within this tab — keeping the
  /// HomeShell's bottom NavigationBar visible.
  Widget _buildTabNavigator({
    required GlobalKey<NavigatorState> navKey,
    required Widget root,
  }) {
    return Navigator(
      key: navKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => root, settings: settings),
    );
  }

  /// The app-level host that draws the tabs in iPhone Duo's side column
  /// (kept here: [dispose] can't look it up).
  SideColumnHostState? _sideHost;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sideHost = SideColumnHost.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<SessionService>().leaveApprovalsPendingCount;
    final c = context.omni;
    // iPhone Duo, closed or open sideways: the tabs go into the system's
    // side column (drawn by SideColumnHost) instead of the bottom bar.
    final side = SideColumnHost.sideOf(context);
    final tabs = [
      const SideTab(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'HOME',
      ),
      SideTab(
        icon: LeaveTabIcon(
          count: pending,
          selected: _index == 1,
          icon: const Icon(Icons.event_note_outlined),
        ),
        selectedIcon: LeaveTabIcon(
          count: pending,
          selected: _index == 1,
          icon: const Icon(Icons.event_note_rounded),
        ),
        label: 'LEAVE',
      ),
      const SideTab(
        icon: Icon(Icons.history_rounded),
        selectedIcon: Icon(Icons.history_rounded),
        label: 'HISTORY',
      ),
      const SideTab(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long_rounded),
        label: 'EXPENSES',
      ),
    ];
    // A full-screen page on the root navigator (check-in, Profile, a root
    // sheet) covers the shell: on a phone it hides the bottom bar, so the
    // column drops the tabs too.
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (side != SideColumn.none && !covered) {
      _sideHost?.offer(
        this,
        SideTabsSpec(tabs: tabs, selectedIndex: _index, onSelected: _onTabTap),
      );
    } else {
      _sideHost?.withdraw(this);
    }
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      // PopScope intercepts the Android system back button so it pops
      // within the active tab's Navigator first. Only when the tab
      // nav is already at its root do we let the system close the app.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = _navKeyForIndex(_index).currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          } else {
            await SystemNavigator.pop();
          }
        },
        child: Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              _buildTabNavigator(
                navKey: _homeNavKey,
                root: HomeRoot(
                  key: _homeRootKey,
                  myDayKey: _myDayKey,
                  overviewKey: _overviewKey,
                  onOpenLeave: navigateToLeave,
                  onOpenExpense: navigateToExpense,
                ),
              ),
              _buildTabNavigator(
                navKey: _leaveNavKey,
                root: LeaveScreen(key: _leaveKey),
              ),
              _buildTabNavigator(
                navKey: _historyNavKey,
                root: HistoryShell(key: _historyKey),
              ),
              _buildTabNavigator(
                navKey: _expensesNavKey,
                root: ExpensesScreen(key: _expensesKey),
              ),
            ],
          ),
          bottomNavigationBar: side != SideColumn.none
              ? null
              : NavigationBarTheme(
                  // Material 3 NavigationBar with a tinted indicator pill
                  // behind the active item. Keeps a single source of truth
                  // for both selected/unselected label color.
                  data: NavigationBarThemeData(
                    backgroundColor: c.bar,
                    elevation: 8,
                    height: 72,
                    indicatorColor: c.navIndicator,
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: c.accent,
                        );
                      }
                      return TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.textMuted,
                      );
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return IconThemeData(color: c.accent);
                      }
                      return IconThemeData(color: c.textMuted);
                    }),
                  ),
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _onTabTap,
                    destinations: [
                      for (final t in tabs)
                        NavigationDestination(
                          icon: t.icon,
                          selectedIcon: t.selectedIcon,
                          label: t.label,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// History tab index in [HomeShell]'s bottom bar.
const historyTabIndex = 2;

/// Whether freshly arrived notifications should reload the leave list:
/// any decision on the user's own leave (approved / refused / first
/// approval) among [arrivals] while the History tab is on screen. Off
/// screen the list reloads anyway when the tab is opened.
bool reloadsLeaveHistory(
  Iterable<NotificationRecord> arrivals, {
  required int tabIndex,
}) => tabIndex == historyTabIndex && arrivals.any((n) => n.isLeaveKind);

/// Whether freshly arrived notifications should re-pull /me: a new
/// leave request waits for this user among [arrivals].
bool refreshesApprovals(Iterable<NotificationRecord> arrivals) =>
    arrivals.any((n) => n.isApprovalRequestKind);

/// The snackbar shown when a notification arrives while the app is open.
/// [onAction] runs for its VIEW / Review action, when the kind has one.
/// [colors] is the theme's tokens (light when omitted).
SnackBar notificationArrivalSnackBar(
  NotificationRecord fresh, {
  required VoidCallback onAction,
  Widget Function(Widget content)? wrapContent,
  OmniColors? colors,
}) => SnackBar(
  backgroundColor: (colors ?? OmniColors.light).brandFill,
  // Flutter 3.44 keeps a bar with an action until it is tapped (persist
  // defaults to action != null); "Leave approved … VIEW" stayed for 6+
  // minutes on the Samsung (APP-8). It times out like any other.
  persist: false,
  duration: const Duration(seconds: 5),
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  content: (wrapContent ?? (Widget w) => w)(
    Row(
      children: [
        const Icon(
          Icons.notifications_active_rounded,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fresh.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (fresh.body.isNotEmpty)
                Text(
                  fresh.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
  action: fresh.snackActionLabel != null
      ? SnackBarAction(
          label: fresh.snackActionLabel!,
          textColor: Colors.white,
          onPressed: onAction,
        )
      : null,
);

/// The snackbar for a push-only notice (a check-in / check-out reminder)
/// that arrives while the app is open (spec 2026-10-11 §6.4): the push's
/// own title and body; "Open" goes to Home. [colors] is the theme's
/// tokens (light when omitted).
SnackBar pushArrivalSnackBar(
  PushArrival arrival, {
  required VoidCallback onOpen,
  OmniColors? colors,
}) => SnackBar(
  backgroundColor: (colors ?? OmniColors.light).brandFill,
  // Same as the notice snackbar: a bar with an action must still time out.
  persist: false,
  duration: const Duration(seconds: 6),
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  content: Row(
    children: [
      const Icon(Icons.alarm_rounded, color: Colors.white, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              arrival.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            if (arrival.body.isNotEmpty)
              Text(
                arrival.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    ],
  ),
  action: SnackBarAction(
    label: 'Open',
    textColor: Colors.white,
    onPressed: onOpen,
  ),
);
