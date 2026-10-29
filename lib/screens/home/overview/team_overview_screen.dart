import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/omni_colors.dart';
import '../../../models/expense_record.dart';
import '../../../models/my_day.dart';
import '../../../models/team_outlook.dart';
import '../../../models/team_overview.dart';
import '../../../services/omni_mobile_api.dart';
import '../../../services/session_service.dart';
import '../../../services/team_cache.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/omni_app_bar.dart';
import '../../../widgets/pill_segments.dart';
import '../../team/team_colors.dart';
import '../../team/team_leave_screen.dart';
import '../my_day/for_you_list.dart';
import '../my_day/for_you_navigation.dart';
import '../my_day/my_day_display.dart';
import 'overview_copy.dart';
import 'overview_drill_screen.dart';
import 'overview_tiles.dart';
import 'person_sheet.dart';
import 'who_out_card.dart';

/// The Team overview (Home for employees HR granted it, D5): live counts,
/// Yesterday as reviewed, Who's out and For you, from `home/overview`.
/// Same refresh contract as My day.
class TeamOverviewScreen extends StatefulWidget {
  const TeamOverviewScreen({
    super.key,
    this.apiBuilder,
    this.appBar,
    this.header,
    this.onOpenLeave,
    this.onOpenExpense,
    this.onUnavailable,
    this.refreshSession,
    this.destinationBuilder,
    this.outlookBuilder,
    this.onBucketTap,
    this.onPersonTap,
  });

  /// Test seam: builds the API client from the session.
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// Test seam: replaces [OmniAppBar].
  final PreferredSizeWidget? appBar;

  /// Shown first in the list in every state (HomeRoot's switch, Task 9).
  final Widget? header;

  /// For-you `my_leave` rows (HomeShell.navigateToLeave).
  final void Function(int leaveId)? onOpenLeave;

  /// For-you `my_expense` rows whose record could not be loaded.
  final void Function(int expenseId)? onOpenExpense;

  /// `home/overview` answered a missing route (older connector) or lost
  /// access: HomeRoot shows My day for the rest of the run (A-L5).
  final VoidCallback? onUnavailable;

  /// Test seam: replaces SessionService.refreshMe.
  @visibleForTesting
  final Future<void> Function()? refreshSession;

  /// Test seam: replaces the screen a For-you row pushes.
  @visibleForTesting
  final Widget Function(ForYouItem item, ExpenseRecord? expense)?
  destinationBuilder;

  /// Test seam: replaces the pushed outlook ([TeamLeaveScreen]).
  @visibleForTesting
  final Widget Function(String context, int? departmentId)? outlookBuilder;

  /// Test seam: takes a count-tile tap (names only).
  @visibleForTesting
  final void Function(String bucket)? onBucketTap;

  /// Test seam: takes a Who's out row tap (names, Attendance, tracked).
  @visibleForTesting
  final void Function(int employeeId)? onPersonTap;

  @override
  State<TeamOverviewScreen> createState() => TeamOverviewScreenState();
}

class TeamOverviewScreenState extends State<TeamOverviewScreen> {
  /// The answer on screen. Usually for the current day + department; after
  /// a day or department switch it is the previous selection's, kept under
  /// a thin progress line until the new answer lands (P1, 1.34.1) —
  /// [_shownDay] / [_shownDepartment] say which selection it is for. Null
  /// while nothing can be shown.
  TeamOverview? _overview;

  /// The day (`today` / `yesterday`) and department [_overview] answers.
  String? _shownDay;
  int? _shownDepartment;

  /// A fetch is running (drives the thin progress line).
  bool _busy = false;

  /// The last good answer of any selection: keeps the department chips and
  /// the day switch on screen while a new selection loads.
  TeamOverview? _last;

  /// When [_overview] came from TeamCache (offline), its save time.
  DateTime? _cachedAt;

  String? _firstLoadError;
  bool _refreshFailed = false;
  String _day = 'today';
  int? _departmentId;

  /// The fetch currently running; every overlapping [refresh] shares it.
  Future<void>? _inFlight;

  /// The bindings [_overview] and [_last] were asked (or read from the
  /// cache) under (A-L22); each is set and cleared with its answer.
  TeamCacheBinding? _overviewBinding;
  TeamCacheBinding? _lastBinding;

  /// What was shown went stale while nothing could be asked (signed out,
  /// a sign-out running): the next notify that allows it asks again.
  bool _reloadPending = false;

  /// Every session notify and every cache clear (A-L22).
  late final Listenable _watch;

  final _forYouGuard = ForYouTapGuard();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _watch = TeamCache.watch(context.read<SessionService>())
      ..addListener(_onBindingChanged);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        refresh();
      },
    );
    refresh();
    // The cached answer paints while the first fetch runs (P1), as the
    // outlook does; read under its own binding, never shown when stale.
    unawaited(_showCached());
  }

  /// [_overview] answers the selection on screen now (not a previous day
  /// or department kept while the new one loads).
  bool get _shownMatches =>
      _overview != null &&
      _shownDay == _day &&
      _shownDepartment == _departmentId;

  /// Shows the cached answer of the current selection (today only; only
  /// today is cached) unless a matching answer is already on screen: on
  /// first build, and after a switch to a department of today. The binding
  /// is taken with the key, before the read (A-L15); a read that lands
  /// after a clear, a sign-out, a new sign-in, a scope change or another
  /// switch is dropped (A-L21). For you is stripped (A-X2).
  Future<void> _showCached() async {
    final session = context.read<SessionService>();
    if (session.employeeId <= 0 || session.isClearing) return;
    final day = _day;
    final departmentId = _departmentId;
    if (day != 'today') return;
    final key = TeamCache.overviewKey(session, departmentId: departmentId);
    final binding = TeamCache.bind(session);
    final hit = await TeamCache.readQuietly(session, key);
    if (!mounted || hit == null) return;
    if (day != _day || departmentId != _departmentId || _shownMatches) return;
    if (!binding.isCurrent(session)) return;
    final overview = TeamOverview.fromJson({
      ...hit.$1,
      'for_you': const <Object>[],
    });
    setState(() {
      _overview = overview;
      _overviewBinding = binding;
      _shownDay = day;
      _shownDepartment = departmentId;
      if (_last == null) {
        _last = overview;
        _lastBinding = binding;
      }
      _cachedAt = hit.$2;
      _firstLoadError = null;
    });
  }

  @override
  void dispose() {
    _watch.removeListener(_onBindingChanged);
    _lifecycle.dispose();
    super.dispose();
  }

  /// The API client of one attempt, built from [session] as it is now
  /// (A-L22, TLP3-F01).
  OmniMobileApi _apiFor(SessionService session) =>
      widget.apiBuilder?.call(session) ??
      OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );

  OmniMobileApi _api() => _apiFor(context.read<SessionService>());

  bool _shownIsCurrent(SessionService session) {
    bool holds(Object? shown, TeamCacheBinding? binding) =>
        shown == null || (binding != null && binding.isCurrent(session));
    return holds(_overview, _overviewBinding) && holds(_last, _lastBinding);
  }

  /// Forgets everything an answer put on screen (the department chips in
  /// [_last] included).
  void _dropShown() {
    _overview = null;
    _overviewBinding = null;
    _shownDay = null;
    _shownDepartment = null;
    _last = null;
    _lastBinding = null;
    _cachedAt = null;
    _firstLoadError = null;
    _refreshFailed = false;
  }

  /// A session notify or a cache clear (A-L22): what is on screen is
  /// checked against the binding it was asked under. A stale answer goes
  /// before the next frame, and the current selection is asked again,
  /// unless a request is on the wire (it checks its own binding when it
  /// lands) or nothing may be asked yet (signed out, a sign-out running).
  void _onBindingChanged() {
    if (!mounted) return;
    final session = context.read<SessionService>();
    if (!_shownIsCurrent(session)) {
      setState(_dropShown);
      if (_inFlight == null) _reloadPending = true;
    }
    if (!_reloadPending || _inFlight != null) return;
    if (session.employeeId <= 0 || session.isClearing) return;
    _reloadPending = false;
    unawaited(refresh());
  }

  /// Reload the overview. Called on first build, pull-to-refresh, on
  /// return from a pushed screen, on app resume and by HomeRoot (Task 9).
  /// Overlapping calls share the one request in flight.
  Future<void> refresh() => _inFlight ??= _startLoad().whenComplete(() {
    _inFlight = null;
    if (mounted && _busy) setState(() => _busy = false);
  });

  Future<void> _startLoad() {
    // No setState: refresh() runs from initState too; the frames that
    // show the progress line (a switch, a cached answer) rebuild anyway.
    _busy = true;
    return _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionService>();
    // Signed out, or a sign-out running (T8-m1): nothing is sent with the
    // token being revoked. The notify that ends the sign-out asks again
    // ([_onBindingChanged]) if someone is still signed in.
    if (session.employeeId <= 0 || session.isClearing) {
      _reloadPending = true;
      return;
    }
    final day = _day;
    final departmentId = _departmentId;
    // Only today is ever written; the key is the same for a yesterday
    // request, which never reads or writes it. The cache binding is taken
    // with the key, before the request (A-L15), and checked before
    // anything the answer drives (A-L21).
    final cacheKey = TeamCache.overviewKey(session, departmentId: departmentId);
    _reloadPending = false;
    // The client is built from the same session in the same synchronous
    // step as the binding (A-L22, TLP3-F01).
    final binding = TeamCache.bind(session);
    final api = _apiFor(session);
    try {
      final overview = await api.fetchOverview(
        day: day,
        departmentId: departmentId,
      );
      if (!mounted || day != _day || departmentId != _departmentId) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      setState(() {
        _overview = overview;
        _overviewBinding = binding;
        _shownDay = day;
        _shownDepartment = departmentId;
        _last = overview;
        _lastBinding = binding;
        _cachedAt = null;
        _firstLoadError = null;
        _refreshFailed = false;
      });
      if (day == 'today') {
        // For you is never cached (A-X2): its cards follow plan flags the
        // scope signature does not cover. A new map: overview.raw is the
        // caller's and is never changed. Storing is best effort: a prefs
        // failure is not a failed refresh (T5-M1).
        unawaited(
          TeamCache.writeQuietly(session, cacheKey, {
            ...overview.raw,
            'for_you': const <Object>[],
          }, binding: binding),
        );
      }
      _syncApprovals(session, overview);
    } catch (e) {
      if (!mounted || day != _day || departmentId != _departmentId) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      if (isMissingRoute(e) || isAccessLost(e)) {
        if (isAccessLost(e)) {
          // Started, not awaited (as Task 7 does): Home falls back to My
          // day at once instead of waiting for a /me on a slow link (A4).
          // The clear bumps the cache generation synchronously.
          // A prefs failure in the clear changes nothing here (T6-M2).
          unawaited(TeamCache.clearEmployeeQuietly(session));
          unawaited(_refreshSession().catchError((_) {}));
        }
        setState(() {
          _dropShown();
          _firstLoadError = friendlyError(e, context: ErrorContext.team);
        });
        widget.onUnavailable?.call();
        return;
      }
      if (e is ApiException &&
          e.errorCode == 'invalid_department' &&
          departmentId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, context: ErrorContext.team))),
        );
        setState(() => _departmentId = null);
        return _load();
      }
      // A failed refresh keeps only what still holds (A-L22): an answer
      // whose binding moved goes, and only a cached entry read under this
      // request's (current) binding may take its place.
      if (!_shownIsCurrent(session)) setState(_dropShown);
      // An answer kept from the previous selection (P1) is not this
      // selection's: it goes; the chips in [_last] stay.
      if (_overview != null && !_shownMatches) {
        setState(() {
          _overview = null;
          _overviewBinding = null;
          _shownDay = null;
          _shownDepartment = null;
          _cachedAt = null;
        });
      }
      if (_overview != null) {
        setState(() => _refreshFailed = true);
        return;
      }
      if (day == 'today') {
        // An unreadable cache reads as an empty one, so the error view
        // shows instead of an endless spinner (T6-M2).
        final cached = await TeamCache.readQuietly(session, cacheKey);
        if (!mounted || day != _day || departmentId != _departmentId) return;
        if (!binding.isCurrent(session)) return _rebind(session);
        if (cached != null) {
          // Stripped on read too (A-X2): an entry an earlier build stored
          // never shows For you cards.
          final overview = TeamOverview.fromJson({
            ...cached.$1,
            'for_you': const <Object>[],
          });
          setState(() {
            _overview = overview;
            _overviewBinding = binding;
            _shownDay = day;
            _shownDepartment = departmentId;
            if (_last == null) {
              _last = overview;
              _lastBinding = binding;
            }
            _cachedAt = cached.$2;
            _refreshFailed = true;
          });
          return;
        }
      }
      setState(
        () => _firstLoadError = friendlyError(e, context: ErrorContext.team),
      );
    }
  }

  /// The answer (or cached read) in hand was asked under a binding that
  /// has moved since (a cache clear, a sign-out, a new sign-in or a scope
  /// change; A-L21): it is neither shown nor stored. What is on screen
  /// belongs to the old binding too (the department chips in [_last]
  /// included), so it goes, and the current selection is asked again
  /// inside the same in-flight refresh, with a client built from the
  /// session of now (A-L22). Nothing is asked while signed out or while a
  /// sign-out runs; the notify that ends the sign-out asks then.
  Future<void> _rebind(SessionService session) {
    setState(_dropShown);
    if (session.employeeId <= 0 || session.isClearing) {
      _reloadPending = true;
      return Future<void>.value();
    }
    return _load();
  }

  /// The For-you approvals card and the LEAVE badge must show one number
  /// (as My day does): a card the session does not agree with re-pulls /me.
  void _syncApprovals(SessionService session, TeamOverview overview) {
    final cardCount = overview.forYou
        .where((item) => item.kind == 'leave_approvals')
        .fold<int>(0, (n, item) => n + item.count);
    if ((session.leaveApprovalsEnabled || cardCount > 0) &&
        cardCount != session.leaveApprovalsPendingCount) {
      unawaited(_refreshSession().catchError((_) {}));
    }
  }

  Future<void> _refreshSession() async {
    final custom = widget.refreshSession;
    if (custom != null) {
      await custom();
    } else {
      await context.read<SessionService>().refreshMe();
    }
  }

  Future<void> _retry() {
    setState(() => _firstLoadError = null);
    return refresh();
  }

  /// A day or department switch. What is on screen stays, under a thin
  /// progress line, until the new selection answers (P1, 1.34.1); a cached
  /// answer of a today selection replaces it at once. The request on the
  /// wire (for the old selection) lands first and is dropped by [_load]
  /// (it checks day and department), then the new selection loads.
  Future<void> _select({
    String? day,
    int? departmentId,
    bool allDepartments = false,
  }) async {
    final nextDay = day ?? _day;
    final nextDepartment = allDepartments
        ? null
        : (departmentId ?? _departmentId);
    if (nextDay == _day && nextDepartment == _departmentId) return;
    setState(() {
      _day = nextDay;
      _departmentId = nextDepartment;
      _busy = true;
      _firstLoadError = null;
      _refreshFailed = false;
    });
    unawaited(_showCached());
    await _inFlight;
    if (!mounted) return;
    // The old request's end cleared the line; this one keeps it on.
    setState(() => _busy = true);
    await refresh();
  }

  /// A For-you card. The cards of a previous selection, kept while the new
  /// one loads, open nothing (1.34.1 review fix 8).
  Future<void> _onForYouTap(ForYouItem item) async {
    if (!_shownMatches) return;
    await _openForYou(item);
  }

  Future<void> _openForYou(ForYouItem item) => openForYouItem(
    context,
    item,
    guard: _forYouGuard,
    api: _api,
    refreshSession: _refreshSession,
    refresh: refresh,
    onOpenLeave: widget.onOpenLeave,
    onOpenExpense: widget.onOpenExpense,
    destinationBuilder: widget.destinationBuilder,
  );

  /// "See 30 / 60 / 90 days": the outlook in the overview context for the
  /// current department, at the stored range (A-L2), on the tab Navigator.
  /// The link of a previous selection, kept while the new one loads, opens
  /// nothing: it would open the new department under the old card.
  Future<void> _openOutlook() async {
    if (!_shownMatches) return;
    final departmentId = _departmentId;
    final builder = widget.outlookBuilder;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => builder != null
            ? builder('overview', departmentId)
            : TeamLeaveScreen(
                context: 'overview',
                departmentId: departmentId,
                apiBuilder: widget.apiBuilder,
              ),
      ),
    );
    if (mounted) await refresh();
  }

  /// A count tile (names only): Task 7's drill-down on the tab Navigator,
  /// for today's counts and the current department; back refreshes.
  void _openBucket(String bucket) {
    // The tiles of a previous selection, kept while the new one loads, do
    // not open a drill-down for the new one.
    if (!_shownMatches) return;
    final custom = widget.onBucketTap;
    if (custom != null) return custom(bucket);
    final overview = _overview;
    final counts = overview?.counts;
    if (overview == null || counts == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OverviewDrillScreen(
              bucket: bucket,
              counts: counts,
              departmentId: _departmentId,
              scopeLabel: overview.scope.label,
              apiBuilder: widget.apiBuilder,
            ),
          ),
        )
        .then((_) {
          if (mounted) refresh();
        });
  }

  /// A Who's out row (names, Attendance and a tracked person, L2): Task 7's
  /// person sheet on the root Navigator.
  /// A row of a previous selection, kept while the new one loads, opens
  /// nothing.
  void _openPerson(int employeeId) {
    if (!_shownMatches) return;
    final custom = widget.onPersonTap;
    if (custom != null) return custom(employeeId);
    // The sheet builds its client per attempt (A-L22). The builder
    // captures the seam, not this State: the sheet can outlive the screen.
    final builder = widget.apiBuilder;
    showOverviewPersonSheet(
      context,
      employeeId: employeeId,
      apiFor: (s) =>
          builder?.call(s) ??
          OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar:
          widget.appBar ??
          OmniAppBar(
            title: helloTitle(
              session.employeeName,
              session.userName,
              session.userLogin,
            ),
          ),
      body: Column(
        children: [
          if (_refreshFailed) _strip(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  16 + MediaQuery.of(context).viewPadding.bottom,
                ),
                children: [
                  if (widget.header != null) ...[
                    widget.header!,
                    const SizedBox(height: 14),
                  ],
                  ..._content(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context) {
    final at = _cachedAt;
    final text = friendlyError(myDayRefreshFailed);
    final c = context.omni;
    return Container(
      key: const ValueKey('ov-refresh-strip'),
      width: double.infinity,
      color: c.error.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        at == null
            ? text
            : '$text\n${OverviewCopy.showingFrom(_savedWhen(at))}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.error),
      ),
    );
  }

  /// When the cached answer was saved, as the strip says it (T8-m4):
  /// "at 18:03" today, "yesterday at 18:03", else "on Tue 21 Oct at 18:03".
  static String _savedWhen(DateTime at) {
    final now = DateTime.now();
    final time = DateFormat('HH:mm', 'en_US').format(at);
    if (DateUtils.isSameDay(at, now)) return 'at $time';
    if (DateUtils.isSameDay(at, DateTime(now.year, now.month, now.day - 1))) {
      return 'yesterday at $time';
    }
    return 'on ${DateFormat('EEE d MMM', 'en_US').format(at)} at $time';
  }

  List<Widget> _content(BuildContext context) {
    final last = _last;
    final error = _firstLoadError;
    if (last == null) {
      return [
        if (error == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: ErrorStateView(message: error, onRetry: _retry),
          ),
      ];
    }
    final overview = _overview;
    return [
      if (last.departments.isNotEmpty) ...[
        _departmentChips(last.departments),
        const SizedBox(height: 14),
      ],
      if (last.sections.attendance) ...[
        PillSegments(
          labels: const [OverviewCopy.todayLive, OverviewCopy.yesterdayLabel],
          value: _day == 'today' ? 0 : 1,
          semanticsLabel: OverviewCopy.whichDay,
          onChanged: (i) => _select(day: i == 0 ? 'today' : 'yesterday'),
        ),
        const SizedBox(height: 14),
      ],
      if (overview == null)
        error == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : ErrorStateView(message: error, onRetry: _retry)
      else ...[
        // The sections stay while a switch or the first fetch runs (P1):
        // a thin line says newer numbers are on the way.
        if (_busy && (!_shownMatches || _cachedAt != null)) ...[
          const LinearProgressIndicator(
            key: ValueKey('ov-progress'),
            minHeight: 2,
          ),
          const SizedBox(height: 12),
        ],
        // A previous selection kept while the new one loads is dimmed; its
        // rows, cards and links open nothing (1.34.1 review fix 8).
        if (_shownMatches)
          ..._sections(context, overview)
        else
          Opacity(
            key: const ValueKey('ov-kept'),
            opacity: 0.55,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _sections(context, overview),
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _sections(BuildContext context, TeamOverview o) {
    final sectionStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: context.omni.textSub,
      fontWeight: FontWeight.w700,
    );
    final scopeLabel = o.scope.label;
    final empty = o.scope.emptyReason;
    final counts = o.counts;
    final reviewed = o.reviewed;
    final whoOut = o.whoOut;
    final today = o.date ?? DateUtils.dateOnly(DateTime.now());
    // The day the shown answer is for (a switch keeps the previous one on
    // screen until the new one lands).
    final shownDay = _shownDay ?? _day;
    final attendance = <Widget>[
      if (empty == null) ...[
        if (shownDay == 'today' && counts != null) ...[
          OverviewTodayTile(
            counts: counts,
            scopeLabel: scopeLabel,
            asOf: o.asOf,
            // A cached answer never reads as live (T8-m4): the stored body
            // keeps the server's `live: true`.
            live: o.live && _cachedAt == null,
          ),
          const SizedBox(height: 8),
          OverviewCountGrid(
            cells: todayCells(counts),
            onTap: o.names ? _openBucket : null,
          ),
          const SizedBox(height: 14),
        ],
        if (shownDay == 'yesterday' && reviewed != null) ...[
          OverviewYesterdayTile(reviewed: reviewed, scopeLabel: scopeLabel),
          const SizedBox(height: 8),
          OverviewCountGrid(cells: yesterdayCells(reviewed)),
          const SizedBox(height: 14),
        ],
        if (!o.names && o.sections.attendance) ...[
          _countsOnlyLine(),
          const SizedBox(height: 14),
        ],
      ],
    ];
    final whoOutBlock = <Widget>[
      if (empty == null)
        if (o.sections.leave && whoOut != null) ...[
          WhoOutCard(
            whoOut: whoOut,
            scopeLabel: scopeLabel,
            today: today,
            canOpenPerson: o.names && o.sections.attendance,
            onPerson: _openPerson,
            onSeeOutlook: _openOutlook,
          ),
          const SizedBox(height: 16),
        ],
    ];
    final forYouBlock = <Widget>[
      // For you comes from a live answer only (A-X2): a cached answer
      // shows no For you section at all, not even its empty state.
      if (_cachedAt == null) ...[
        Text(OverviewCopy.forYou, style: sectionStyle),
        const SizedBox(height: 8),
        ForYouList(
          // "Yesterday looks incomplete" is answered on My day.
          items: o.forYou
              .where((item) => item.kind != 'yesterday_incomplete')
              .toList(),
          onTap: _onForYouTap,
        ),
      ],
    ];
    if (empty != null) {
      return [_emptyCard(empty), const SizedBox(height: 16), ...forYouBlock];
    }
    return [
      OverviewColumns(blocks: [attendance, whoOutBlock, forYouBlock]),
    ];
  }

  Widget _departmentChips(List<TeamDepartment> departments) {
    final c = context.omni;
    final t = TeamColors.of(context);
    Widget chip(Key key, String label, bool on, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          selected: on,
          child: Material(
            color: on ? t.accentTint : Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(
                color: on ? t.accentTint : t.chipBorder,
                width: 1.5,
              ),
            ),
            child: InkWell(
              key: key,
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? t.onAccentTint : c.textSub,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            const ValueKey('ov-dept-all'),
            OverviewCopy.allDepartments,
            _departmentId == null,
            () => _select(allDepartments: true),
          ),
          for (final d in departments)
            chip(
              ValueKey('ov-dept-${d.id}'),
              d.name,
              _departmentId == d.id,
              () => _select(departmentId: d.id),
            ),
        ],
      ),
    );
  }

  Widget _countsOnlyLine() {
    final muted = context.omni.textMuted;
    return Padding(
      key: const ValueKey('ov-counts-only'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 14, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              OverviewCopy.countsOnly,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String reason) {
    return Card(
      key: const ValueKey('ov-empty'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          reason == 'no_department'
              ? OverviewCopy.noDepartment
              : OverviewCopy.noPeople,
          style: TextStyle(fontSize: 14, color: context.omni.textSub),
        ),
      ),
    );
  }
}

/// Lays the overview's blocks (today's tile and counts, Who's out, For you)
/// side by side when the screen is wide — iPhone Duo open: two columns
/// upright, three sideways — and stacked on a phone. With two columns,
/// Who's out and For you share the second.
class OverviewColumns extends StatelessWidget {
  const OverviewColumns({super.key, required this.blocks});

  /// Width (content, between the side paddings) from which a second and a
  /// third column are used.
  static const twoColumnWidth = 600.0;
  static const threeColumnWidth = 820.0;

  final List<List<Widget>> blocks;

  @override
  Widget build(BuildContext context) {
    final groups = blocks.where((b) => b.isNotEmpty).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= threeColumnWidth
            ? 3
            : w >= twoColumnWidth
            ? 2
            : 1;
        if (cols == 1 || groups.length < 2) {
          return _stack([for (final g in groups) ...g]);
        }
        final columns = cols == 2 && groups.length == 3
            ? [groups[0], groups[1] + groups[2]]
            : groups;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: _stack(columns[i])),
            ],
          ],
        );
      },
    );
  }

  static Widget _stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}
