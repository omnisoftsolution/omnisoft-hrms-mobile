import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/push_groups.dart';
import '../models/push_prefs.dart';
import 'notification_service.dart';
import 'omni_mobile_api.dart';
import 'push_native.dart';
import 'session_service.dart';

/// Firebase Cloud Messaging behind a seam, so [PushService] is testable
/// without Firebase (spec 2026-10-11 §6).
abstract class PushMessaging {
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  Future<AuthorizationStatus> authorizationStatus();
  Future<AuthorizationStatus> requestPermission();
}

/// The real FCM. Only built after `Firebase.initializeApp()` succeeded.
class FirebasePushMessaging implements PushMessaging {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  Future<String?> getToken() => _m.getToken();

  @override
  Future<void> deleteToken() => _m.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _m.getInitialMessage();

  @override
  Future<AuthorizationStatus> authorizationStatus() async =>
      (await _m.getNotificationSettings()).authorizationStatus;

  @override
  Future<AuthorizationStatus> requestPermission() async =>
      (await _m.requestPermission()).authorizationStatus;
}

/// What the phone allows (spec §6.2). [notAsked]: the system prompt can
/// still be shown (never asked; on Android 13+ also after one refusal).
/// [denied]: only the phone's settings can turn notifications on (A5).
enum PushPermission { notAsked, granted, denied }

/// The tenant session a push call belongs to, copied from SessionService
/// when its access token arrives (spec §6.3). SessionService changes under
/// a running call — Settings → Company saves the new company before it
/// signs out — so push/register, push/unregister, the prefs routes and
/// notifications/get all use this copy, never the live fields.
@immutable
class PushTarget {
  const PushTarget({
    required this.baseUrl,
    required this.db,
    required this.token,
  });

  PushTarget.of(SessionService s)
    : this(baseUrl: s.clientUrl, db: s.clientDb, token: s.token);

  final String baseUrl;
  final String db;
  final String token;
}

typedef PushApiBuilder = OmniMobileApi Function(PushTarget target);

OmniMobileApi _targetApi(PushTarget t) =>
    OmniMobileApi(baseUrl: t.baseUrl, db: t.db, token: t.token);

/// Push notifications on this phone (spec 2026-10-11 §6): the FCM token's
/// life on the tenant session (§6.3) and the user's mutes (§6.6).
///
/// main() builds one, sets `SessionService.onSessionClearing` to
/// [onSessionCleared], calls [onSignedIn] once and then [init].
class PushService extends ChangeNotifier {
  PushService({
    PushMessaging? messaging,
    PushNative? pushNative,
    PushApiBuilder? apiBuilder,
    NotificationService? notifications,
    String? platform,
    List<Duration> apnsRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ],
    Duration callTimeout = const Duration(seconds: 5),
    Duration signOutCap = const Duration(seconds: 2),
  }) : _messaging = messaging,
       _native = pushNative ?? PushNative.instance,
       _apiBuilder = apiBuilder ?? _targetApi,
       _notifications = notifications,
       _platform =
           platform ??
           (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
       _apnsRetryDelays = apnsRetryDelays,
       _callTimeout = callTimeout,
       _signOutCap = signOutCap;

  final PushMessaging? _messaging;
  final PushNative _native;
  final PushApiBuilder _apiBuilder;
  final String _platform;

  /// iOS: getToken throws `apns-token-not-set` until APNs answered, which
  /// right after launch it usually has not. One retry after each delay
  /// (≈ 10 s in all); after that onTokenRefresh and resume take over.
  final List<Duration> _apnsRetryDelays;
  final Duration _callTimeout;

  /// How long a sign-out waits for the push side (spec §6.3); the rest of
  /// the teardown finishes in the background ([_teardown]).
  final Duration _signOutCap;
  final List<StreamSubscription<Object?>> _subs = [];

  /// The bell; a notice arriving in the foreground re-polls it.
  final NotificationService? _notifications;

  SessionService? _session;

  /// The signed-in session as of its last access token; null signed out.
  PushTarget? _current;

  /// [_current] once its push/register succeeded (null otherwise).
  PushTarget? _registered;

  /// Bumped on every new access token and every sign-out. A call started
  /// in an older generation stores and sends nothing more.
  int _generation = 0;

  /// The registration running now (deduplicates resume retries).
  Future<void>? _inFlight;

  /// A push/register request already sent; sign-out lets it land first.
  Future<void>? _onWire;

  /// The access token of the session being (or last) signed out. The
  /// session keeps reporting it as signed in until the sign-out hook
  /// returns; a notify in that window (refreshSubscription's saveCompany,
  /// refreshMe) must not adopt it again.
  String? _retiredToken;

  /// The current generation's registration failed for good: a legacy
  /// sign-in (`session_required`) or a connector without the route (404).
  /// Resume and token refreshes leave it; the next access token retries.
  bool _settled = false;

  /// The last sign-out's unregister + deleteToken, still running in the
  /// background after the sign-out returned.
  Future<void>? _teardown;
  PushPrefs? _prefs;
  List<PushArrival> _arrivals = const [];

  /// Firebase came up. False: every push feature is off on this run.
  bool get enabled => _messaging != null;

  /// The last `push/prefs/get` answer for the signed-in user; null = not
  /// known (signed out, older connector, offline).
  PushPrefs? get prefs => _prefs;

  /// The tenant sends pushes: gates Profile → Notifications (§6.6).
  bool get available => _prefs?.pushAvailable == true;

  /// Android channels, the FCM token stream and foreground messages. Call
  /// once at start-up, after [onSignedIn].
  Future<void> init() async {
    final m = _messaging;
    if (m == null) return;
    await _native.createChannels();
    _subs.add(
      m.onTokenRefresh.listen(
        (_) => _onFcmTokenRefresh(),
        onError: (Object e) => debugPrint('push: token refresh failed ($e)'),
      ),
    );
    _subs.add(
      m.onMessage.listen(
        (msg) => unawaited(
          handleForeground(
            msg.data,
            title: msg.notification?.title,
            body: msg.notification?.body,
          ),
        ),
      ),
    );
  }

  /// Attaches the app's session (synchronously, before the first await)
  /// and registers when it is signed in (app start). Later sign-ins and
  /// every new access token are seen through the session listener.
  Future<void> onSignedIn(SessionService s) async {
    if (!identical(_session, s)) {
      _session?.removeListener(_onSessionChanged);
      _session = s;
      s.addListener(_onSessionChanged);
    }
    if (!s.isLoggedIn || s.token == _retiredToken) return;
    if (s.token != _current?.token) _adopt(s);
    await register();
  }

  /// Only a new access token (sign-in, `auth/refresh`) means "register".
  /// Sign-outs arrive through [onSessionCleared]. A routing change under
  /// the same token is Settings → Company saving the new company just
  /// before it signs out: registering then would send the old tenant's
  /// token to the new tenant (spec §6.3), so it is ignored. So is the token
  /// being signed out ([_retiredToken]).
  void _onSessionChanged() {
    final s = _session;
    if (s == null || !s.isLoggedIn) return;
    if (s.token == _current?.token || s.token == _retiredToken) return;
    _adopt(s);
    unawaited(register());
  }

  void _adopt(SessionService s) {
    _generation++;
    _current = PushTarget.of(s);
    _registered = null;
    _retiredToken = null;
    _settled = false;
  }

  void _onFcmTokenRefresh() {
    if (_current == null || _settled) return;
    _registered = null;
    unawaited(register());
  }

  /// `push/register` with the current FCM token for the session snapshot
  /// (spec §6.3), then reads the user's prefs. Never throws. Overtaken by a
  /// sign-out or a new access token, it writes nothing.
  Future<void> register() async {
    final m = _messaging;
    final target = _current;
    if (m == null || target == null) return;
    final gen = _generation;
    final run = _registerOnce(m, target, gen);
    _inFlight = run;
    await run;
    if (identical(_inFlight, run)) _inFlight = null;
    if (gen != _generation) return;
    await refreshPrefs();
  }

  Future<void> _registerOnce(
    PushMessaging m,
    PushTarget target,
    int gen,
  ) async {
    try {
      // A quick sign-in right after a sign-out: the old teardown's
      // deleteToken must not kill the token this registration fetches.
      final teardown = _teardown;
      if (teardown != null) {
        try {
          await teardown.timeout(_callTimeout);
        } catch (_) {
          // Slow: go on; a later token rotation arrives via onTokenRefresh.
        }
        if (gen != _generation) return;
      }
      final token = await _fcmToken(m, gen);
      // Checked again after every await: the session may be gone.
      if (token == null || token.isEmpty || gen != _generation) return;
      final call = _apiBuilder(target).pushRegister(token, _platform);
      _onWire = call;
      try {
        await call;
      } finally {
        if (identical(_onWire, call)) _onWire = null;
      }
      if (gen == _generation) _registered = target;
    } catch (e) {
      // Offline, a 409, or iOS still without its APNs token after the
      // retries: onTokenRefresh or the next resume tries again. A legacy
      // sign-in or an older connector: only the next access token does.
      if (gen != _generation) return;
      if (_isPermanent(e)) _settled = true;
      _forwardInvalidSession(e, gen);
    }
  }

  /// `session_required` (a legacy sign-in) or an HTML 404 (a connector
  /// without the push routes): retrying under the same session is useless.
  static bool _isPermanent(Object e) =>
      e is ApiException &&
      (e.errorCode == 'session_required' ||
          (e.errorCode == 'server_error' && e.data?['http_status'] == 404));

  /// The push routes are quiet; an invalid_session answer signs the user
  /// out only when it is about the current session (not an older
  /// generation's snapshot).
  void _forwardInvalidSession(Object e, int gen) {
    if (gen != _generation || e is! ApiException) return;
    if (e.errorCode == 'invalid_session' || e.errorCode == 'invalid_token') {
      OmniMobileApi.onInvalidSession?.call();
    }
  }

  /// [PushMessaging.getToken], retried after each of [_apnsRetryDelays]
  /// while iOS answers `apns-token-not-set` (FlutterFire's APNs check).
  Future<String?> _fcmToken(PushMessaging m, int gen) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await m.getToken();
      } on FirebaseException catch (e) {
        final retry =
            e.code == 'apns-token-not-set' &&
            attempt < _apnsRetryDelays.length &&
            gen == _generation;
        if (!retry) rethrow;
        await Future<void>.delayed(_apnsRetryDelays[attempt]);
      }
    }
  }

  /// `push/prefs/get`; throws on any failure (Profile → Notifications
  /// shows it through friendlyError). An answer that arrives after a
  /// sign-out or a new access token is not kept: it asks again for the
  /// current session, or throws when there is none.
  Future<PushPrefs> loadPrefs() async {
    final target = _current;
    if (target == null) throw ApiException('invalid_session');
    final gen = _generation;
    final PushPrefs p;
    try {
      p = await _apiBuilder(target).pushPrefsGet();
    } catch (e) {
      _forwardInvalidSession(e, gen);
      rethrow;
    }
    if (gen != _generation) return loadPrefs();
    _prefs = p;
    notifyListeners();
    return p;
  }

  /// [loadPrefs] that keeps the last answer on failure.
  Future<PushPrefs?> refreshPrefs() async {
    try {
      return await loadPrefs();
    } catch (_) {
      return _prefs;
    }
  }

  /// `SessionService.onSessionClearing`: every local sign-out path (spec
  /// §6.3). Unregisters (best effort) at the tenant and with the token the
  /// registration used — the snapshot, not the live session, which
  /// Settings → Company has already pointed at the new company — clears
  /// delivered notifications and the badge, deletes the FCM token so the
  /// old tenant's token dies even if the server never heard. Never throws.
  /// The sign-out waits at most [_signOutCap]; the rest finishes in the
  /// background (every call in it uses the snapshot), each network step
  /// bounded by the call timeout.
  Future<void> onSessionCleared() async {
    final target = _current;
    final onWire = _onWire;
    _retiredToken = target?.token ?? _session?.token;
    _generation++;
    final gen = _generation;
    _current = null;
    _registered = null;
    _settled = false;
    _arrivals = const [];
    if (_prefs != null) {
      _prefs = null;
      notifyListeners();
    }
    final teardown = _tearDown(target, onWire, gen);
    _teardown = teardown;
    unawaited(
      teardown.whenComplete(() {
        if (identical(_teardown, teardown)) _teardown = null;
      }),
    );
    try {
      await teardown.timeout(_signOutCap);
    } catch (_) {
      // Slow network: the sign-out goes on; the teardown keeps running.
    }
  }

  /// Unregister and deleteToken side by side, plus the local clean-up.
  Future<void> _tearDown(
    PushTarget? target,
    Future<void>? onWire,
    int gen,
  ) async {
    await Future.wait([
      _native.clearDelivered().then((_) => _native.setBadge(0)),
      _unregister(target, onWire),
      _deleteFcmToken(gen),
    ]);
  }

  Future<void> _unregister(PushTarget? target, Future<void>? onWire) async {
    // A push/register already sent lands first, so the unregister cannot
    // overtake it on the server.
    if (onWire != null) {
      try {
        await onWire.timeout(_callTimeout);
      } catch (_) {
        // Failed or slow: deleteToken still kills the token.
      }
    }
    if (target == null) return;
    try {
      await _apiBuilder(target).pushUnregister().timeout(_callTimeout);
    } catch (_) {
      // Revoked already, offline or slow: deleteToken still kills the
      // token on FCM's side.
    }
  }

  Future<void> _deleteFcmToken(int gen) async {
    final m = _messaging;
    // A new session already took over: its token must live.
    if (m == null || gen != _generation) return;
    try {
      await m.deleteToken().timeout(_callTimeout);
    } catch (_) {
      // Offline: FCM keeps the old token until the next deleteToken.
    }
  }

  /// App back in the foreground: retry a registration that failed.
  Future<void> onResumed() async {
    final s = _session;
    if (s == null || !s.isLoggedIn) return;
    if (_current != null &&
        _registered == null &&
        !_settled &&
        _inFlight == null) {
      unawaited(register());
    }
  }

  /// A push that arrived while the app is open (spec §6.4). Only this
  /// tenant's pushes count. No system banner: a notice re-polls the bell
  /// (its arrival snackbar follows), a reminder is queued for HomeShell's
  /// snackbar, a `remove` takes the notification off and applies the badge.
  Future<void> handleForeground(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) async {
    final s = _session;
    if (s == null || !s.isLoggedIn || !isForThisTenant(data, s.companyCode)) {
      return;
    }
    if (data['action'] == 'remove') {
      await applyRemove(data, _native);
      return;
    }
    final kind = data['kind']?.toString() ?? '';
    if (isReminderKind(kind)) {
      _arrivals = [
        PushArrival(kind: kind, title: title ?? '', body: body ?? ''),
        ..._arrivals,
      ];
      notifyListeners();
      return;
    }
    await _notifications?.refreshNow();
  }

  /// Reminders that arrived since HomeShell last asked, newest first.
  List<PushArrival> consumeArrivals() {
    final a = _arrivals;
    _arrivals = const [];
    return a;
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }
}

/// A push-only notice (a check-in / check-out reminder) that arrived while
/// the app was open; HomeShell shows it as a snackbar (spec §6.4).
class PushArrival {
  const PushArrival({
    required this.kind,
    required this.title,
    required this.body,
  });

  final String kind;
  final String title;
  final String body;
}

/// Every push carries `company_code` (set by hrmsmanager from the sending
/// tenant). One for another tenant is ignored (spec §6.4).
bool isForThisTenant(Map<String, dynamic> data, String companyCode) {
  final code = data['company_code'];
  if (code is! String) return false;
  final mine = companyCode.trim().toUpperCase();
  return mine.isNotEmpty && code.trim().toUpperCase() == mine;
}

/// A `remove` push (spec §6.4): take the notification about its `omni_key`
/// off the phone (iOS by identifier = apns-collapse-id, Android by tag) and
/// apply its badge (iOS). Best effort (§10).
Future<void> applyRemove(
  Map<String, dynamic> data,
  PushNative pushNative,
) async {
  final key = data['omni_key']?.toString() ?? '';
  if (key.isNotEmpty) {
    await pushNative.removeDelivered([key]);
    await pushNative.cancelTag(key);
  }
  final badge = int.tryParse(data['badge']?.toString() ?? '');
  if (badge != null) await pushNative.setBadge(badge);
}

/// The signed-in company code as SessionService stored it — the background
/// isolate has no SessionService. Android runs the background handler in
/// its own isolate, whose SharedPreferences cache outlives a message while
/// the main isolate switches tenant: reload before reading. [open] is a
/// test seam.
Future<String> storedCompanyCode({
  Future<SharedPreferences> Function()? open,
}) async {
  final prefs = await (open ?? SharedPreferences.getInstance)();
  await prefs.reload();
  return prefs.getString(SessionService.companyCodePrefsKey) ?? '';
}

/// A data message while the app is in the background or closed. Only
/// `remove` needs work (the system shows `show` pushes itself), and only
/// for this phone's tenant — checked before anything is cancelled.
@visibleForTesting
Future<void> handleBackgroundData(
  Map<String, dynamic> data, {
  PushNative? pushNative,
  Future<String> Function()? companyCode,
}) async {
  if (data['action'] != 'remove') return;
  final code = await (companyCode ?? storedCompanyCode)();
  if (!isForThisTenant(data, code)) return;
  await applyRemove(data, pushNative ?? PushNative.instance);
}

/// FCM's background entry point (registered in main). Android runs it in
/// a background isolate, iOS on the main isolate.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // FlutterFire's dispatcher only initialises the binding. Register the
  // Dart side of the plugins (shared_preferences, flutter_local_notifications'
  // Android class used by cancel-by-tag) in this isolate first; without it
  // a remove would silently do nothing. Idempotent; harmless on iOS.
  DartPluginRegistrant.ensureInitialized();
  await handleBackgroundData(message.data);
}
