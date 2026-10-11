import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/models/push_prefs.dart';
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

  /// Thrown by the next getToken calls, in order (iOS before APNs answered).
  final List<Object> tokenErrors = [];
  AuthorizationStatus status = AuthorizationStatus.authorized;
  AuthorizationStatus afterRequest = AuthorizationStatus.authorized;
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
    token = 'fcm-new-$deleteCalls';
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<RemoteMessage> get onMessage => messages.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;

  @override
  Future<AuthorizationStatus> authorizationStatus() async => status;

  @override
  Future<AuthorizationStatus> requestPermission() async {
    requests++;
    status = afterRequest;
    return status;
  }
}

/// What the fake tenant was asked, and how it answers.
class PushApiLog {
  final List<String> calls = [];
  Object? registerError;
  Object? unregisterError;

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
    final e = log.registerError;
    if (e != null) throw e;
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
    log.calls.add('notifications/get $id');
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

  @override
  Future<void> cancelTag(String tag) async {
    calls.add('cancel $tag');
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
  String platform = 'android',
  List<Duration> apnsRetryDelays = const [
    Duration.zero,
    Duration.zero,
    Duration.zero,
  ],
  Duration callTimeout = const Duration(seconds: 5),
}) => PushService(
  messaging: messaging,
  pushNative: pushNative ?? FakeNative(),
  apiBuilder: (t) =>
      FakePushApi(log, baseUrl: t.baseUrl, db: t.db, token: t.token),
  platform: platform,
  apnsRetryDelays: apnsRetryDelays,
  callTimeout: callTimeout,
);
