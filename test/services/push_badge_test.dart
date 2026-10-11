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
}
