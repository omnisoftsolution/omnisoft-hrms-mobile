import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/theme.dart';
import '../../../models/team_outlook.dart';
import '../../../models/team_overview.dart';
import '../../../services/omni_mobile_api.dart';
import '../../../services/session_service.dart';
import '../../../services/team_cache.dart';
import '../../team/team_colors.dart' show TeamColors;
import '../../team/team_format.dart' show leaveWhenLabel;
import '../../team/team_widgets.dart' show TeamAvatar, TeamYouChip;
import '../my_day/my_day_display.dart' show minutesLabel;

String _join(Iterable<String> parts) =>
    parts.where((p) => p.isNotEmpty).join(' · ');

/// Where a punch came from (connector L3): "Phone", "Kiosk · Front door",
/// or nothing for any other source.
String punchSourceLabel(String source, String kioskName) => switch (source) {
  'mobile' => 'Phone',
  'kiosk' => kioskName.isEmpty ? 'Kiosk' : 'Kiosk · $kioskName',
  _ => '',
};

/// The sheet's Today box.
String personStatusLabel(String bucket, int lateMinutes) => switch (bucket) {
  'on_time' => 'Checked in · on time',
  'late' =>
    lateMinutes > 0
        ? 'Checked in · ${minutesLabel(lateMinutes)} late'
        : 'Checked in · late',
  'not_in_yet' => 'Not in yet',
  'no_check_in' => 'No check-in',
  'on_leave' => 'On leave',
  'off_today' => 'Off today',
  _ => '—',
};

/// The sheet's Shift box: "08:30 – 17:30" ([OverviewShift.label]), or
/// "No shift".
String personShiftLabel(OverviewShift? shift) => shift?.label ?? 'No shift';

String _punchKind(String kind) => switch (kind) {
  'check_in' => 'Check in',
  'check_out' => 'Check out',
  'break_start' => 'Break',
  'break_end' => 'Back from break',
  _ => '',
};

/// One "Punches today" line after the time: "Check in · Phone · Office".
String punchLine(OverviewPunch p) => _join([
  _punchKind(p.kind),
  punchSourceLabel(p.source, p.kioskName ?? ''),
  p.location ?? '',
]);

/// The Leave box after "Leave · ": each leave of the week (today through
/// Sunday) with its type when the server sends one (D4) and "pending" for
/// a request not yet approved (D3).
String personLeaveText(List<TeamLeaveRow> rows) {
  if (rows.isEmpty) return 'none in the next 7 days';
  return rows
      .map(
        (r) => _join([
          r.type ?? '',
          leaveWhenLabel(r),
          if (r.state == 'pending') 'pending',
        ]),
      )
      .join('; ');
}

/// One person's day, read-only (Task 7; contract `home/overview/person`).
/// Root navigator: the sheet covers the bottom bar. Never cached (A-L3).
///
/// [apiFor] builds the client for each attempt (the first load, Retry, a
/// reload after the team binding moved) from the session of the moment
/// (A-L22, TLP3-F01): a retry after a new sign-in sends the new token.
/// Callers pass a builder that does not need their own `context`: the sheet
/// can outlive the screen that opened it.
Future<void> showOverviewPersonSheet(
  BuildContext context, {
  required int employeeId,
  required OmniMobileApi Function(SessionService session) apiFor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PersonSheet(employeeId: employeeId, apiFor: apiFor),
  );
}

class _PersonSheet extends StatefulWidget {
  const _PersonSheet({required this.employeeId, required this.apiFor});

  final int employeeId;
  final OmniMobileApi Function(SessionService session) apiFor;

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  OverviewPerson? _person;
  String? _error;
  bool _retryable = false;

  /// The binding [_person] was asked under (A-L22).
  TeamCacheBinding? _shownBinding;

  /// A request on the wire checks its own binding when it lands.
  bool _asking = false;

  /// What was shown went stale while nothing could be asked (signed out,
  /// a sign-out running): the next notify that allows it asks again.
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

  static bool _gone(Object e) =>
      e is ApiException && e.errorCode == 'not_found';

  /// A session notify or a cache clear (A-L22): a person shown under a
  /// binding that has moved goes before the next frame, and the sheet asks
  /// again, unless a request is on the wire or nothing may be asked yet.
  void _onBindingChanged() {
    if (!mounted) return;
    final session = context.read<SessionService>();
    final shown = _shownBinding;
    if (_person != null && (shown == null || !shown.isCurrent(session))) {
      setState(() {
        _person = null;
        _shownBinding = null;
      });
      if (!_asking) _reloadPending = true;
    }
    if (!_reloadPending || _asking) return;
    if (session.employeeId <= 0 || session.isClearing) return;
    _reloadPending = false;
    unawaited(_load());
  }

  Future<void> _load() async {
    final session = context.read<SessionService>();
    _reloadPending = false;
    // The binding and the client of this attempt, in one synchronous step
    // (A-L22): the token sent is the one the binding describes.
    final binding = TeamCache.bind(session);
    final api = widget.apiFor(session);
    try {
      final OverviewPerson person;
      _asking = true;
      try {
        person = await api.fetchOverviewPerson(widget.employeeId);
      } finally {
        _asking = false;
      }
      if (!mounted) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      setState(() {
        _person = person;
        _shownBinding = binding;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!binding.isCurrent(session)) return _rebind(session);
      final shown = _shownBinding;
      if (_person != null && (shown == null || !shown.isCurrent(session))) {
        _person = null; // never behind Retry either (A-L22)
        _shownBinding = null;
      }
      final lost = isAccessLost(e);
      if (lost) {
        // A-L3: the grant changed under us; drop what this user cached and
        // let /me say what is left.
        unawaited(TeamCache.clearEmployee(session));
        unawaited(session.refreshMe());
      }
      setState(() {
        _retryable = !lost && !_gone(e);
        // not_found reads "This person is no longer in your view." (A-L9).
        _error = friendlyError(e, context: ErrorContext.team);
      });
    }
  }

  /// The answer in hand was asked under a binding that has moved (A-L21):
  /// not shown. The sheet asks again with a client built now, or, signed
  /// out / during a sign-out, at the notify that allows it.
  Future<void> _rebind(SessionService session) {
    setState(() {
      _person = null;
      _shownBinding = null;
      _error = null;
    });
    if (session.employeeId <= 0 || session.isClearing) {
      _reloadPending = true;
      return Future<void>.value();
    }
    return _load();
  }

  void _retry() {
    setState(() {
      _error = null;
      _retryable = false;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + media.viewPadding.bottom),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _error;
    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error,
            key: const ValueKey('person-error'),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_retryable)
                TextButton(onPressed: _retry, child: const Text('Retry')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      );
    }
    final p = _person;
    if (p == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final sub = _join([p.department, p.calendar]);
    final leaveWeek = p.leaveWeek;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TeamAvatar(id: p.id, initials: p.initials, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (p.you) ...[
                        const SizedBox(width: 6),
                        const TeamYouChip(),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: text.bodySmall?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Fact(
                label: 'Today',
                value: personStatusLabel(p.bucket, p.lateMinutes),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Fact(label: 'Shift', value: personShiftLabel(p.shift)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Punches today',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (p.punches.isEmpty)
          Text(
            'None yet.',
            style: text.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant),
          )
        else
          for (final punch in p.punches)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    punch.at,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      punchLine(punch),
                      style: text.bodyMedium?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        if (leaveWeek != null) ...[
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('person-leave'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: TeamColors.leaveTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: TeamColors.leaveOn),
                children: [
                  const TextSpan(
                    text: 'Leave',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' · ${personLeaveText(leaveWeek)}'),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Read-only. Fixes and approvals stay in Odoo and in Leave approvals.',
          style: text.bodySmall?.copyWith(color: AppTheme.outline),
        ),
      ],
    );
  }
}

/// A small labelled box (Today / Shift).
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: AppTheme.outline,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
