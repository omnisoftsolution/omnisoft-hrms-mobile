import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('on resume the badge is the bell\'s fresh unread count', () async {
    final s = await signedInSession();
    final native = FakeNative();
    final bell = FakeNotifications()..unread = 3;
    final push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
      notifications: bell,
    );
    await push.onSignedIn(s);
    native.calls.clear();
    await push.onResumed();
    expect(bell.refreshes, 1);
    expect(native.calls, ['badge 3']);
  });

  test('on resume while signed out the badge is cleared', () async {
    final s = await signedInSession(token: null);
    final native = FakeNative();
    final bell = FakeNotifications()..unread = 3;
    final push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
      notifications: bell,
    );
    await push.onSignedIn(s);
    await push.onResumed();
    expect(bell.refreshes, 0);
    expect(native.calls, ['badge 0']);
  });

  test('a foreground notice re-polls the bell and sets the badge to its '
      'unread count (iOS applies no aps.badge while the app is open)', () async {
    final s = await signedInSession();
    final native = FakeNative();
    final bell = FakeNotifications()..unread = 2;
    final push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
      notifications: bell,
    );
    await push.onSignedIn(s);
    native.calls.clear();
    await push.handleForeground(<String, dynamic>{
      'kind': 'leave_approved',
      'company_code': 'ACME',
    });
    expect(bell.refreshes, 1);
    expect(native.calls, ['badge 2']);
  });

  test('a sign-out while the resume re-poll is pending: no stale badge '
      'afterwards', () async {
    final s = await signedInSession();
    final native = FakeNative();
    final bell = FakeNotifications()..unread = 3;
    final push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
      notifications: bell,
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    native.calls.clear();
    final gate = Completer<void>();
    bell.refreshGate = gate;
    final resumed = push.onResumed();
    await flush();
    await s.signOut();
    gate.complete();
    await resumed;
    await flush();
    expect(native.calls, isNot(contains('badge 3')));
    expect(native.calls.last, 'badge 0');
  });

  test('a sign-out while a foreground notice re-polls: no stale badge '
      'afterwards', () async {
    final s = await signedInSession();
    final native = FakeNative();
    final bell = FakeNotifications()..unread = 2;
    final push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
      notifications: bell,
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    native.calls.clear();
    final gate = Completer<void>();
    bell.refreshGate = gate;
    final handled = push.handleForeground(<String, dynamic>{
      'kind': 'leave_approved',
      'company_code': 'ACME',
    });
    await flush();
    await s.signOut();
    gate.complete();
    await handled;
    await flush();
    expect(native.calls, isNot(contains('badge 2')));
    expect(native.calls.last, 'badge 0');
  });
}
