import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/team_outlook.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../services/team_cache.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/omni_app_bar.dart';
import '../../widgets/pill_segments.dart';
import 'heat_map.dart';
import 'team_colors.dart';
import 'team_day_detail.dart';
import 'team_format.dart';
import 'team_widgets.dart';

/// The outlook ranges, in switch order.
const teamLeaveRanges = [30, 60, 90];

/// Labels of the team-context views (`views` in the answer); a view the
/// app does not know is not offered.
const teamLeaveViewLabels = {
  'team': 'My team',
  'approvees': 'People you approve',
  'company': 'Everyone',
};

/// Prefs key of the remembered range (A-L2).
String teamLeaveRangeKey(SessionService s) =>
    'team_leave_range|${s.clientDb}|${s.employeeId}';

/// The remembered range of this employee; 30 when none, or when prefs
/// fail (A-L2, final review M4).
Future<int> readTeamLeaveRange(SessionService s) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(teamLeaveRangeKey(s));
    return teamLeaveRanges.contains(v) ? v! : 30;
  } catch (e) {
    debugPrint('Team leave: range read failed: $e');
    return 30;
  }
}

/// Remembers the range; never throws (a prefs failure only forgets it).
Future<void> saveTeamLeaveRange(SessionService s, int days) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(teamLeaveRangeKey(s), days);
  } catch (e) {
    debugPrint('Team leave: range save failed: $e');
  }
}

/// Team leave outlook: who is off over the next 30 / 60 / 90 days as a
/// calendar heat map (D1); tap a day to see who.
///
/// [context] `'team'` is the LEAVE tab's "Team leave" (views: My team /
/// People you approve / Everyone); `'overview'` is the Team overview's
/// "Leave outlook" (people of the overview grant, department chips for
/// company access, starting on [departmentId]).
class TeamLeaveScreen extends StatefulWidget {
  const TeamLeaveScreen({
    super.key,
    this.context = 'team',
    this.departmentId,
    this.initialDays,
    this.apiBuilder,
    this.appBar,
  });

  /// `'team'` or `'overview'` (the contract's `context`).
  final String context;

  /// Overview context only: the department the overview showed.
  final int? departmentId;

  /// 30, 60 or 90; null = the remembered range (A-L2).
  final int? initialDays;

  /// Test seam: builds the API client from the session.
  @visibleForTesting
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// Test seam: replaces [OmniAppBar], which needs the notification and
  /// session services.
  @visibleForTesting
  final PreferredSizeWidget? appBar;

  @override
  State<TeamLeaveScreen> createState() => TeamLeaveScreenState();
}

class TeamLeaveScreenState extends State<TeamLeaveScreen> {
  /// Every session notify and every cache clear (A-L22).
  late final Listenable _watch;

  /// False until the remembered range is read; the body is a skeleton.
  bool _rangeKnown = false;
  int _days = 30;
  String _view = 'team';
  int? _departmentId;

  /// What the screen shows: the last good answer for the current choice
  /// (live, or from TeamCache), with the time it was fetched.
  TeamOutlook? _outlook;
  DateTime? _shownAt;

  /// The binding [_outlook] was asked (or read from the cache) under
  /// (A-L22). Set with [_outlook], cleared with it.
  TeamCacheBinding? _shownBinding;

  /// The last good answer, kept while the next choice loads or fails: the
  /// header and the view / department chips are drawn from it, so a tap
  /// does not make them flash and a failed first fetch of a new choice
  /// leaves the way back. Set with [_outlook]; unlike it, a choice change
  /// keeps it. Dropped, with [_chromeBinding], as soon as that binding is
  /// no longer current (A-L22): a revoked or changed scope keeps no chips.
  TeamOutlook? _chrome;
  TeamCacheBinding? _chromeBinding;

  /// What was shown went stale while nothing could be asked (signed out,
  /// or a sign-out running): the next notify that allows it asks again.
  bool _reloadPending = false;

  /// A refresh failed while [_outlook] stays on screen (the red strip).
  String? _stripError;

  /// The first load failed and there is nothing to show.
  String? _fatalError;

  /// The server says this view is no longer allowed (A-L3).
  String? _lostError;

  DateTime? _selected;

  /// The fetch running for the current choice; overlapping [refresh]
  /// calls share it. A choice change starts a new one and bumps [_seq],
  /// so an older answer is dropped.
  Future<void>? _inFlight;
  int _seq = 0;

  bool get _isOverview => widget.context == 'overview';

  @override
  void initState() {
    super.initState();
    _watch = TeamCache.watch(context.read<SessionService>())
      ..addListener(_onBindingChanged);
    _departmentId = _isOverview ? widget.departmentId : null;
    unawaited(_start());
  }

  @override
  void dispose() {
    _watch.removeListener(_onBindingChanged);
    super.dispose();
  }

  /// The API client of this attempt (A-L22, TLP3-F01): built from the
  /// session of the moment, next to the attempt's binding, so a retry after
  /// a new sign-in sends the new token, never the one the screen opened
  /// with.
  OmniMobileApi _apiFor(SessionService s) =>
      widget.apiBuilder?.call(s) ??
      OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token);

  /// A session notify or a cache clear (A-L22): what is on screen is
  /// checked against the binding it was asked under. A stale answer goes
  /// before the next frame; the current choice is asked again unless a
  /// request is on the wire (it checks its own binding when it lands) or
  /// nothing may be asked yet (signed out, a sign-out running).
  void _onBindingChanged() {
    if (!mounted) return;
    final session = context.read<SessionService>();
    if (_staleShown(session)) {
      setState(_dropShown);
      // A request on the wire checks its own binding when it lands
      // (_rebind), so only an idle screen asks again from here.
      if (_inFlight == null) _reloadPending = true;
    }
    if (!_reloadPending || _inFlight != null) return;
    if (session.employeeId <= 0 || session.isClearing) return;
    _reloadPending = false;
    unawaited(refresh());
  }

  /// True when an answer, or the chips kept from one, belongs to a binding
  /// that is no longer current (A-L22).
  bool _staleShown(SessionService session) {
    bool stale(TeamCacheBinding? b) => b == null || !b.isCurrent(session);
    return (_outlook != null && stale(_shownBinding)) ||
        (_chrome != null && stale(_chromeBinding));
  }

  /// Forgets the shown answer and everything that describes it, the kept
  /// chips included.
  void _dropShown() {
    _outlook = null;
    _shownAt = null;
    _shownBinding = null;
    _chrome = null;
    _chromeBinding = null;
    _stripError = null;
    _fatalError = null;
    _lostError = null;
  }

  Future<void> _start() async {
    final session = context.read<SessionService>();
    final initial = widget.initialDays;
    final days = teamLeaveRanges.contains(initial)
        ? initial!
        : await readTeamLeaveRange(session);
    if (!mounted) return;
    setState(() {
      _days = days;
      _rangeKnown = true;
    });
    await _showCached(_seq);
    if (!mounted) return;
    await refresh();
  }

  /// The TeamCache key of the current choice (A-L3). The LEAVE tab row
  /// (Task 6) stores its 30-day team answer under the same
  /// [TeamCache.outlookKey], so the screen opens on it at once (A-L1).
  String _cacheKey(SessionService s) => TeamCache.outlookKey(
    s,
    days: _days,
    context: widget.context,
    view: _view,
    departmentId: _departmentId,
  );

  /// Shows the cached answer for the current choice, if any, until the
  /// fetch answers (A-L1).
  Future<void> _showCached(int seq) async {
    final session = context.read<SessionService>();
    final binding = TeamCache.bind(session);
    // Unreadable prefs read like an empty cache: the fetch still runs.
    final hit = await TeamCache.readQuietly(session, _cacheKey(session));
    if (!mounted || seq != _seq || hit == null || _outlook != null) return;
    // A clear, a sign-out or a new sign-in while the read ran (A-L21): not
    // shown. The fetch that follows asks under the new binding.
    if (!binding.isCurrent(session)) return;
    final (body, savedAt) = hit;
    final outlook = TeamOutlook.fromJson(body);
    setState(() {
      _outlook = outlook;
      _shownAt = savedAt;
      _shownBinding = binding;
      _chrome = outlook;
      _chromeBinding = binding;
      _selected = _keepOrDefault(outlook);
    });
  }

  /// Reload the outlook. Called on first build, pull-down and every
  /// range / view / department change. Overlapping calls share one
  /// request.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> started;
    started = _load(_seq).whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    });
    _inFlight = started;
    return started;
  }

  Future<void> _load(int seq) async {
    final session = context.read<SessionService>();
    _reloadPending = false;
    // The cache binding is taken with the key, before the request (A-L15),
    // and checked before anything the answer drives (A-L21): an answer that
    // lands after a clear, a sign-out, a new sign-in or a scope change is
    // neither shown nor stored. The client is built from the same session
    // in the same synchronous step (A-L22, TLP3-F01): its token is the one
    // the binding describes.
    final key = _cacheKey(session);
    final binding = TeamCache.bind(session);
    final api = _apiFor(session);
    try {
      final outlook = await api.fetchTeamOutlook(
        days: _days,
        context: widget.context,
        view: _view,
        departmentId: _departmentId,
      );
      if (!mounted || seq != _seq) return;
      if (!binding.isCurrent(session)) return _rebind(seq, session);
      setState(() {
        _outlook = outlook;
        _shownAt = DateTime.now();
        _shownBinding = binding;
        _chrome = outlook;
        _chromeBinding = binding;
        _stripError = null;
        _fatalError = null;
        _lostError = null;
        _selected = _keepOrDefault(outlook);
      });
      // Storing is best effort and runs on its own: a prefs failure is not
      // a failed refresh, and the refresh does not wait on the disk (M1).
      unawaited(
        TeamCache.writeQuietly(session, key, outlook.raw, binding: binding),
      );
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (!binding.isCurrent(session)) return _rebind(seq, session);
      if (isAccessLost(e)) {
        // A prefs failure in the clear still ends on the lost view.
        await TeamCache.clearEmployeeQuietly(session);
        unawaited(session.refreshMe());
        // The clear took a while: a newer choice may be loading or shown
        // by now, and its answer must stand (M4).
        if (!mounted || seq != _seq) return;
        setState(() {
          _lostError = friendlyError(e, context: ErrorContext.team);
          _outlook = null;
          _shownBinding = null;
          _chrome = null;
          _chromeBinding = null;
          _stripError = null;
          _fatalError = null;
        });
        return;
      }
      final text = friendlyError(e, context: ErrorContext.team);
      // A failed refresh never keeps an answer whose binding has moved
      // (A-L22): it goes, and the error view takes its place.
      final stale = _staleShown(session);
      setState(() {
        if (stale) _dropShown();
        if (_outlook == null) {
          _fatalError = text;
        } else {
          _stripError = text;
        }
      });
    }
  }

  /// The answer in hand was asked under a binding that has moved since (a
  /// cache clear, a sign-out, a new sign-in or a scope change; A-L21): it
  /// is neither shown nor stored. What is on screen belongs to the old
  /// binding too, so it goes, and the current choice is asked again inside
  /// the same in-flight refresh, with a client built from the session of
  /// now (A-L22). Nothing is asked while signed out or while a sign-out
  /// runs; the notify that ends the sign-out asks then (_onBindingChanged).
  Future<void> _rebind(int seq, SessionService session) {
    setState(_dropShown);
    if (session.employeeId <= 0 || session.isClearing) {
      _reloadPending = true;
      return Future<void>.value();
    }
    return _load(seq);
  }

  /// The selected day survives a reload while it is still in range.
  DateTime _keepOrDefault(TeamOutlook o) {
    final sel = _selected;
    if (sel != null &&
        o.days.isNotEmpty &&
        !sel.isBefore(dayOnly(o.days.first.date)) &&
        !sel.isAfter(dayOnly(o.days.last.date))) {
      return sel;
    }
    return defaultTeamDay(o);
  }

  /// A new range, view or department: what is on screen belongs to the
  /// old choice, so it goes; the cache for the new one shows at once.
  Future<void> _change(VoidCallback apply) async {
    _seq++;
    _inFlight = null;
    setState(() {
      apply();
      _outlook = null;
      _shownAt = null;
      _shownBinding = null;
      _stripError = null;
      _fatalError = null;
    });
    await _showCached(_seq);
    if (!mounted) return;
    await refresh();
  }

  void _setDays(int days) {
    if (days == _days) return;
    unawaited(saveTeamLeaveRange(context.read<SessionService>(), days));
    unawaited(_change(() => _days = days));
  }

  Future<void> _retry() {
    setState(() => _fatalError = null);
    return refresh();
  }

  @override
  Widget build(BuildContext context) {
    final strip = _stripError;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar:
          widget.appBar ??
          OmniAppBar(title: _isOverview ? 'Leave outlook' : 'Team leave'),
      body: Column(
        children: [
          if (strip != null && _outlook != null)
            Container(
              key: const ValueKey('team-strip'),
              width: double.infinity,
              color: AppTheme.error.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strip,
                    style: const TextStyle(fontSize: 12, color: AppTheme.error),
                  ),
                  if (_shownAt != null)
                    Text(
                      'Showing what you saw at ${clockLabel(_shownAt!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.error,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  24 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: _children(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _children() {
    final lost = _lostError;
    if (lost != null) return [ErrorStateView(message: lost)];
    if (!_rangeKnown) return const [_Skeleton()];
    final o = _outlook;
    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(w);
    }

    // The header and the chips come from the last good answer, so they
    // stay while the next choice loads or fails (M3).
    final c = _chrome;
    if (c != null) add(_header(c));
    if (c != null &&
        _isOverview &&
        c.departments.isNotEmpty &&
        c.emptyReason == null) {
      add(_departmentChips(c));
    }
    if (c != null && !_isOverview) {
      final views = c.views.where(teamLeaveViewLabels.containsKey).toList();
      if (views.length > 1) add(_viewChips(views));
    }
    add(
      PillSegments(
        labels: const ['30 days', '60 days', '90 days'],
        value: teamLeaveRanges.indexOf(_days),
        onChanged: (i) => _setDays(teamLeaveRanges[i]),
        semanticsLabel: 'How far ahead',
      ),
    );
    // No privacy banner (1.34.1): it described the company defaults, while
    // the server discloses type and pending per viewer (requester, approvers
    // and Time Off officers always see both, L1/L28), so an officer saw
    // "no type" above typed rows. The rows speak for themselves.
    final fatal = _fatalError;
    if (o == null) {
      add(
        fatal != null
            ? ErrorStateView(message: fatal, onRetry: _retry)
            : const _Skeleton(),
      );
    } else if (o.emptyReason != null) {
      add(_noTeam(o.emptyReason!));
    } else if (o.isEmpty) {
      add(_everyoneIn());
    } else {
      add(
        TeamHeatMap(
          outlook: o,
          selected: _selected,
          onSelect: (d) => _onDayTap(o, d),
        ),
      );
      if (o.truncated) {
        // The server bounded the rows (K2): the counts stay exact, some
        // names are missing from the day card (A-L17).
        out.add(const SizedBox(height: 8));
        out.add(
          const Text(
            teamRowsNotShown,
            key: ValueKey('team-truncated'),
            style: TextStyle(fontSize: 12, color: TeamColors.muted),
          ),
        );
      }
      add(_dayCard(o, _selected ?? defaultTeamDay(o)));
    }
    return out;
  }

  Widget _header(TeamOutlook o) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: TeamColors.leaveTint,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(
          Icons.people_alt_outlined,
          size: 20,
          color: TeamColors.leaveOn,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o.team?.label ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              teamScopeSubLabel(o, departmentId: _departmentId),
              style: const TextStyle(fontSize: 12, color: TeamColors.muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _chipRow(List<Widget> chips) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          chips[i],
        ],
      ],
    ),
  );

  Widget _departmentChips(TeamOutlook o) => _chipRow([
    TeamFilterChip(
      key: const ValueKey('dept-all'),
      label: 'All',
      selected: _departmentId == null,
      onTap: () {
        if (_departmentId != null) _change(() => _departmentId = null);
      },
    ),
    for (final d in o.departments)
      TeamFilterChip(
        key: ValueKey('dept-${d.id}'),
        label: d.name,
        selected: _departmentId == d.id,
        onTap: () {
          if (_departmentId != d.id) _change(() => _departmentId = d.id);
        },
      ),
  ]);

  Widget _viewChips(List<String> views) => _chipRow([
    for (final v in views)
      TeamFilterChip(
        key: ValueKey('view-$v'),
        label: teamLeaveViewLabels[v]!,
        selected: _view == v,
        onTap: () {
          if (_view != v) _change(() => _view = v);
        },
      ),
  ]);

  BoxDecoration get _card => BoxDecoration(
    color: AppTheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(24),
    boxShadow: AppTheme.glassShadow,
  );

  Widget _stateCard({
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String title,
    required String body,
    Widget? action,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    decoration: _card,
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 28, color: iconFg),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant),
        ),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    ),
  );

  Widget _everyoneIn() => _stateCard(
    icon: Icons.event_available_outlined,
    iconBg: TeamColors.accentTint,
    iconFg: TeamColors.accent,
    title: "Everyone's in",
    // The overview context (HR, a company or a department) is not "your
    // team" (A-L9).
    body: _isOverview
        ? 'No one is off in the next $_days days.'
        : 'No one on your team is off in the next $_days days.',
    action: _days == 90
        ? null
        : OutlinedButton(
            onPressed: () => _setDays(90),
            child: const Text('Look 90 days ahead'),
          ),
  );

  Widget _noTeam(String reason) => _stateCard(
    icon: Icons.person_outline,
    iconBg: AppTheme.surfaceContainer,
    iconFg: AppTheme.onSurfaceVariant,
    title: 'No team to show yet',
    body: teamEmptyReasonText(reason),
  );

  /// The selected day under the calendar: the day the outlook opens on
  /// (today, else the busiest day), then the last day tapped. Kept next to
  /// the sheet because on a 30-day range it is visible without a tap and
  /// answers "who is off today" at a glance.
  Widget _dayCard(TeamOutlook o, DateTime day) => Container(
    key: const ValueKey('team-day-card'),
    decoration: _card,
    padding: const EdgeInsets.only(bottom: 6),
    child: TeamDayDetail(outlook: o, day: day),
  );

  /// A tap on a calendar day: it becomes the selected day and its detail
  /// opens in the day sheet, where it is in view whatever the scroll.
  void _onDayTap(TeamOutlook o, DateTime day) {
    setState(() => _selected = day);
    unawaited(showTeamDaySheet(context, o, day));
  }
}

/// The loading placeholder of the mockup: a summary bar, a title bar and
/// four person rows.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  Widget _bar(double widthFactor, double height) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: TeamColors.skeleton,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );

  BoxDecoration get _card => BoxDecoration(
    color: AppTheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(24),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('team-skeleton'),
      container: true,
      label: 'Loading team leave',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_bar(0.45, 12), const SizedBox(height: 12), _bar(1, 26)],
              ),
            ),
            const SizedBox(height: 18),
            _bar(0.35, 12),
            for (var i = 0; i < 4; i++) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: _card,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: TeamColors.skeleton,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _bar(0.55, 11),
                          const SizedBox(height: 8),
                          _bar(0.75, 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
