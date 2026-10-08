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
  static const Duration _pollInterval = Duration(seconds: 60);

  Timer? _timer;
  SessionService? _session;
  bool _busy = false;
  String? _lastError;

  int _unreadCount = 0;
  List<NotificationRecord> _items = const [];
  // Tracks the most-recent notification id we've already surfaced via
  // a transient snackbar so we don't re-fire on subsequent polls.
  int _maxAnnouncedId = 0;
  // Set when polling discovers an arrival the user hasn't seen as a
  // snackbar yet. HomeShell consumes this in its listener.
  NotificationRecord? _freshArrival;
  int _pollsSinceStart = 0;

  int get unreadCount => _unreadCount;
  List<NotificationRecord> get items => _items;
  bool get loading => _busy;
  String? get lastError => _lastError;

  /// Returns and clears any pending fresh-arrival notification. Called
  /// by the host (HomeShell) inside its listener so each arrival is
  /// shown as a snackbar at most once.
  NotificationRecord? consumeFreshArrival() {
    final f = _freshArrival;
    _freshArrival = null;
    return f;
  }

  OmniMobileApi? _api() {
    final s = _session;
    if (s == null || !s.isLoggedIn) return null;
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
    _freshArrival = null;
    _pollsSinceStart = 0;
    // Intentionally NOT calling notifyListeners() — this method is
    // only invoked from HomeShell.dispose(), at which point Flutter
    // is mid-finalizeTree (locked) and any rebuild request crashes a
    // debug assert. The Consumer<SessionService> in main.dart is
    // already swapping HomeShell for LoginScreen on the same frame,
    // so a notification here adds nothing useful anyway.
  }

  /// Lightweight unread-count probe used by the periodic timer.
  /// When the unread count *increases* after we've already polled at
  /// least once, fetches the full list and queues the freshest unread
  /// item for the HomeShell snackbar listener.
  Future<void> _refreshUnread() async {
    final api = _api();
    if (api == null) return;
    try {
      final c = await api.getUnreadNotificationCount();
      _pollsSinceStart++;
      final increased = c > _unreadCount && _pollsSinceStart > 1;
      if (c != _unreadCount) {
        _unreadCount = c;
        notifyListeners();
      }
      if (increased) {
        // Need the actual record(s) for the snackbar title — just-saw
        // a count bump is not enough.
        await refreshList();
        // First unread in the list is the newest (server orders DESC).
        NotificationRecord? newest;
        for (final n in _items) {
          if (!n.read) {
            newest = n;
            break;
          }
        }
        if (newest != null && newest.id > _maxAnnouncedId) {
          _maxAnnouncedId = newest.id;
          _freshArrival = newest;
          notifyListeners();
        }
      }
    } catch (_) {
      // ignore — keep old count
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
