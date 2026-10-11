import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import 'push_fakes.dart';

/// Branch review fix round 1: one serialized push lifecycle (register,
/// unregister, deleteToken, adopt never overtake each other).

Future<void> signIn(SessionService s, String token) => s.saveSession(
  accessToken: token,
  userId: 2,
  userLogin: 'budi',
  userName: 'Budi',
  employeeId: 2,
  employeeName: 'Budi',
);

/// `auth/refresh` that answers with [newToken] once [gate] opens.
class GatedRefreshApi extends OmniMobileApi {
  GatedRefreshApi(this.gate, this.newToken)
    : super(baseUrl: 'https://acme.test', db: 'acme', token: '');

  final Completer<void> gate;
  final String newToken;

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    await gate.future;
    return {'access_token': newToken, 'expires_at': ''};
  }
}

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

  tearDown(() => OmniMobileApi.onInvalidSession = null);

  Iterable<String> registers() =>
      log.calls.where((c) => c.startsWith('register'));

  // -- Codex 1 / Opus m4: the token deletion outlives its timeout --

  test('a token deletion slower than the call timeout: B waits for it and '
      'registers the fresh token, never the deleted one', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(milliseconds: 20),
      signOutCap: const Duration(milliseconds: 20),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    final deleting = Completer<void>();
    fcm.deleteGate = deleting;
    await s.signOut();
    await signIn(s, 'tok-b');
    // Well past the call timeout; FCM is still deleting the old token.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await flush();
    expect(registers(), isEmpty);
    deleting.complete();
    await flush();
    expect(registers(), ['register https://acme.test tok-b fcm-new-1 android']);
    expect(push.registeredToken, 'fcm-new-1');
  });

  test('a deletion still running after the safety cap: B registers now, '
      'then again with the fresh token once the deletion ends', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(milliseconds: 20),
      signOutCap: const Duration(milliseconds: 20),
      teardownWaitCap: const Duration(milliseconds: 60),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    final deleting = Completer<void>();
    fcm.deleteGate = deleting;
    await s.signOut();
    await signIn(s, 'tok-b');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await flush();
    expect(registers(), ['register https://acme.test tok-b fcm-1 android']);
    deleting.complete();
    await flush();
    expect(registers(), [
      'register https://acme.test tok-b fcm-1 android',
      'register https://acme.test tok-b fcm-new-1 android',
    ]);
    expect(push.registeredToken, 'fcm-new-1');
  });

  // -- Codex 2: an access token arriving during the sign-out --

  test('an auth/refresh that lands during the sign-out hook is not adopted '
      'and nothing registers after the sign-out', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(seconds: 3),
      signOutCap: const Duration(seconds: 3),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    final answer = Completer<void>();
    final refreshing = s.refreshAccessTokenWith(
      GatedRefreshApi(answer, 'tok-2'),
      'device-1',
      refreshToken: 'R',
    );
    await flush();
    log.unregisterGate = Completer<void>();
    final out = s.signOut();
    await flush();
    // auth/refresh answers while the hook waits for push/unregister.
    answer.complete();
    final outcome = await refreshing;
    await flush();
    expect(registers(), isEmpty);
    log.unregisterGate!.complete();
    await out;
    await flush();
    expect(s.isLoggedIn, isFalse);
    expect(outcome, RefreshOutcome.failed);
    await push.onResumed();
    fcm.refresh.add('fcm-9');
    await flush();
    expect(registers(), isEmpty);
  });

  test('a registration whose session changed under it (new routing, same '
      'token) sends nothing', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    final gate = Completer<void>();
    fcm.tokenGate = gate;
    final signingIn = push.onSignedIn(s);
    await flush();
    await s.saveCompany(
      saasUrl: 'https://saas.test',
      companyCode: 'BETA',
      clientUrl: 'https://beta.test',
      clientDb: 'beta',
    );
    gate.complete();
    await signingIn;
    await flush();
    expect(registers(), isEmpty);
  });

  // -- Codex 3: concurrent session clears --

  test('two invalid-session clears at once, B signs in before the first '
      'hook is released: B stays signed in and B registers', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(seconds: 3),
      signOutCap: const Duration(seconds: 3),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    log.calls.clear();
    log.unregisterGate = Completer<void>();
    final first = s.clearSession();
    final second = s.clearSession();
    await flush();
    // The second clear joins the first: the session is not wiped early.
    expect(s.isLoggedIn, isTrue);
    expect(s.isClearing, isTrue);
    await signIn(s, 'tok-b');
    await flush();
    // Not adopted while the old session is being cleared.
    expect(registers(), isEmpty);
    log.unregisterGate!.complete();
    await Future.wait([first, second]);
    await flush();
    expect(s.isLoggedIn, isTrue);
    expect(s.token, 'tok-b');
    expect(registers(), ['register https://acme.test tok-b fcm-new-1 android']);
    expect(push.registeredToken, 'fcm-new-1');
    expect(push.sessionStillCurrent()(), isTrue);
    expect(log.calls.where((c) => c.startsWith('unregister')), [
      'unregister https://acme.test tok-1',
    ]);
  });

  // -- Codex 4: overlapping registrations --

  test('token refreshes while a push/register is on the wire: exactly one '
      'follow-up with the newest token, sent after the first landed', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    await push.init();
    final wire = Completer<void>();
    log.registerGate = wire;
    unawaited(push.onSignedIn(s));
    await flush();
    expect(registers(), ['register https://acme.test tok-1 fcm-1 android']);
    fcm.token = 'fcm-2';
    fcm.refresh.add('fcm-2');
    fcm.token = 'fcm-3';
    fcm.refresh.add('fcm-3');
    await flush();
    expect(registers(), ['register https://acme.test tok-1 fcm-1 android']);
    wire.complete();
    await flush();
    expect(registers(), [
      'register https://acme.test tok-1 fcm-1 android',
      'register https://acme.test tok-1 fcm-3 android',
    ]);
    expect(log.landed.last, 'register tok-1 fcm-3');
    expect(push.registeredToken, 'fcm-3');
  });

  test('sign-out waits for every push/register on the wire; a follow-up '
      'still queued is dropped', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      callTimeout: const Duration(seconds: 3),
      signOutCap: const Duration(seconds: 3),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    final wire = Completer<void>();
    log.registerGate = wire;
    unawaited(push.onSignedIn(s));
    await flush();
    fcm.token = 'fcm-2';
    fcm.refresh.add('fcm-2');
    await flush();
    final out = s.clearSession();
    await flush();
    expect(log.calls.where((c) => c.startsWith('unregister')), isEmpty);
    wire.complete();
    await out;
    await flush();
    expect(
      log.calls.where(
        (c) => c.startsWith('register') || c.startsWith('unregister'),
      ),
      [
        'register https://acme.test tok-1 fcm-1 android',
        'unregister https://acme.test tok-1',
      ],
    );
  });

  // -- Opus m2: a sign-out with nothing to tear down --

  test('a sign-out while already signed out returns at once and keeps the '
      'FCM token', () async {
    final s = await signedInSession(token: null);
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      signOutCap: const Duration(seconds: 10),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    fcm.deleteGate = Completer<void>(); // a deleteToken would hang
    final sw = Stopwatch()..start();
    await s.clearSession();
    sw.stop();
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    expect(fcm.deleteCalls, 0);
    expect(log.calls, isEmpty);
  });

  test('a late invalid_session after a sign-out tears nothing down again',
      () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, pushNative: native);
    s.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(s);
    await s.signOut();
    expect(fcm.deleteCalls, 1);
    log.calls.clear();
    await s.clearSession();
    expect(fcm.deleteCalls, 1);
    expect(log.calls, isEmpty);
  });
}
