import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'leave_tab_icon.dart';
import 'my_day/my_day_screen.dart';
import '../approvals/approval_detail_screen.dart';
import '../expenses/expenses_screen.dart';
import '../history/history_shell.dart';
import '../leave/leave_screen.dart';
import '../../core/theme.dart';
import '../../models/notification_record.dart';
import '../../services/face_recognition_service.dart';
import '../../services/holiday_service.dart';
import '../../services/notification_service.dart';
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
  final _myDayKey = GlobalKey<MyDayScreenState>();
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
    });
  }

  @override
  void dispose() {
    // Stop the notification poller when the shell is torn down (e.g.
    // session.clearSession on invalid_session reroutes us to Login).
    _notifSvc?.removeListener(_onNotificationChange);
    _notifSvc?.stop();
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

  /// Pops a transient snackbar when a freshly-arrived notification
  /// is queued by NotificationService. Each arrival fires at most
  /// one snackbar (consume-and-clear semantics on the service).
  void _onNotificationChange() {
    final fresh = _notifSvc?.consumeFreshArrival();
    if (fresh == null || !mounted) return;
    if (fresh.isApprovalRequestKind) {
      // A new request waits for this user: re-pull /me so the approvals
      // count in SessionService (Home card) is current.
      // ignore: discarded_futures — fire-and-forget
      context.read<SessionService>().refreshMe();
    }
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        notificationArrivalSnackBar(fresh, onAction: () => _openArrival(fresh)),
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

  void _onTabTap(int i) {
    // Tap-active-tab pops that tab's nav back to its root (Instagram
    // pattern). Avoids stranding users deep inside a sub-screen.
    if (i == _index) {
      final nav = _navKeyForIndex(i).currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
      // My day reloads on a Home re-tap (a kiosk punch shows on the next
      // refresh).
      if (i == 0) _myDayKey.currentState?.refresh();
      return;
    }
    setState(() => _index = i);
    // Refresh data when switching to these tabs.
    if (i == 0) _myDayKey.currentState?.refresh();
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
    _myDayKey.currentState?.refresh();
  }

  /// Reached from "HR updated your attendance" (spec 2026-10-07 §3.7):
  /// the Home tab at its root, reloaded.
  Future<void> navigateToMyDay() async {
    _homeNavKey.currentState?.popUntil((r) => r.isFirst);
    if (_index != 0) setState(() => _index = 0);
    await WidgetsBinding.instance.endOfFrame;
    await _myDayKey.currentState?.refresh();
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

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<SessionService>().leaveApprovalsPendingCount;
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
                root: MyDayScreen(
                  key: _myDayKey,
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
          bottomNavigationBar: NavigationBarTheme(
            // Material 3 NavigationBar with a tinted indicator pill
            // behind the active item. Keeps a single source of truth
            // for both selected/unselected label color.
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              elevation: 8,
              height: 72,
              indicatorColor: AppTheme.primaryContainer.withValues(alpha: 0.18),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.primary,
                  );
                }
                return TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.outline,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(color: AppTheme.primary);
                }
                return IconThemeData(color: AppTheme.outline);
              }),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onTabTap,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'HOME',
                ),
                NavigationDestination(
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
                const NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'HISTORY',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'EXPENSES',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The snackbar shown when a notification arrives while the app is open.
/// [onAction] runs for its VIEW / Review action, when the kind has one.
SnackBar notificationArrivalSnackBar(
  NotificationRecord fresh, {
  required VoidCallback onAction,
}) => SnackBar(
  backgroundColor: AppTheme.primary,
  // Flutter 3.44 keeps a bar with an action until it is tapped (persist
  // defaults to action != null); "Leave approved … VIEW" stayed for 6+
  // minutes on the Samsung (APP-8). It times out like any other.
  persist: false,
  duration: const Duration(seconds: 5),
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  content: Row(
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
  action: fresh.snackActionLabel != null
      ? SnackBarAction(
          label: fresh.snackActionLabel!,
          textColor: Colors.white,
          onPressed: onAction,
        )
      : null,
);
