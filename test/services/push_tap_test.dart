import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/services/session_service.dart';

import 'push_fakes.dart';

Map<String, dynamic> tapData({String company = 'ACME'}) => <String, dynamic>{
  'notification_id': '41',
  'kind': 'leave_approval_requested',
  'push_group': 'approvals',
  'omni_key': 'approve:41',
  'company_code': company,
  'leave_id': '148',
};

Future<void> newAccessToken(SessionService s, String token) => s.saveSession(
  accessToken: token,
  userId: 1,
  userLogin: 'siti',
  userName: 'Siti',
  employeeId: 1,
  employeeName: 'Siti',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMessaging fcm;
  late PushApiLog log;

  setUp(() {
    fcm = FakeMessaging();
    log = PushApiLog();
  });

  tearDown(() => OmniMobileApi.onInvalidSession = null);

  Future<PushService> started({String? token = 'tok-1'}) async {
    final s = await signedInSession(token: token);
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await push.init();
    return push;
  }

  test('a tap on our own push waits for HomeShell, once', () async {
    final push = await started();
    push.handleTap(tapData());
    expect(push.consumePendingTap()?['notification_id'], '41');
    expect(push.consumePendingTap(), isNull);
  });

  test('a tap on another company\'s push only opens the app', () async {
    final push = await started();
    push.handleTap(tapData(company: 'PRINTART'));
    expect(push.consumePendingTap(), isNull);
  });

  test('a tap while signed out is dropped', () async {
    final push = await started(token: null);
    push.handleTap(tapData());
    expect(push.consumePendingTap(), isNull);
  });

  test('taps come from onMessageOpenedApp and from the launch message', () async {
    fcm.initial = RemoteMessage(data: tapData());
    final push = await started();
    // The launch message is looked up in the background (init() does not
    // wait for it).
    await flush();
    expect(push.consumePendingTap()?['kind'], 'leave_approval_requested');
    fcm.opened.add(RemoteMessage(data: {...tapData(), 'notification_id': '42'}));
    expect(push.consumePendingTap()?['notification_id'], '42');
  });

  // Review fix round 1 (Opus M1 / Codex 7): the launch message is looked
  // up in the background; start-up never waits for it.
  test('a launch-message lookup that never answers does not hold init()',
      () async {
    fcm.initialGate = Completer<RemoteMessage?>();
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      initialMessageTimeout: const Duration(milliseconds: 50),
    );
    await push.onSignedIn(s);
    await push.init().timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(push.consumePendingTap(), isNull);
  });

  test('a launch message that answers after init() returned still opens, '
      'once', () async {
    final launch = Completer<RemoteMessage?>();
    fcm.initialGate = launch;
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    await push.onSignedIn(s);
    await push.init().timeout(const Duration(seconds: 1));
    expect(push.consumePendingTap(), isNull);
    launch.complete(RemoteMessage(data: tapData()));
    await flush();
    expect(push.consumePendingTap()?['notification_id'], '41');
    expect(push.consumePendingTap(), isNull);
  });

  test('a tap tells HomeShell (notifyListeners)', () async {
    final push = await started();
    var notified = 0;
    push.addListener(() => notified++);
    fcm.opened.add(RemoteMessage(data: tapData()));
    expect(notified, 1);
    fcm.opened.add(RemoteMessage(data: tapData(company: 'PRINTART')));
    expect(notified, 1);
  });

  test('signing out drops a tap that was not opened yet', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await push.init();
    push.handleTap(tapData());
    await s.clearSession();
    expect(push.consumePendingTap(), isNull);
  });

  // Review fix round 1 (ledger A4): the _current == null guard.
  test('a tap while the sign-out hook runs only opens the app', () async {
    final s = await signedInSession();
    log.unregisterGate = Completer<void>();
    final push = pushService(
      messaging: fcm,
      log: log,
      callTimeout: const Duration(seconds: 3),
      signOutCap: const Duration(seconds: 3),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await push.init();
    final out = s.signOut();
    await flush();
    expect(s.isLoggedIn, isTrue);
    push.handleTap(tapData());
    fcm.opened.add(RemoteMessage(data: tapData()));
    expect(push.consumePendingTap(), isNull);
    log.unregisterGate!.complete();
    await out;
    expect(push.consumePendingTap(), isNull);
  });

  test('fetchNotice goes through notifications/get', () async {
    log.notices[41] = NotificationRecord(id: 41, kind: 'leave_approval_requested', title: 'Approval needed');
    final push = await started();
    final n = await push.fetchNotice(41);
    expect(n.id, 41);
    // On the session snapshot: the signed-in tenant and its access token.
    expect(log.calls, contains('notifications/get 41 https://acme.test tok-1'));
  });

  test('fetchNotice while signed out asks nothing and fails', () async {
    final push = await started(token: null);
    await expectLater(push.fetchNotice(41), throwsA(isA<ApiException>()));
    expect(log.calls.where((c) => c.startsWith('notifications/get')), isEmpty);
  });

  test('fetchNotice: invalid_session for the current session signs out',
      () async {
    var fired = 0;
    OmniMobileApi.onInvalidSession = () => fired++;
    log.noticeError = ApiException('invalid_session');
    final push = await started();
    await expectLater(push.fetchNotice(41), throwsA(isA<ApiException>()));
    expect(fired, 1);
  });

  test('fetchNotice: invalid_session for a session that is gone (sign-out, '
      'new access token) signs nobody out', () async {
    var fired = 0;
    OmniMobileApi.onInvalidSession = () => fired++;
    log.noticeError = ApiException('invalid_session');
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await push.init();

    // A new access token while notifications/get is on the wire.
    var gate = Completer<void>();
    log.noticeGate = gate;
    var pending = push.fetchNotice(41);
    await flush();
    await newAccessToken(s, 'tok-2');
    await flush();
    gate.complete();
    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(fired, 0);

    // A sign-out while notifications/get is on the wire.
    gate = Completer<void>();
    log.noticeGate = gate;
    pending = push.fetchNotice(41);
    await flush();
    await s.clearSession();
    gate.complete();
    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(fired, 0);
  });

  test('sessionStillCurrent: false after a sign-out or a new access token',
      () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await push.init();

    final first = push.sessionStillCurrent();
    expect(first(), isTrue);
    await newAccessToken(s, 'tok-2');
    await flush();
    expect(first(), isFalse);

    final second = push.sessionStillCurrent();
    expect(second(), isTrue);
    await s.clearSession();
    expect(second(), isFalse);
    expect(push.sessionStillCurrent()(), isFalse);
  });
}
