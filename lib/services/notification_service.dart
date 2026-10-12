import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/notification_record.dart';
import 'omni_mobile_api.dart';
import 'session_service.dart';

/// Per-user in-app notification cache + 60s poller.
///
/// Lifecycle: HomeShell calls `start(session)` once it knows we're
/// signed in, and `stop()` from its dispose. Logout flows that drop
/// the session also call `stop()`.
class NotificationService extends ChangeNotifier {
  NotificationService({OmniMobileApi Function(SessionService session)? apiFor})
      : _apiFor = apiFor;

  static const Duration _pollInterval = Duration(seconds: 60);

  /// Tests hand in a fake server; the app builds the real API.
  final OmniMobileApi Function(SessionService session)? _apiFor;

  Timer? _timer;
  SessionService? _session;
  bool _busy = false;
  String? _lastError;

  int _unreadCount = 0;
  List<NotificationRecord> _items = const [];
  // Tracks the most-recent notification id we've already surfaced via
  // a transient snackbar so we don't re-fire on subsequent polls.
  int _maxAnnouncedId = 0;
  // Every arrival polling discovered that HomeShell has not consumed
  // yet, newest first. The newest becomes the snackbar; all of them are
  // checked for leave decisions / approval requests.
  List<NotificationRecord> _freshArrivals = const [];
  int _pollsSinceStart = 0;
  // Notices a push tap opened (F1): never handed over as an arrival.
  final Set<int> _suppressed = {};
  // The arrival handed over last: its snackbar may be on screen.
  int? _lastHandedOver;
  // A poll saw the unread count drop (F3), not consumed by HomeShell yet.
  bool _unreadDrop = false;

  int get unreadCount => _unreadCount;
  List<NotificationRecord> get items => _items;
  bool get loading => _busy;
  String? get lastError => _lastError;

  /// Returns and clears every notification that arrived since the host
  /// last asked, newest first (empty when none). Called by HomeShell in
  /// its listener: the first one is shown as a snackbar, and all of them
  /// count for side effects — a leave decision that arrived together
  /// with a newer expense update must still reload the leave list.
  List<NotificationRecord> consumeFreshArrivals() {
    final f = _freshArrivals;
    _freshArrivals = const [];
    if (f.isNotEmpty) _lastHandedOver = f.first.id;
    return f;
  }

  /// A push tap opened notice [id] (F1): it is never handed over as an
  /// arrival (the user is looking at it), and is dropped from the queue
  /// when a poll already queued it. True, once, when it was the arrival
  /// handed over last — its snackbar may be on screen for the host to hide.
  bool suppressArrival(int id) {
    _suppressed.add(id);
    if (_freshArrivals.any((n) => n.id == id)) {
      _freshArrivals = _freshArrivals.where((n) => n.id != id).toList();
    }
    if (_lastHandedOver != id) return false;
    _lastHandedOver = null;
    return true;
  }

  /// True, once, after a poll saw the unread count drop: something was
  /// read or closed elsewhere (another phone, or a request someone else
  /// decided — F3). The list was reloaded already; HomeShell re-pulls the
  /// approvals count.
  bool consumeUnreadDrop() {
    final d = _unreadDrop;
    _unreadDrop = false;
    return d;
  }

  /// Queue the new arrivals in [items] (the server's list, newest
  /// first) after the unread count went up by [increase]: the unread
  /// items newer than anything already queued, at most [increase] of
  /// them (older unread items were there before this poll). Notifies
  /// when something was queued.
  @visibleForTesting
  void queueArrivals(List<NotificationRecord> items, {required int increase}) {
    final fresh = <NotificationRecord>[];
    var taken = 0;
    for (final n in items) {
      if (taken >= increase) break;
      if (n.read || n.id <= _maxAnnouncedId) continue;
      // A suppressed notice still counts as one of the new ones (F1), so
      // an older unread item does not take its place.
      taken++;
      if (!_suppressed.contains(n.id)) fresh.add(n);
    }
    if (fresh.isEmpty) return;
    _maxAnnouncedId = fresh.first.id;
    _freshArrivals = [...fresh, ..._freshArrivals];
    notifyListeners();
  }

  OmniMobileApi? _api() {
    final s = _session;
    if (s == null || !s.isLoggedIn) return null;
    final apiFor = _apiFor;
    if (apiFor != null) return apiFor(s);
    return OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token);
  }

  /// Start polling. Safe to call multiple times — re-uses the timer.
  void start(SessionService session) {
    _session = session;
    _timer ??= Timer.periodic(_pollInterval, (_) => _refreshUnread());
    // Fire-and-forget initial pull so the badge is right immediately.
    _refreshUnread();
  }

  /// Stop polling and drop cached state. Call on logout.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _items = const [];
    _unreadCount = 0;
    _lastError = null;
    _maxAnnouncedId = 0;
    _freshArrivals = const [];
    _pollsSinceStart = 0;
    _suppressed.clear();
    _lastHandedOver = null;
    _unreadDrop = false;
    // Intentionally NOT calling notifyListeners() — this method is
    // only invoked from HomeShell.dispose(), at which point Flutter
    // is mid-finalizeTree (locked) and any rebuild request crashes a
    // debug assert. The Consumer<SessionService> in main.dart is
    // already swapping HomeShell for LoginScreen on the same frame,
    // so a notification here adds nothing useful anyway.
  }

  /// Re-poll now: a push arrived while the app is open (spec 2026-10-11
  /// §6.4). Same path as the 60 s timer, so the arrival snackbar follows.
  /// Does nothing before [start]. True only when a fresh unread count was
  /// fetched (false before [start], signed out or offline): the iOS badge
  /// is set from [unreadCount] only then.
  Future<bool> refreshNow() => _refreshUnread();

  /// Lightweight unread-count probe used by the periodic timer.
  /// When the unread count *increases* after we've already polled at
  /// least once, fetches the full list and queues the freshest unread
  /// item for the HomeShell snackbar listener. True when the count came.
  Future<bool> _refreshUnread() async {
    final api = _api();
    if (api == null) return false;
    try {
      final c = await api.getUnreadNotificationCount();
      _pollsSinceStart++;
      final increased = c > _unreadCount && _pollsSinceStart > 1;
      final dropped = c < _unreadCount && _pollsSinceStart > 1;
      final increase = c - _unreadCount;
      if (c != _unreadCount) {
        _unreadCount = c;
        notifyListeners();
      }
      if (increased) {
        // Need the actual record(s) for the snackbar title — just-saw
        // a count bump is not enough.
        await refreshList();
        // The server orders DESC: the first unread items are the new ones.
        queueArrivals(_items, increase: increase);
      } else if (dropped) {
        // Read or closed elsewhere (F3): an open bell list shows the new
        // read state, and HomeShell re-pulls the approvals count.
        await refreshList();
        _unreadDrop = true;
        notifyListeners();
      }
      return true;
    } catch (_) {
      // ignore — keep old count
      return false;
    }
  }

  /// Pull the full list (called when the user opens the notifications
  /// screen so they see fresh data + we recompute the unread count
  /// from the items themselves).
  Future<void> refreshList() async {
    final api = _api();
    if (api == null) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final list = await api.getNotifications();
      _items = list;
      _unreadCount = list.where((n) => !n.read).length;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Mark one notification read (optimistic — updates local state
  /// immediately, then fires the API call in the background).
  Future<void> markRead(int id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx >= 0 && !_items[idx].read) {
      final updated = NotificationRecord(
        id: _items[idx].id,
        kind: _items[idx].kind,
        title: _items[idx].title,
        body: _items[idx].body,
        payload: _items[idx].payload,
        read: true,
        createDate: _items[idx].createDate,
        answered: _items[idx].answered,
      );
      _items = [..._items.sublist(0, idx), updated, ..._items.sublist(idx + 1)];
      _unreadCount = _items.where((n) => !n.read).length;
      notifyListeners();
    }
    final api = _api();
    if (api == null) return;
    try {
      await api.markNotificationsRead(ids: [id]);
    } catch (_) {
      // Server-side mark failed — next poll will reconcile.
    }
  }

  /// Mark every unread notification for this user as read.
  Future<void> markAllRead() async {
    final api = _api();
    if (api == null) return;
    try {
      await api.markNotificationsRead(); // no ids = all
    } catch (_) {
      // ignore — still update local state below
    }
    _items = _items
        .map(
          (n) => n.read
              ? n
              : NotificationRecord(
                  id: n.id,
                  kind: n.kind,
                  title: n.title,
                  body: n.body,
                  payload: n.payload,
                  read: true,
                  createDate: n.createDate,
                  answered: n.answered,
                ),
        )
        .toList();
    _unreadCount = 0;
    notifyListeners();
  }
}
