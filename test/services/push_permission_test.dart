import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/push_prefs.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/push_service.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMessaging fcm;
  late PushApiLog log;

  setUp(() {
    fcm = FakeMessaging()..status = AuthorizationStatus.notDetermined;
    log = PushApiLog();
  });

  tearDown(() => OmniMobileApi.onInvalidSession = null);

  test('the explainer is due once after sign-in when nothing was asked yet', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    await push.onSignedIn(s);
    expect(push.consumeExplainerDue(), isTrue);
    expect(push.consumeExplainerDue(), isFalse);
  });

  test('once shown it never comes back (next app start included)', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    await push.onSignedIn(s);
    push.consumeExplainerDue();
    await push.markExplainerSeen();
    final next = pushService(messaging: fcm, log: log, platform: 'ios');
    await next.onSignedIn(s);
    expect(next.consumeExplainerDue(), isFalse);
    expect(await next.shouldShowExplainer(), isFalse);
  });

  test('no explainer when the tenant has no push', () async {
    log.prefs = const PushPrefs(pushAvailable: false, remindersAvailable: false, muted: <String>{});
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    await push.onSignedIn(s);
    expect(push.consumeExplainerDue(), isFalse);
  });

  test('no explainer when the phone already allows or refused', () async {
    final s = await signedInSession();
    fcm.status = AuthorizationStatus.authorized;
    final allowed = pushService(messaging: fcm, log: log, platform: 'ios');
    await allowed.onSignedIn(s);
    expect(allowed.consumeExplainerDue(), isFalse);
    fcm.status = AuthorizationStatus.denied;
    final refused = pushService(messaging: fcm, log: log, platform: 'ios');
    await refused.onSignedIn(s);
    expect(refused.consumeExplainerDue(), isFalse);
  });

  test('iOS: permission follows the system status', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    await push.onSignedIn(s);
    expect(await push.permission(), PushPermission.notAsked);
    fcm.status = AuthorizationStatus.provisional;
    expect(await push.permission(), PushPermission.granted);
    fcm.status = AuthorizationStatus.denied;
    expect(await push.permission(), PushPermission.denied);
    fcm.status = AuthorizationStatus.deniedPermanently;
    expect(await push.permission(), PushPermission.denied);
  });

  test('Android 13+ (firebase_messaging 16.7): never asked and refused once '
      'both offer the system prompt; refused for good opens the settings', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'android');
    await push.onSignedIn(s);
    expect(await push.permission(), PushPermission.notAsked);
    fcm.afterRequest = AuthorizationStatus.denied;
    expect(await push.requestPermission(), PushPermission.notAsked);
    fcm.afterRequest = AuthorizationStatus.deniedPermanently;
    expect(await push.requestPermission(), PushPermission.denied);
    expect(fcm.requests, 2);
    expect(await push.permission(), PushPermission.denied);
  });

  test('Android: a phone that was asked before (denied, or denied for good) '
      'gets no explainer', () async {
    final s = await signedInSession();
    for (final status in [
      AuthorizationStatus.denied,
      AuthorizationStatus.deniedPermanently,
    ]) {
      fcm.status = status;
      final push = pushService(messaging: fcm, log: log, platform: 'android');
      await push.onSignedIn(s);
      expect(push.consumeExplainerDue(), isFalse, reason: '$status');
    }
  });

  test('without Firebase there is nothing to allow', () async {
    final s = await signedInSession();
    final push = pushService(messaging: null, log: log);
    await push.onSignedIn(s);
    expect(await push.permission(), PushPermission.denied);
    expect(await push.shouldShowExplainer(), isFalse);
  });

  test('savePrefs sends the sorted mutes and keeps the answer', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    await push.onSignedIn(s);
    final saved = await push.savePrefs({'news', 'approvals'});
    expect(log.calls.last, 'prefs/set approvals,news');
    expect(saved.muted, {'news', 'approvals'});
    expect(push.prefs?.muted, {'news', 'approvals'});
  });

  test('saves go one at a time, in order: a slow first save cannot land '
      'after a later one (prefs/set replaces all mutes)', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    await push.onSignedIn(s);
    final gate = Completer<void>();
    log.prefsSetGate = gate;
    final first = push.savePrefs({'approvals'});
    final second = push.savePrefs({'approvals', 'news'});
    await flush();
    Iterable<String> sets() => log.calls.where((c) => c.startsWith('prefs/set'));
    expect(sets(), ['prefs/set approvals']);
    gate.complete();
    await first;
    await second;
    expect(sets(), ['prefs/set approvals', 'prefs/set approvals,news']);
    expect(push.prefs?.muted, {'approvals', 'news'});
  });

  test('a save still queued when the person signs out is never sent with '
      'the next account', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    final gate = Completer<void>();
    log.prefsSetGate = gate;
    final first = push.savePrefs({'approvals'});
    final queued = push.savePrefs({'approvals', 'news'});
    await flush();
    // A signs out, B signs in while A's first save is still on the wire.
    await s.signOut();
    await s.saveSession(
      accessToken: 'tok-b',
      userId: 2,
      userLogin: 'budi',
      userName: 'Budi',
      employeeId: 2,
      employeeName: 'Budi',
    );
    await flush();
    gate.complete();
    await first;
    await expectLater(queued, throwsA(isA<ApiException>()));
    expect(log.prefsSetTokens, ['tok-1']);
  });

  test('a failed save does not stop the next one', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    await push.onSignedIn(s);
    log.prefsSetError = ApiException('network_error');
    await expectLater(push.savePrefs({'news'}), throwsA(isA<ApiException>()));
    log.prefsSetError = null;
    final saved = await push.savePrefs({'approvals'});
    expect(saved.muted, {'approvals'});
  });

  // push/prefs/set is quiet (fireHooks: false), so PushService forwards
  // invalid_session itself — only for the session still signed in.
  test('savePrefs: invalid_session for the current session signs out',
      () async {
    var fired = 0;
    OmniMobileApi.onInvalidSession = () => fired++;
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    await push.onSignedIn(s);
    log.prefsSetError = ApiException('invalid_session');
    await expectLater(push.savePrefs({'news'}), throwsA(isA<ApiException>()));
    expect(fired, 1);
  });

  test('savePrefs: invalid_session for a session already signed out (and a '
      'queued save dropped at sign-out) signs nobody out', () async {
    var fired = 0;
    OmniMobileApi.onInvalidSession = () => fired++;
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log);
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    final gate = Completer<void>();
    log.prefsSetGate = gate;
    log.prefsSetError = ApiException('invalid_session');
    final first = push.savePrefs({'news'});
    final queued = push.savePrefs({'news', 'approvals'});
    await flush();
    await s.signOut();
    gate.complete();
    await expectLater(first, throwsA(isA<ApiException>()));
    await expectLater(queued, throwsA(isA<ApiException>()));
    expect(fired, 0);
  });

  // Review fix 1 (spec §6.2): below Android 13 there is no runtime prompt;
  // firebase_messaging reports `denied` whenever notifications are off and
  // requestPermission cannot ask, so only the phone's settings help.
  test('Android 12 and older: notifications off means the settings, and '
      'no explainer', () async {
    final s = await signedInSession();
    fcm.status = AuthorizationStatus.denied;
    final push = pushService(
      messaging: fcm,
      log: log,
      platform: 'android',
      androidSdk: 31,
    );
    await push.onSignedIn(s);
    expect(await push.permission(), PushPermission.denied);
    expect(push.consumeExplainerDue(), isFalse);
    expect(await push.shouldShowExplainer(), isFalse);
  });

  test('Android 13+: denied may ask again, deniedPermanently means the '
      'settings', () async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      platform: 'android',
      androidSdk: 33,
    );
    await push.onSignedIn(s);
    fcm.status = AuthorizationStatus.denied;
    expect(await push.permission(), PushPermission.notAsked);
    fcm.status = AuthorizationStatus.deniedPermanently;
    expect(await push.permission(), PushPermission.denied);
  });

  // Review fix 2: the explainer flag belongs to the session it was found for.
  test('a sign-out while the explainer check runs leaves no explainer due',
      () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    s.onSessionClearing = push.onSessionCleared;
    final gate = Completer<void>();
    fcm.statusGate = gate;
    final signingIn = push.onSignedIn(s);
    await flush();
    await s.signOut();
    gate.complete();
    await signingIn;
    expect(push.consumeExplainerDue(), isFalse);
  });

  test('an explainer due but not shown yet is dropped at sign-out', () async {
    final s = await signedInSession();
    final push = pushService(messaging: fcm, log: log, platform: 'ios');
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    await s.signOut();
    expect(push.consumeExplainerDue(), isFalse);
  });
}
