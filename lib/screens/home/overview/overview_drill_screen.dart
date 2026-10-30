import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/omni_colors.dart';
import '../../../models/team_overview.dart';
import '../../../services/omni_mobile_api.dart';
import '../../../services/session_service.dart';
import '../../../services/team_cache.dart';
import '../../../widgets/error_state_view.dart';
import '../../../widgets/omni_app_bar.dart';
import '../../team/team_colors.dart' show TeamColors;
import '../../team/team_format.dart' show dayTitle;
import '../../team/team_widgets.dart' show TeamAvatar, TeamYouChip;
import '../my_day/my_day_display.dart' show minutesLabel;
import 'overview_copy.dart';
import 'person_sheet.dart' show punchSourceLabel, showOverviewPersonSheet;

/// The drill-down's title: "Today · Novaworks", "Today · Marketing".
String drillTitle(String scopeLabel) => 'Today · $scopeLabel';

/// What one drill-down row says. An empty string is not shown.
class DrillRowText {
  const DrillRowText({
    required this.line,
    this.time = '',
    this.chip = '',
    this.note = '',
  });

  /// Under the name: the department and the bucket's detail.
  final String line;

  /// Right column, large: first check-in, shift start, back time or "—".
  final String time;

  /// Right column, under the time: "28 min late", "No check-in".
  final String chip;

  /// A quiet extra line: "On leave today · came in anyway".
  final String note;
}

String _join(Iterable<String> parts) =>
    parts.where((p) => p.isNotEmpty).join(' · ');

/// The row texts for each bucket (Task 7, mockup `drillRows`). [today]
/// defaults to now; it decides "until Fri 23 Oct" versus "today".
DrillRowText drillRowText(OverviewRow r, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final date = DateTime(now.year, now.month, now.day);
  switch (r.bucket) {
    case 'on_time':
    case 'late':
      return DrillRowText(
        line: _join([
          r.department,
          punchSourceLabel(r.source, r.kioskName ?? ''),
          r.location ?? '',
        ]),
        time: r.firstIn ?? '',
        chip: r.bucket == 'late' && r.lateMinutes > 0
            ? '${minutesLabel(r.lateMinutes)} late'
            : '',
        note: _noteOf(r),
      );
    case 'not_in_yet':
      final back = r.leave?.backAt ?? '';
      return DrillRowText(
        line: _join([r.department, _notInYet(r)]),
        time: back.isNotEmpty ? back : (r.shift?.start ?? ''),
        note: _noteOf(r),
      );
    case 'no_check_in':
      final shift = r.shift;
      final since = r.minutesSinceStart;
      return DrillRowText(
        line: _join([
          r.department,
          if (shift != null) 'Shift ${shift.label}',
          if (since != null) '${minutesLabel(since)} since start',
        ]),
        time: '—',
        chip: 'No check-in',
        note: _noteOf(r),
      );
    case 'on_leave':
      final leave = r.leave;
      final type = leave?.type ?? '';
      final until = leave?.until;
      return DrillRowText(
        line: _join([
          r.department,
          type.isEmpty ? 'On leave' : type,
          until != null && until.isAfter(date)
              ? 'until ${dayTitle(until)}'
              : 'today',
        ]),
      );
    case 'off_today':
      return DrillRowText(line: _join([r.department, 'No shift today']));
    default:
      return DrillRowText(line: r.department);
  }
}

String _notInYet(OverviewRow r) {
  final shift = r.shift;
  final leave = r.leave;
  final backAt = leave?.backAt ?? '';
  if (leave != null && backAt.isNotEmpty) {
    final what = leave.part == 'morning'
        ? 'leave this morning'
        : 'part-day leave';
    return 'Back $backAt · $what';
  }
  if (r.flexible) return 'Flexible hours';
  final range = shift == null ? '' : 'Shift ${shift.label}';
  final startsIn = r.startsInMin;
  if (startsIn != null) {
    return _join([range, 'starts in ${minutesLabel(startsIn)}']);
  }
  final since = r.minutesSinceStart;
  if (since != null) {
    return _join([
      if (shift != null) 'Shift ${shift.start}',
      'no check-in for ${minutesLabel(since)}',
    ]);
  }
  if (r.laterToday) {
    return range.isEmpty ? 'Later today' : '$range · later today';
  }
  return range.isEmpty ? 'Not in yet' : range;
}

String _noteOf(OverviewRow r) {
  switch (r.note) {
    case 'came_in_on_leave':
      return 'On leave today · came in anyway';
    case 'part_day_leave':
      final leave = r.leave;
      if (leave == null) return 'Part-day leave today';
      final type = leave.type ?? '';
      final part = switch (leave.part) {
        'morning' => ' (morning)',
        'afternoon' => ' (afternoon)',
        'hours' => ' (hours)',
        _ => '',
      };
      return '${type.isEmpty ? 'Leave' : type}$part';
    default:
      return '';
  }
}

/// Today's people in one bucket (contract `home/overview/list`), pushed on
/// the Home tab's navigator from a count tile. Read-only; a row opens the
/// person sheet.
class OverviewDrillScreen extends StatefulWidget {
  const OverviewDrillScreen({
    super.key,
    required this.bucket,
    required this.counts,
    this.departmentId,
    required this.scopeLabel,
    this.apiBuilder,
    this.appBar,
  });

  /// The bucket the tapped tile stands for.
  final String bucket;

  /// The overview's live counts: the chips' numbers until a list answers.
  final OverviewCounts counts;

  /// The overview's department filter (company access), sent with every
  /// page.
  final int? departmentId;

  /// "Novaworks" or the department name, for the title.
  final String scopeLabel;

  /// Test seam: builds the API client from the session.
  @visibleForTesting
  final OmniMobileApi Function(SessionService session)? apiBuilder;

  /// Test seam: replaces [OmniAppBar] (needs the notification service).
  @visibleForTesting
  final PreferredSizeWidget? appBar;

  @override
  State<OverviewDrillScreen> createState() => _OverviewDrillScreenState();
}

class _OverviewDrillScreenState extends State<OverviewDrillScreen> {
  static const _pageSize = 50;

  late String _bucket = widget.bucket;

  /// Chip numbers: the overview's counts, replaced by a list's exact
  /// `total` once that bucket answered.
  late final Map<String, int> _totals = {
    for (final b in overviewBucketOrder) b: overviewCountOf(widget.counts, b),
  };

  final List<OverviewRow> _rows = [];
  int? _nextOffset;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _moreScheduled = false;
  bool _leaving = false;
  String? _error;

  /// Bumped by every first-page load; an answer for an older one is
  /// dropped (the user switched bucket or pulled to refresh meanwhile).
  int _seq = 0;

  /// The binding the rows on screen were asked under (the first page's;
  /// a later page only lands while it is still current) (A-L22).
  TeamCacheBinding? _rowsBinding;

  /// List requests of the current first-page load that are on the wire
  /// (the first page and its "more" pages); each checks its own binding when
  /// it lands. A first-page load that starts resets it: an older request
  /// still pending is stale and never counts (T7 review I2).
  int _asking = 0;

  /// A first-page load (the first open, a bucket switch, a pull to refresh,
  /// a reload) is on the wire. Load-more waits for it (T7 review M1).
  bool _firstPageAsking = false;

  /// The rows went stale while nothing could be asked (signed out, a
  /// sign-out running): the next notify that allows it asks again.
  bool _reloadPending = false;

  /// Every session notify and every cache clear (A-L22).
  late final Listenable _watch;

  @override
  void initState() {
    super.initState();
    _watch = TeamCache.watch(context.read<SessionService>())
      ..addListener(_onBindingChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _watch.removeListener(_onBindingChanged);
    super.dispose();
  }

  OmniMobileApi _api(SessionService session) =>
      widget.apiBuilder?.call(session) ??
      OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );

  /// A session notify or a cache clear (A-L22): rows shown under a binding
  /// that has moved go before the next frame, and the first page is asked
  /// again, unless a request is on the wire or nothing may be asked yet.
  void _onBindingChanged() {
    if (!mounted || _leaving) return;
    final session = context.read<SessionService>();
    final shown = _rowsBinding;
    // What is shown: rows, or an answer that said nobody (an empty bucket)
    // (A-L22, T7 review I1). The chip totals are not part of the binding:
    // they stay.
    final showsAnswer =
        _rows.isNotEmpty || (!_loading && _error == null && shown != null);
    if (showsAnswer && (shown == null || !shown.isCurrent(session))) {
      setState(_dropRows);
      if (_asking == 0) _reloadPending = true;
    }
    if (!_reloadPending || _asking > 0) return;
    if (session.employeeId <= 0 || session.isClearing) return;
    _reloadPending = false;
    unawaited(_load());
  }

  /// Forgets the rows (they belong to an old binding); the list shows the
  /// spinner until the first page answers again.
  void _dropRows() {
    _rows.clear();
    _rowsBinding = null;
    _nextOffset = null;
    _loading = true;
    _loadingMore = false;
    _moreFailed = false;
    _error = null;
  }

  /// The first page (offset 0), or with [more] the next one. Callers set
  /// the loading flags first; this sets state only after the answer.
  Future<void> _load({bool more = false}) async {
    final seq = more ? _seq : ++_seq;
    final session = context.read<SessionService>();
    if (!more) _reloadPending = false;
    final offset = more ? (_nextOffset ?? 0) : 0;
    if (!more) {
      // Older requests are stale now: they no longer count as asking.
      _asking = 0;
      _firstPageAsking = true;
    }
    // The binding and the client of this attempt, in one synchronous step
    // (A-L22, TLP3-F01): the token sent is the one the binding describes.
    final binding = TeamCache.bind(session);
    final api = _api(session);
    try {
      final OverviewPage page;
      _asking++;
      try {
        page = await api.fetchOverviewList(
          bucket: _bucket,
          departmentId: widget.departmentId,
          offset: offset,
          limit: _pageSize,
        );
      } finally {
        if (seq == _seq) {
          _asking--;
          if (!more) _firstPageAsking = false;
        }
      }
      if (!mounted || seq != _seq) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      setState(() {
        if (!more) {
          _rows.clear();
          _rowsBinding = binding;
          // A new first page: an earlier failed "more" no longer applies,
          // so the footer goes back to asking the next page.
          _moreFailed = false;
        }
        _rows.addAll(page.rows);
        _nextOffset = page.nextOffset;
        _totals[_bucket] = page.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      if (isAccessLost(e)) {
        _leave(e, session);
        return;
      }
      // A failed load never keeps rows whose binding has moved (A-L22).
      final shown = _rowsBinding;
      final stale =
          _rows.isNotEmpty && (shown == null || !shown.isCurrent(session));
      setState(() {
        if (stale) _dropRows();
        _loading = false;
        _loadingMore = false;
        if (more && !stale) {
          _moreFailed = true;
        } else {
          _error = friendlyError(e, context: ErrorContext.team);
        }
      });
    }
  }

  /// The page in hand was asked under a binding that has moved (A-L21):
  /// not shown. The rows on screen go too, and the first page is asked
  /// again with a client built now, or, signed out / during a sign-out, at
  /// the notify that allows it.
  Future<void> _rebind(SessionService session) {
    setState(_dropRows);
    if (session.employeeId <= 0 || session.isClearing) {
      _reloadPending = true;
      return Future<void>.value();
    }
    return _load();
  }

  /// `names_hidden` / `not_allowed` / `feature_unavailable`: the names are
  /// no longer this user's to see. Back to the overview with the reason;
  /// the cache goes and /me says what is left (A-L3).
  void _leave(Object e, SessionService session) {
    if (_leaving) return;
    _leaving = true;
    final messenger = ScaffoldMessenger.of(context);
    final text = friendlyError(e, context: ErrorContext.team);
    unawaited(TeamCache.clearEmployeeQuietly(session));
    unawaited(session.refreshMe());
    unawaited(Navigator.of(context).maybePop());
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _select(String bucket) {
    if (bucket == _bucket || _leaving) return;
    setState(() {
      _bucket = bucket;
      _rows.clear();
      _nextOffset = null;
      _loading = true;
      _loadingMore = false;
      _moreFailed = false;
      _error = null;
    });
    unawaited(_load());
  }

  void _loadMore() {
    // A "more" page asked for the old list must not land after a refreshed
    // first page (T7 review M1): wait for the refresh; its answer rebuilds
    // the footer, which asks again.
    if (_loadingMore || _nextOffset == null || _leaving || _firstPageAsking) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    unawaited(_load(more: true));
  }

  Future<void> _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    return _load();
  }

  /// The sheet builds its own client per attempt (A-L22). The builder
  /// captures the seam, not this State: the sheet can outlive the screen
  /// (an access-lost answer pops it).
  void _openPerson(OverviewRow row) {
    final builder = widget.apiBuilder;
    unawaited(
      showOverviewPersonSheet(
        context,
        employeeId: row.id,
        apiFor: (s) =>
            builder?.call(s) ??
            OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.omni;
    final t = TeamColors.of(context);
    final error = _error;
    return Scaffold(
      appBar: widget.appBar ?? OmniAppBar(title: drillTitle(widget.scopeLabel)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null && _rows.isNotEmpty)
            Container(
              color: c.error.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                error,
                style: text.bodySmall?.copyWith(color: c.error),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: ListView.separated(
              key: const ValueKey('drill-chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: overviewBucketOrder.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final b = overviewBucketOrder[i];
                return _BucketChip(
                  key: ValueKey('drill-chip-$b'),
                  label: overviewBucketLabel(b),
                  count: _totals[b] ?? 0,
                  dot: t.bucket(b).dot,
                  selected: b == _bucket,
                  onTap: () => _select(b),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              overviewBucketHint(_bucket),
              key: const ValueKey('drill-hint'),
              style: text.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
          Expanded(child: _list(context)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final error = _error;
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty && error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorStateView(message: error, onRetry: _retry),
        ),
      );
    }
    final padding = EdgeInsets.fromLTRB(
      16,
      8,
      16,
      16 + MediaQuery.of(context).viewPadding.bottom,
    );
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            Card(
              key: const ValueKey('drill-empty'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nobody here right now.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.omni.textSub,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final footer = _nextOffset != null || _moreFailed;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const ValueKey('drill-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: _rows.length + (footer ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _rows.length) return _footer();
          final row = _rows[i];
          return _DrillRow(
            key: ValueKey('drill-row-${row.id}'),
            row: row,
            first: i == 0,
            last: i == _rows.length - 1 && !footer,
            onTap: () => _openPerson(row),
          );
        },
      ),
    );
  }

  /// The row after the last loaded one: building it means the user reached
  /// the end, so the next page is asked for (once).
  Widget _footer() {
    if (_moreFailed) {
      return Padding(
        key: const ValueKey('drill-more'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: const Text("Couldn't load more. Try again"),
          ),
        ),
      );
    }
    if (!_loadingMore && !_moreScheduled) {
      _moreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _moreScheduled = false;
        if (mounted) _loadMore();
      });
    }
    return const Padding(
      key: ValueKey('drill-more'),
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    super.key,
    required this.label,
    required this.count,
    required this.dot,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color dot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? c.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? Colors.transparent : c.line,
            width: 1.5,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '$label · $count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        // onPrimaryContainer (#004449) has no token.
                        ? (context.isDarkTheme
                              ? c.onAccentTint
                              : const Color(0xFF004449))
                        : c.textSub,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrillRow extends StatelessWidget {
  const _DrillRow({
    super.key,
    required this.row,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final OverviewRow row;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = drillRowText(row);
    final c = context.omni;
    final team = TeamColors.of(context);
    final tone = team.bucket(row.bucket);
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? 24 : 0),
      bottom: Radius.circular(last ? 24 : 0),
    );
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.card,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: first
                ? null
                : Border(
                    top: BorderSide(
                      color: c.line.withValues(alpha: 0.4),
                    ),
                  ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              TeamAvatar(id: row.id, initials: row.initials, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (row.you) ...[
                          const SizedBox(width: 6),
                          const TeamYouChip(),
                        ],
                      ],
                    ),
                    if (t.line.isNotEmpty)
                      Text(
                        t.line,
                        style: text.bodySmall?.copyWith(
                          color: c.textSub,
                        ),
                      ),
                    if (t.note.isNotEmpty)
                      Text(
                        t.note,
                        style: text.bodySmall?.copyWith(
                          color: team.leaveOn,
                        ),
                      ),
                  ],
                ),
              ),
              if (t.time.isNotEmpty || t.chip.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (t.time.isNotEmpty)
                      Text(
                        t.time,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (t.chip.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tone.tint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t.chip,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tone.onTint,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
