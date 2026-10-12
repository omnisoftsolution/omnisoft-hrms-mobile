import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/models/push_prefs.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/push_native.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An ACME session (no network). [token] null = signed out.
Future<SessionService> signedInSession({String? token = 'tok-1'}) async {
  FlutterSecureStorage.setMockInitialValues({'access_token': ?token});
  SharedPreferences.setMockInitialValues({
    'saas_url': 'https://saas.test',
    'company_code': 'ACME',
    'client_url': 'https://acme.test',
    'client_db': 'acme',
  });
  final s = SessionService();
  await s.load();
  return s;
}

/// Lets fire-and-forget futures (listener-started registrations) finish.
Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeMessaging implements PushMessaging {
  String? token = 'fcm-1';
  int deleteCalls = 0;
  int requests = 0;
  int getTokenCalls = 0;

  /// The next getToken waits for it (used once, then cleared).
  Completer<void>? tokenGate;

  /// The next deleteToken waits for it before the new token exists (used
  /// once, then cleared).
  Completer<void>? deleteGate;

  /// Thrown by the next getToken calls, in order (iOS before APNs answered).
  final List<Object> tokenErrors = [];
  AuthorizationStatus status = AuthorizationStatus.authorized;
  AuthorizationStatus afterRequest = AuthorizationStatus.authorized;

  /// The next authorizationStatus / requestPermission waits for it (each
  /// used once, then cleared).
  Completer<void>? statusGate;
  Completer<void>? requestGate;
  RemoteMessage? initial;
  final refresh = StreamController<String>.broadcast(sync: true);
  final messages = StreamController<RemoteMessage>.broadcast(sync: true);
  final opened = StreamController<RemoteMessage>.broadcast(sync: true);

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    final gate = tokenGate;
    tokenGate = null;
    if (gate != null) await gate.future;
    if (tokenErrors.isNotEmpty) throw tokenErrors.removeAt(0);
    return token;
  }

  @override
  Future<void> deleteToken() async {
    deleteCalls++;
    final n = deleteCalls;
    final gate = deleteGate;
    deleteGate = null;
    if (gate != null) await gate.future;
    token = 'fcm-new-$n';
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<RemoteMessage> get onMessage => messages.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => opened.stream;

  /// When set, getInitialMessage answers with it (instead of [initial]).
  Completer<RemoteMessage?>? initialGate;

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    final gate = initialGate;
    if (gate != null) return gate.future;
    return initial;
  }

  @override
  Future<AuthorizationStatus> authorizationStatus() async {
    final gate = statusGate;
    statusGate = null;
    if (gate != null) await gate.future;
    return status;
  }

  @override
  Future<AuthorizationStatus> requestPermission() async {
    requests++;
    final gate = requestGate;
    requestGate = null;
    if (gate != null) await gate.future;
    status = afterRequest;
    return status;
  }
}

/// What the fake tenant was asked, and how it answers.
class PushApiLog {
  final List<String> calls = [];

  /// Each push/register that reached the server, in the order it landed
  /// (`register <access token> <fcm token>`): the server keeps the last.
  final List<String> landed = [];
  Object? registerError;
  Object? unregisterError;

  /// The next push/register waits for it after it was sent (used once).
  Completer<void>? registerGate;

  /// Set to a never-completing completer to make unregister hang.
  Completer<void>? unregisterGate;
  PushPrefs prefs = const PushPrefs(
    pushAvailable: true,
    remindersAvailable: true,
    muted: <String>{},
  );
  Object? prefsError;
  Object? prefsSetError;

  /// The next prefs/get and prefs/set wait for these (each used once).
  Completer<void>? prefsGetGate;
  Completer<void>? prefsSetGate;

  /// The access token each prefs/set was sent with, in order.
  final List<String?> prefsSetTokens = [];
  final Map<int, NotificationRecord> notices = {};
  Object? noticeError;

  /// The next notifications/get waits for it after it was sent (used once).
  Completer<void>? noticeGate;
}

class FakePushApi extends OmniMobileApi {
  FakePushApi(
    this.log, {
    required super.baseUrl,
    required super.db,
    required super.token,
  });

  final PushApiLog log;

  @override
  Future<void> pushRegister(String fcmToken, String platform) async {
    log.calls.add('register $baseUrl $token $fcmToken $platform');
    final gate = log.registerGate;
    log.registerGate = null;
    if (gate != null) await gate.future;
    final e = log.registerError;
    if (e != null) throw e;
    log.landed.add('register $token $fcmToken');
  }

  @override
  Future<void> pushUnregister() async {
    log.calls.add('unregister $baseUrl $token');
    final gate = log.unregisterGate;
    if (gate != null) await gate.future;
    final e = log.unregisterError;
    if (e != null) throw e;
  }

  @override
  Future<PushPrefs> pushPrefsGet() async {
    log.calls.add('prefs/get');
    final gate = log.prefsGetGate;
    log.prefsGetGate = null;
    if (gate != null) await gate.future;
    final e = log.prefsError;
    if (e != null) throw e;
    return log.prefs;
  }

  @override
  Future<PushPrefs> pushPrefsSet(List<String> muted) async {
    log.calls.add('prefs/set ${muted.join(',')}');
    log.prefsSetTokens.add(token);
    final gate = log.prefsSetGate;
    log.prefsSetGate = null;
    if (gate != null) await gate.future;
    final e = log.prefsSetError;
    if (e != null) throw e;
    log.prefs = log.prefs.copyWith(muted: muted.toSet());
    return log.prefs;
  }

  @override
  Future<NotificationRecord> notificationGet(int id) async {
    log.calls.add('notifications/get $id $baseUrl $token');
    final gate = log.noticeGate;
    log.noticeGate = null;
    if (gate != null) await gate.future;
    final e = log.noticeError;
    if (e != null) throw e;
    final n = log.notices[id];
    if (n == null) throw ApiException('not_found');
    return n;
  }
}

class FakeNative extends PushNative {
  FakeNative() : super(platform: TargetPlatform.iOS);

  final List<String> calls = [];

  @override
  Future<void> createChannels() async {
    calls.add('channels');
  }

  @override
  Future<void> removeDelivered(List<String> ids) async {
    calls.add('remove ${ids.join(',')}');
  }

  /// The next cancelTag waits for it (used once, then cleared).
  Completer<void>? cancelGate;

  @override
  Future<void> cancelTag(String tag) async {
    calls.add('cancel $tag');
    final gate = cancelGate;
    cancelGate = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> clearDelivered() async {
    calls.add('clear');
  }

  @override
  Future<void> setBadge(int n) async {
    calls.add('badge $n');
  }
}

/// Builds the API from the snapshot PushService hands it (never the live
/// session), so `log.calls` shows which tenant and token each call used.
/// APNs retries wait zero in tests.
PushService pushService({
  required FakeMessaging? messaging,
  required PushApiLog log,
  FakeNative? pushNative,
  NotificationService? notifications,
  String platform = 'android',
  int androidSdk = 34,
  Future<void> Function()? openSettings,
  List<Duration> apnsRetryDelays = const [
    Duration.zero,
    Duration.zero,
    Duration.zero,
  ],
  Duration callTimeout = const Duration(seconds: 5),
  Duration signOutCap = const Duration(seconds: 2),
  Duration teardownWaitCap = const Duration(seconds: 30),
  Duration initialMessageTimeout = const Duration(seconds: 3),
}) => PushService(
  messaging: messaging,
  pushNative: pushNative ?? FakeNative(),
  apiBuilder: (t) =>
      FakePushApi(log, baseUrl: t.baseUrl, db: t.db, token: t.token),
  notifications: notifications,
  platform: platform,
  androidSdk: () async => androidSdk,
  openSettings: openSettings ?? () async {},
  apnsRetryDelays: apnsRetryDelays,
  callTimeout: callTimeout,
  signOutCap: signOutCap,
  teardownWaitCap: teardownWaitCap,
  initialMessageTimeout: initialMessageTimeout,
);

/// The bell as PushService sees it: counts re-polls, fixed unread count.
class FakeNotifications extends NotificationService {
  int refreshes = 0;
  int unread = 0;

  /// The next refreshNow waits for it (used once, then cleared).
  Completer<void>? refreshGate;

  @override
  int get unreadCount => unread;

  /// What refreshNow answers: false = no count fetched (not started yet,
  /// offline).
  bool fetched = true;

  /// Full list reloads (a foreground remove asks for one, F3).
  int listRefreshes = 0;

  @override
  Future<void> refreshList() async => listRefreshes++;

  @override
  Future<bool> refreshNow() async {
    refreshes++;
    final gate = refreshGate;
    refreshGate = null;
    if (gate != null) await gate.future;
    return fetched;
  }
}
