import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

import 'push_fakes.dart';

/// What FlutterFire's getToken throws on iOS until APNs answered.
FirebaseException apnsNotSet() => FirebaseException(
  plugin: 'firebase_messaging',
  code: 'apns-token-not-set',
  message: 'APNS token has not been set yet.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMessaging fcm;
  late PushApiLog log;
  late FakeNative native;

  setUp(() {
    fcm = FakeMessaging();
    log = PushApiLog();
    native = FakeNative();
  });

  Iterable<String> registers() => log.calls.where((c) => c.startsWith('register'));

  test('registers the FCM token at app start when signed in, then reads prefs', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    expect(log.calls, [
      'register https://acme.test tok-1 fcm-1 android',
      'prefs/get',
    ]);
    expect(push.available, isTrue);
    expect(native.calls, ['channels']);
  });

  test('a new access token (refresh or a new sign-in) registers again', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    await s.saveSession(
      accessToken: 'tok-2',
      userId: 1,
      userLogin: 'siti',
      userName: 'Siti',
      employeeId: 1,
      employeeName: 'Siti',
    );
    await flush();
    expect(registers(), ['register https://acme.test tok-2 fcm-1 android']);
  });

  test('other session changes do not register again', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    await s.updateLeaveApprovalsFromMe({
      'leave_approvals': {'enabled': true, 'pending_count': 2},
    });
    await flush();
    expect(registers(), isEmpty);
  });

  test('onTokenRefresh registers the new token', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    fcm.token = 'fcm-2';
    fcm.refresh.add('fcm-2');
    await flush();
    expect(registers(), ['register https://acme.test tok-1 fcm-2 android']);
  });

  test('signed out: nothing is registered', () async {
    final s = await signedInSession(token: null);
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    fcm.refresh.add('fcm-2');
    await flush();
    expect(log.calls, isEmpty);
  });

  test('a failed registration is retried when the app resumes', () async {
    final s = await signedInSession();
    log.registerError = ApiException('network_error');
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    log.registerError = null;
    log.calls.clear();
    await push.onResumed();
    await flush();
    expect(registers(), ['register https://acme.test tok-1 fcm-1 android']);
    log.calls.clear();
    await push.onResumed();
    await flush();
    expect(registers(), isEmpty);
  });

  test('without Firebase nothing registers, and sign-out still works', () async {
    final s = await signedInSession();
    final push = pushService(messaging: null, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    expect(push.enabled, isFalse);
    expect(push.available, isFalse);
    expect(registers(), isEmpty);
    await s.clearSession();
    expect(s.isLoggedIn, isFalse);
  });

  test('clearSession unregisters with the old session, clears delivered '
      'notifications and deletes the FCM token', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.clearSession();
    expect(log.calls.last, 'unregister https://acme.test tok-1');
    expect(native.calls, containsAllInOrder(['clear', 'badge 0']));
    expect(fcm.deleteCalls, 1);
    expect(push.prefs, isNull);
    expect(s.isLoggedIn, isFalse);
  });

  test('logout (Clear Company) unregisters at the old company first', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.logout();
    expect(log.calls, contains('unregister https://acme.test tok-1'));
    expect(fcm.deleteCalls, 1);
    expect(s.hasCompany, isFalse);
  });

  test('a hanging unregister does not hold the sign-out', () async {
    final s = await signedInSession();
    log.unregisterGate = Completer<void>();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(milliseconds: 50),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.clearSession();
    expect(s.isLoggedIn, isFalse);
    expect(fcm.deleteCalls, 1);
  });

  test('a failed unregister still clears and deletes the token', () async {
    final s = await signedInSession();
    log.unregisterError = ApiException('invalid_session');
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.clearSession();
    expect(native.calls, contains('clear'));
    expect(fcm.deleteCalls, 1);
  });

  test('after sign-out a token refresh registers nothing', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.clearSession();
    log.calls.clear();
    fcm.refresh.add('fcm-3');
    await flush();
    expect(log.calls, isEmpty);
  });

  test('Settings → Company order (new company saved, then signOut): the '
      'old token never reaches the new company, the old company hears the '
      'unregister', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    // company_settings_screen._resolve: saveCompany first (notifies while
    // the old access token is still set) ...
    await s.saveCompany(
      saasUrl: 'https://saas.test',
      companyCode: 'BETA',
      clientUrl: 'https://beta.test',
      clientDb: 'beta',
    );
    await flush();
    expect(log.calls, isEmpty);
    // ... then signOut.
    await s.signOut();
    expect(log.calls, ['unregister https://acme.test tok-1']);
    expect(fcm.deleteCalls, 1);
    expect(s.isLoggedIn, isFalse);
  });

  test('a registration for account A still waiting for its FCM token '
      'writes nothing once B has signed in', () async {
    final s = await signedInSession();
    final gate = Completer<void>();
    fcm.tokenGate = gate;
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(milliseconds: 50),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    unawaited(push.onSignedIn(s));
    await flush();
    expect(registers(), isEmpty);
    // A signs out; B signs in at another company and registers.
    await s.signOut();
    await s.saveCompany(
      saasUrl: 'https://saas.test',
      companyCode: 'BETA',
      clientUrl: 'https://beta.test',
      clientDb: 'beta',
    );
    await s.saveSession(
      accessToken: 'tok-b',
      userId: 2,
      userLogin: 'budi',
      userName: 'Budi',
      employeeId: 2,
      employeeName: 'Budi',
    );
    await flush();
    expect(registers(), ['register https://beta.test tok-b fcm-new-1 android']);
    // A's getToken answers only now.
    gate.complete();
    await flush();
    expect(registers(), ['register https://beta.test tok-b fcm-new-1 android']);
    expect(log.calls.where((c) => c.contains('tok-1')), [
      'unregister https://acme.test tok-1',
    ]);
    // B stays registered: a resume does not register again.
    log.calls.clear();
    await push.onResumed();
    await flush();
    expect(registers(), isEmpty);
  });

  test('a prefs answer that arrives after sign-out is not kept', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    final gate = Completer<void>();
    log.prefsGetGate = gate;
    final pending = push.refreshPrefs();
    await flush();
    await s.clearSession();
    gate.complete();
    await pending;
    expect(push.prefs, isNull);
  });

  test('iOS: getToken before APNs answered (apns-token-not-set) is tried '
      'again, then the token is registered', () async {
    final s = await signedInSession();
    fcm.tokenErrors.addAll([apnsNotSet(), apnsNotSet()]);
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      platform: 'ios',
    );
    await push.init();
    await push.onSignedIn(s);
    expect(fcm.getTokenCalls, 3);
    expect(registers(), ['register https://acme.test tok-1 fcm-1 ios']);
  });

  test('iOS: after three retries it gives up quietly; the next token '
      'refresh registers', () async {
    final s = await signedInSession();
    fcm.tokenErrors.addAll(List.generate(4, (_) => apnsNotSet()));
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      platform: 'ios',
    );
    await push.init();
    await push.onSignedIn(s);
    expect(fcm.getTokenCalls, 4);
    expect(registers(), isEmpty);
    fcm.refresh.add('fcm-1');
    await flush();
    expect(registers(), ['register https://acme.test tok-1 fcm-1 ios']);
  });

  test('other getToken failures are not retried', () async {
    final s = await signedInSession();
    fcm.tokenErrors.add(
      FirebaseException(plugin: 'firebase_messaging', code: 'unknown'),
    );
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    await push.onSignedIn(s);
    expect(fcm.getTokenCalls, 1);
    expect(registers(), isEmpty);
  });
}
