import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/session_service.dart';
import '../../widgets/pill_segments.dart';
import 'my_day/my_day_screen.dart';
import 'overview/team_overview_screen.dart';

/// Builds My day with [header] on top (test seam; the default is the real
/// [MyDayScreen]).
typedef HomeMyDayBuilder =
    Widget Function(GlobalKey<MyDayScreenState> key, Widget? header);

/// Builds Team overview with [header] on top and the fallback callback
/// (test seam; the default is the real [TeamOverviewScreen]).
typedef HomeOverviewBuilder =
    Widget Function(
      GlobalKey<TeamOverviewScreenState> key,
      Widget? header,
      VoidCallback onUnavailable,
    );

/// Prefs key of the dual-mode choice (A-L4): `overview` | `my_day`.
String homeModeKey(SessionService session) =>
    'home_mode|${session.clientDb}|${session.employeeId}';

/// The context a notification tap on the Home tab runs from (A-L8): My
/// day, else Team overview, else the Home tab's Navigator. Each one is
/// under HomeShell's ScaffoldMessenger and the app's providers; null when
/// none is mounted.
BuildContext? homeTabContext({
  required GlobalKey<MyDayScreenState> myDayKey,
  required GlobalKey<TeamOverviewScreenState> overviewKey,
  required GlobalKey<NavigatorState> homeNavKey,
}) {
  for (final context in [
    myDayKey.currentContext,
    overviewKey.currentContext,
    homeNavKey.currentContext,
  ]) {
    if (context != null && context.mounted) return context;
  }
  return null;
}

/// The Home tab root. It shows My day, Team overview, or the switch
/// between them, from `SessionService.homeView`. It re-evaluates on every
/// session notify, and falls back to My day for the run when the overview
/// is unavailable (A-L5).
class HomeRoot extends StatefulWidget {
  const HomeRoot({
    super.key,
    required this.myDayKey,
    required this.overviewKey,
    this.onOpenLeave,
    this.onOpenExpense,
    this.myDayBuilder,
    this.overviewBuilder,
  });

  final GlobalKey<MyDayScreenState> myDayKey;
  final GlobalKey<TeamOverviewScreenState> overviewKey;

  /// Opens leave history on one request (HomeShell.navigateToLeave).
  final void Function(int leaveId)? onOpenLeave;

  /// Opens the Expenses tab (HomeShell.navigateToExpense).
  final void Function(int expenseId)? onOpenExpense;

  @visibleForTesting
  final HomeMyDayBuilder? myDayBuilder;

  @visibleForTesting
  final HomeOverviewBuilder? overviewBuilder;

  @override
  State<HomeRoot> createState() => HomeRootState();
}

class HomeRootState extends State<HomeRoot> {
  /// Dual mode: Team overview (true) or My day (false).
  bool _overviewMode = true;

  /// The [homeModeKey] whose stored choice is applied; null = not read yet.
  String? _modeFor;

  /// The [homeModeKey] being read from prefs.
  String? _modeLoading;

  /// `overviewAccess` when `home/overview` was last unavailable (missing
  /// route, access lost): My day while the session still says this
  /// (A-L5). Null = no fallback.
  String? _unavailableAt;

  /// Reloads the visible screen: HomeShell on a Home tab tap or re-tap,
  /// and after an approval opened from a notification is closed.
  Future<void> refresh() async {
    final myDay = widget.myDayKey.currentState;
    if (myDay != null) {
      await myDay.refresh();
      return;
    }
    await widget.overviewKey.currentState?.refresh();
  }

  /// "HR updated your attendance" / a reminder's Open: My day, reloaded.
  /// In dual mode this shows My day for this visit; the remembered choice
  /// (A-L4) only changes when the user taps the switch.
  Future<void> showMyDay() async {
    if (!mounted) return;
    final session = context.read<SessionService>();
    if (widget.myDayKey.currentState == null &&
        _viewOf(session) == HomeView.dual) {
      setState(() {
        _overviewMode = false;
        _modeFor = homeModeKey(session);
        _modeLoading = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    await refresh();
  }

  /// [SessionService.homeView], unless the overview fell back this run and
  /// the grant has not changed since. Pure: `build` calls it, so it never
  /// assigns state ([didChangeDependencies] clears the fallback).
  HomeView _viewOf(SessionService session) {
    final at = _unavailableAt;
    if (at != null && at == session.overviewAccess) return HomeView.myDay;
    return session.homeView;
  }

  /// `build` watches the session, so every session notify lands here
  /// before the rebuild. A /me that changed overview_access since the
  /// fallback ends it: the overview is tried again (A-L5).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final at = _unavailableAt;
    if (at != null && at != context.read<SessionService>().overviewAccess) {
      _unavailableAt = null;
    }
  }

  void _onUnavailable() {
    if (!mounted) return;
    final access = context.read<SessionService>().overviewAccess;
    setState(() => _unavailableAt = access);
  }

  void _syncMode(String key) {
    if (_modeLoading == key) return;
    _modeLoading = key;
    unawaited(_loadMode(key));
  }

  Future<void> _loadMode(String key) async {
    String? stored;
    try {
      stored = (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      stored = null; // Unreadable prefs: the default.
    }
    if (!mounted || _modeLoading != key) return;
    setState(() {
      _overviewMode = stored != 'my_day';
      _modeFor = key;
      _modeLoading = null;
    });
  }

  Future<void> _pick(int index) async {
    final overview = index == 0;
    if (overview == _overviewMode) return;
    final key = homeModeKey(context.read<SessionService>());
    setState(() => _overviewMode = overview);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, overview ? 'overview' : 'my_day');
    } catch (_) {
      // Not remembered this time; the choice still applies now.
    }
  }

  Widget _myDay(Widget? header) {
    final build = widget.myDayBuilder;
    if (build != null) return build(widget.myDayKey, header);
    return MyDayScreen(
      key: widget.myDayKey,
      header: header,
      onOpenLeave: widget.onOpenLeave,
      onOpenExpense: widget.onOpenExpense,
    );
  }

  Widget _overview(Widget? header) {
    final build = widget.overviewBuilder;
    if (build != null) return build(widget.overviewKey, header, _onUnavailable);
    return TeamOverviewScreen(
      key: widget.overviewKey,
      header: header,
      onOpenLeave: widget.onOpenLeave,
      onOpenExpense: widget.onOpenExpense,
      onUnavailable: _onUnavailable,
    );
  }

  /// Dual mode: the remembered screen with the switch on top.
  Widget _dual(SessionService session) {
    final key = homeModeKey(session);
    if (_modeFor != key) {
      // The remembered choice is read first: no overview call that a
      // remembered "My day" would throw away.
      _syncMode(key);
      return const Scaffold(body: SizedBox.shrink());
    }
    final header = KeyedSubtree(
      key: const ValueKey('home-switch'),
      child: PillSegments(
        labels: const ['Team overview', 'My day'],
        value: _overviewMode ? 0 : 1,
        onChanged: _pick,
        semanticsLabel: 'Home view',
      ),
    );
    return _overviewMode ? _overview(header) : _myDay(header);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return switch (_viewOf(session)) {
      HomeView.myDay => _myDay(null),
      HomeView.overview => _overview(null),
      HomeView.dual => _dual(session),
    };
  }
}
