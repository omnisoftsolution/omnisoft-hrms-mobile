import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_service.dart';

/// The last good team leave outlook / Team overview answer per employee,
/// for offline display (A-L3, TLMD-07). SharedPreferences, one key per
/// db + employee + kind + context + view + department + span:
/// `team_v1|<db>|<employeeId>|<kind>|<context>|<view>|<departmentId or ->|<span>`.
///
/// Each value is `{saved_at, signature, body}`. An entry saved under
/// another signature ([SessionService.teamCacheSignature]: the server's
/// `team_scope_sig`, else grant / setting / department / company) is not
/// shown. Cleared:
/// - all `team_v1|` keys on every sign-out (SessionService calls
///   [clearAll] from its session wipe);
/// - this employee's keys on an access-lost answer ([clearEmployee]).
///
/// Binding (A-L15, A-L21): a caller takes the key and a [TeamCacheBinding]
/// ([bind]) **before** it sends the request, checks it before the answer
/// is shown, and passes it to [write]. Every clear bumps [generation] and
/// every sign-out / sign-in moves [SessionService.requestEpoch], so an
/// answer that was on the wire across a clear (an access-lost answer
/// elsewhere), a sign-out (even one whose wipe was skipped), a new sign-in
/// or a signature change is neither shown nor stored. Writes and clears
/// run one at a time on their own queue (the SessionService `_persisting`
/// pattern). A clear takes effect for reads before anyone hears of it and
/// sends its removal to storage at once, ahead of that queue (A-L23).
///
/// At most [maxPerEmployee] entries per employee; the oldest go first.
/// The person sheet is never cached.
///
/// No method takes the SessionService persistence lock, so [clearAll] may
/// run inside it.
class TeamCache {
  TeamCache._();

  static const prefix = 'team_v1|';
  static const maxPerEmployee = 24;
  static const kindOutlook = 'outlook';
  static const kindOverview = 'overview';

  /// Save-time clock; tests replace it.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// The generation; its listeners hear every clear at once (A-L22).
  static final ValueNotifier<int> _generation = ValueNotifier<int>(0);

  /// Bumped by [clearEmployee] and [clearAll]. Part of every
  /// [TeamCacheBinding].
  static int get generation => _generation.value;

  /// Notifies, synchronously, on every [clearEmployee] / [clearAll], once
  /// [read] already misses the cleared entries (A-L23).
  static Listenable get changes => _generation;

  /// Everything that can make a shown team answer stale (A-L22): every
  /// [SessionService] notify (a /me, a sign-in, the end of a sign-out) and
  /// every cache clear. A screen keeps the returned object and removes its
  /// listener with it in `dispose`.
  static Listenable watch(SessionService s) => Listenable.merge([s, changes]);

  /// What a team request is asked under (A-L21): take it with the key,
  /// before the request; check it before showing the answer
  /// ([TeamCacheBinding.isCurrent]) and hand it to [write].
  static TeamCacheBinding bind(SessionService s) => TeamCacheBinding(
    employeeId: s.employeeId,
    signature: s.teamCacheSignature,
    generation: _generation.value,
    requestEpoch: s.requestEpoch,
  );

  /// `team_v1|<db>|<employeeId>|`.
  static String employeePrefix(SessionService s) =>
      '$prefix${s.clientDb}|${s.employeeId}|';

  /// The A-L3 key. [span] is the outlook's days ('30') or the overview's
  /// day ('today').
  static String key({
    required SessionService session,
    required String kind,
    String context = '-',
    String view = '-',
    int? departmentId,
    required String span,
  }) =>
      '${employeePrefix(session)}$kind|$context|$view|'
      '${departmentId ?? '-'}|$span';

  /// The outlook's key. The LEAVE row and the outlook screen share the
  /// 30-day team key (A-L1). `view` only counts in the team context.
  static String outlookKey(
    SessionService s, {
    required int days,
    String context = 'team',
    String view = 'team',
    int? departmentId,
  }) =>
      key(
        session: s,
        kind: kindOutlook,
        context: context,
        view: context == 'team' ? view : '-',
        departmentId: departmentId,
        span: '$days',
      );

  /// The Team overview's key ([day] 'today' | 'yesterday').
  static String overviewKey(
    SessionService s, {
    String day = 'today',
    int? departmentId,
  }) =>
      key(
        session: s,
        kind: kindOverview,
        departmentId: departmentId,
        span: day,
      );

  /// The stored body and its save time (local), or null when the key is
  /// absent, corrupt, saved under another signature, not this employee's,
  /// or under a clear that has not finished yet (A-L23).
  static Future<(Map<String, dynamic> body, DateTime savedAt)?> read(
    SessionService s,
    String key,
  ) async {
    if (s.employeeId <= 0 || !key.startsWith(employeePrefix(s))) return null;
    final prefs = await SharedPreferences.getInstance();
    // Checked after the await, in the same synchronous step as the lookup:
    // a clear that started while this read waited hides the entry too.
    if (_barred(key)) return null;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (value is! Map) return null;
    if (value['signature'] != s.teamCacheSignature) return null;
    final body = value['body'];
    final at = value['saved_at'];
    final savedAt = at is String ? DateTime.tryParse(at) : null;
    if (body is! Map || savedAt == null) return null;
    return (Map<String, dynamic>.from(body), savedAt.toLocal());
  }

  /// Stores [body] under [key] for the signed-in employee, then keeps the
  /// [maxPerEmployee] newest entries. [binding] is what the caller took
  /// before its request (A-L15, A-L21). Dropped when no employee is signed
  /// in, a sign-out is running, [key] is not this employee's, or [binding]
  /// is no longer current (another employee, another signature, a clear
  /// since, a sign-out or a new sign-in since): a fetch that lands after a
  /// sign-out, an access-lost clear or a narrowed grant never writes the
  /// old team back. Checked again inside the queue, right before storing.
  static Future<void> write(
    SessionService s,
    String key,
    Map<String, dynamic> body, {
    required TeamCacheBinding binding,
  }) {
    bool current() => _mayStore(s, key) && binding.isCurrent(s);
    if (!current()) return Future<void>.value();
    final String value;
    try {
      value = jsonEncode({
        'saved_at': clock().toUtc().toIso8601String(),
        'signature': binding.signature,
        'body': body,
      });
    } on JsonUnsupportedObjectError {
      return Future<void>.value();
    }
    return _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      await prefs.setString(key, value);
      await _trim(prefs, employeePrefix(s));
    });
  }

  /// Removes every entry of the signed-in employee (an access-lost
  /// answer: not_allowed / names_hidden / feature_unavailable). Reads miss
  /// them and the generation moves at once, so a write already queued or
  /// on the wire is dropped and a reload a listener starts finds nothing
  /// (A-L23).
  static Future<void> clearEmployee(SessionService s) =>
      _clear(employeePrefix(s));

  /// Removes every `team_v1|` entry (sign-out, logout), the same way as
  /// [clearEmployee].
  static Future<void> clearAll() => _clear(prefix);

  // The screens' calls (final review M4): the cache is best effort, so a
  // prefs failure (a full disk, a broken prefs file) never fails a refresh,
  // never leaves a screen on its skeleton and is never an unhandled error.
  // Each one starts its call synchronously, so a clear's barrier and
  // generation still move at once.

  /// [read], with a prefs failure read as an empty cache (null).
  static Future<(Map<String, dynamic> body, DateTime savedAt)?> readQuietly(
    SessionService s,
    String key,
  ) async {
    try {
      return await read(s, key);
    } catch (e) {
      debugPrint('TeamCache: read failed: $e');
      return null;
    }
  }

  /// [write]; a prefs failure only means no offline copy.
  static Future<void> writeQuietly(
    SessionService s,
    String key,
    Map<String, dynamic> body, {
    required TeamCacheBinding binding,
  }) async {
    try {
      await write(s, key, body, binding: binding);
    } catch (e) {
      debugPrint('TeamCache: write failed: $e');
    }
  }

  /// [clearEmployee]; the generation moves at once even when the removal
  /// from storage then fails.
  static Future<void> clearEmployeeQuietly(SessionService s) async {
    try {
      await clearEmployee(s);
    } catch (e) {
      debugPrint('TeamCache: clear failed: $e');
    }
  }

  /// Clears that have started and not finished, by key prefix (A-L23):
  /// while a prefix is here, [read] returns nothing under it.
  static final Map<String, int> _barriers = <String, int>{};

  static bool _barred(String key) => _barriers.keys.any(key.startsWith);

  /// The one clear (A-L23), in this order:
  /// 1. the read barrier for [scope], synchronously: from here on [read]
  ///    returns nothing under it;
  /// 2. the generation, which notifies [changes] synchronously: a listener
  ///    that reloads and falls back to the cache already reads nothing;
  /// 3. the removal goes to storage now, not behind the writes already
  ///    queued: SharedPreferences takes each key out of its in-memory copy
  ///    at once and sends the removal to the platform in order, so an app
  ///    killed before the queue reaches this clear finds no entry after a
  ///    restart (the barrier itself lives in memory only);
  /// 4. on the queue, after the writes queued before it: a second sweep
  ///    (its errors are this call's), then the barrier goes. Writes queued
  ///    later run after that, under the new generation.
  static Future<void> _clear(String scope) {
    _barriers[scope] = (_barriers[scope] ?? 0) + 1;
    _generation.value++;
    final sent = SharedPreferences.getInstance().then<void>(
      (prefs) => Future.wait([
        for (final k in prefs.getKeys().toList())
          if (k.startsWith(scope)) prefs.remove(k),
      ]),
      // A failure here is retried by the sweep below, which reports it.
      onError: (Object _) {},
    );
    return _serial(() async {
      try {
        await sent;
        await _removeWhere((k) => k.startsWith(scope));
      } finally {
        final left = _barriers[scope]! - 1;
        if (left == 0) {
          _barriers.remove(scope);
        } else {
          _barriers[scope] = left;
        }
      }
    });
  }

  static bool _mayStore(SessionService s, String key) =>
      s.employeeId > 0 && !s.isClearing && key.startsWith(employeePrefix(s));

  /// One queue for every write and clear (the SessionService
  /// `_persisting` pattern): an idle queue runs [body] at once and keeps
  /// no completed future, so nothing waits on another zone's microtask
  /// queue (widget tests run in a fake-async zone). Never call a
  /// SessionService locked method from [body].
  static Future<void> _serial(Future<void> Function() body) {
    final previous = _tail;
    final run = previous == null ? body() : previous.then((_) => body());
    final tail = run.then<void>((_) {}, onError: (Object _) {});
    _tail = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tail, tail)) _tail = null;
      }),
    );
    return run;
  }

  /// The last write or clear queued; null when the queue is idle.
  static Future<void>? _tail;

  static Future<void> _removeWhere(bool Function(String key) test) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where(test).toList()) {
      await prefs.remove(k);
    }
  }

  /// Keeps the [maxPerEmployee] newest entries under [employeePrefix];
  /// unreadable entries count as the oldest.
  static Future<void> _trim(
    SharedPreferences prefs,
    String employeePrefix,
  ) async {
    final keys =
        prefs.getKeys().where((k) => k.startsWith(employeePrefix)).toList();
    if (keys.length <= maxPerEmployee) return;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    DateTime savedAt(String k) {
      try {
        final v = jsonDecode(prefs.getString(k) ?? '');
        final at = v is Map ? v['saved_at'] : null;
        return (at is String ? DateTime.tryParse(at) : null) ?? epoch;
      } on FormatException {
        return epoch;
      }
    }

    keys.sort((a, b) => savedAt(a).compareTo(savedAt(b)));
    for (final k in keys.take(keys.length - maxPerEmployee)) {
      await prefs.remove(k);
    }
  }
}

/// What a team answer was asked under (A-L15, A-L21), taken with
/// [TeamCache.bind] before the request. The screens of Tasks 5, 6 and 8
/// check [isCurrent] before every `setState` an answer (or a cached read)
/// drives, and [TeamCache.write] checks it before storing.
@immutable
class TeamCacheBinding {
  const TeamCacheBinding({
    required this.employeeId,
    required this.signature,
    required this.generation,
    required this.requestEpoch,
  });

  /// [SessionService.employeeId] at the time.
  final int employeeId;

  /// [SessionService.teamCacheSignature] at the time.
  final String signature;

  /// [TeamCache.generation] at the time.
  final int generation;

  /// [SessionService.requestEpoch] at the time.
  final int requestEpoch;

  /// True while nothing that decides what the viewer may see has moved:
  /// the same employee and scope signature, no cache clear, no sign-out
  /// or new sign-in since (even one whose wipe was skipped), and no
  /// sign-out running now.
  bool isCurrent(SessionService s) =>
      s.employeeId == employeeId &&
      s.teamCacheSignature == signature &&
      TeamCache.generation == generation &&
      s.requestEpoch == requestEpoch &&
      !s.isClearing;
}
