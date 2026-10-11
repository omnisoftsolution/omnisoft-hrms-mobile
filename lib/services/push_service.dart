import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/push_prefs.dart';
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
    String? platform,
    List<Duration> apnsRetryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ],
    Duration callTimeout = const Duration(seconds: 5),
  }) : _messaging = messaging,
       _native = pushNative ?? PushNative.instance,
       _apiBuilder = apiBuilder ?? _targetApi,
       _platform =
           platform ??
           (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
       _apnsRetryDelays = apnsRetryDelays,
       _callTimeout = callTimeout;

  final PushMessaging? _messaging;
  final PushNative _native;
  final PushApiBuilder _apiBuilder;
  final String _platform;

  /// iOS: getToken throws `apns-token-not-set` until APNs answered, which
  /// right after launch it usually has not. One retry after each delay
  /// (≈ 10 s in all); after that onTokenRefresh and resume take over.
  final List<Duration> _apnsRetryDelays;
  final Duration _callTimeout;
  final List<StreamSubscription<Object?>> _subs = [];

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
  PushPrefs? _prefs;

  /// Firebase came up. False: every push feature is off on this run.
  bool get enabled => _messaging != null;

  /// The last `push/prefs/get` answer for the signed-in user; null = not
  /// known (signed out, older connector, offline).
  PushPrefs? get prefs => _prefs;

  /// The tenant sends pushes: gates Profile → Notifications (§6.6).
  bool get available => _prefs?.pushAvailable == true;

  /// Android channels and the FCM token stream. Call once at start-up,
  /// after [onSignedIn].
  Future<void> init() async {
    final m = _messaging;
    if (m == null) return;
    await _native.createChannels();
    _subs.add(m.onTokenRefresh.listen((_) => _onFcmTokenRefresh()));
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
    if (!s.isLoggedIn) return;
    if (s.token != _current?.token) _adopt(s);
    await register();
  }

  /// Only a new access token (sign-in, `auth/refresh`) means "register".
  /// Sign-outs arrive through [onSessionCleared]. A routing change under
  /// the same token is Settings → Company saving the new company just
  /// before it signs out: registering then would send the old tenant's
  /// token to the new tenant (spec §6.3), so it is ignored.
  void _onSessionChanged() {
    final s = _session;
    if (s == null || !s.isLoggedIn) return;
    if (s.token == _current?.token) return;
    _adopt(s);
    unawaited(register());
  }

  void _adopt(SessionService s) {
    _generation++;
    _current = PushTarget.of(s);
    _registered = null;
  }

  void _onFcmTokenRefresh() {
    if (_current == null) return;
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
    } catch (_) {
      // Offline, an older connector (no route), a legacy sign-in
      // (`session_required`), a 409, or iOS still without its APNs token
      // after the retries: onTokenRefresh or the next resume tries again.
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
    final p = await _apiBuilder(target).pushPrefsGet();
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
  /// old tenant's token dies even if the server never heard. Never throws;
  /// each network step gives up after the call timeout.
  Future<void> onSessionCleared() async {
    final target = _current;
    final onWire = _onWire;
    _generation++;
    _current = null;
    _registered = null;
    if (_prefs != null) {
      _prefs = null;
      notifyListeners();
    }
    // A push/register already sent lands first, so the unregister below
    // cannot overtake it on the server.
    if (onWire != null) {
      try {
        await onWire.timeout(_callTimeout);
      } catch (_) {
        // Failed or slow: deleteToken below still kills the token.
      }
    }
    if (target != null) {
      try {
        await _apiBuilder(target).pushUnregister().timeout(_callTimeout);
      } catch (_) {
        // Revoked already, offline or slow: deleteToken below still kills
        // the token on FCM's side.
      }
    }
    await _native.clearDelivered();
    await _native.setBadge(0);
    final m = _messaging;
    if (m != null) {
      try {
        await m.deleteToken().timeout(_callTimeout);
      } catch (_) {
        // Offline: FCM keeps the old token until the next deleteToken.
      }
    }
  }

  /// App back in the foreground: retry a registration that failed.
  Future<void> onResumed() async {
    final s = _session;
    if (s == null || !s.isLoggedIn) return;
    if (_current != null && _registered == null && _inFlight == null) {
      unawaited(register());
    }
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
