import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_fakes.dart';

Map<String, dynamic> notice({String company = 'ACME'}) => <String, dynamic>{
  'notification_id': '41',
  'kind': 'leave_approved',
  'push_group': 'requests',
  'omni_key': 'leave:12',
  'company_code': company,
  'leave_id': '12',
};

Map<String, dynamic> reminder({String company = 'ACME'}) => <String, dynamic>{
  'notification_id': '',
  'kind': 'remind_check_in',
  'push_group': 'reminders',
  'omni_key': 'remind-in:7:20261012T0100',
  'company_code': company,
};

Map<String, dynamic> removal({String company = 'ACME'}) => <String, dynamic>{
  'action': 'remove',
  'omni_key': 'approve:77',
  'badge': '3',
  'company_code': company,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMessaging fcm;
  late PushApiLog log;
  late FakeNative native;
  late FakeNotifications bell;

  setUp(() {
    fcm = FakeMessaging();
    log = PushApiLog();
    native = FakeNative();
    bell = FakeNotifications();
  });

  Future<PushService> started({String? token = 'tok-1'}) async {
    final s = await signedInSession(token: token);
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      notifications: bell,
    );
    await push.onSignedIn(s);
    await push.init();
    native.calls.clear();
    return push;
  }

  test('a notice in the foreground re-polls the bell at once and queues no '
      'push snackbar (the bell\'s own arrival snackbar follows)', () async {
    final push = await started();
    fcm.messages.add(
      RemoteMessage(
        data: notice(),
        notification: const RemoteNotification(
          title: 'Leave approved',
          body: 'Your Annual Leave for 20 Oct was approved.',
        ),
      ),
    );
    await flush();
    expect(bell.refreshes, 1);
    expect(push.consumeArrivals(), isEmpty);
  });

  test('a reminder in the foreground becomes a snackbar from the push', () async {
    final push = await started();
    fcm.messages.add(
      RemoteMessage(
        data: reminder(),
        notification: const RemoteNotification(
          title: 'Time to check in',
          body: 'Your shift started at 09:00. Tap to check in.',
        ),
      ),
    );
    await flush();
    final arrivals = push.consumeArrivals();
    expect(arrivals.single.kind, 'remind_check_in');
    expect(arrivals.single.title, 'Time to check in');
    expect(arrivals.single.body, 'Your shift started at 09:00. Tap to check in.');
    expect(push.consumeArrivals(), isEmpty);
    expect(bell.refreshes, 0);
  });

  // Review fix round 1 (ledger A3): the connector always sends a title,
  // but an empty one must not leave an empty bold line.
  test('a reminder without a title gets its kind\'s title (the connector '
      'wording)', () async {
    final push = await started();
    await push.handleForeground(reminder(), title: '', body: 'Tap to check in.');
    await push.handleForeground(
      {...reminder(), 'kind': 'remind_check_out'},
      body: 'Tap to check out.',
    );
    final arrivals = push.consumeArrivals();
    expect(arrivals.map((a) => a.title), ['Still at work?', 'Time to check in']);
  });

  test('an error on the foreground message or opened-app stream is ignored',
      () async {
    final push = await started();
    fcm.messages.addError(StateError('message stream failed'));
    fcm.opened.addError(StateError('opened stream failed'));
    await flush();
    fcm.messages.add(
      RemoteMessage(
        data: reminder(),
        notification: const RemoteNotification(title: 'Time to check in'),
      ),
    );
    await flush();
    expect(push.consumeArrivals().single.kind, 'remind_check_in');
  });

  test('another company\'s push is ignored in the foreground', () async {
    final push = await started();
    await push.handleForeground(notice(company: 'PRINTART'));
    await push.handleForeground(reminder(company: 'PRINTART'));
    await push.handleForeground(removal(company: 'PRINTART'));
    expect(bell.refreshes, 0);
    expect(push.consumeArrivals(), isEmpty);
    expect(native.calls, isEmpty);
  });

  test('signed out: a push is ignored', () async {
    final push = await started(token: null);
    await push.handleForeground(notice());
    await push.handleForeground(reminder());
    expect(bell.refreshes, 0);
    expect(push.consumeArrivals(), isEmpty);
  });

  test('remove in the foreground takes the notification off and sets the badge', () async {
    final push = await started();
    await push.handleForeground(removal());
    expect(native.calls, ['remove approve:77', 'cancel approve:77', 'badge 3']);
    expect(bell.refreshes, 0);
  });

  test('company codes match whatever their case or spaces', () {
    expect(isForThisTenant({'company_code': 'acme '}, 'ACME'), isTrue);
    expect(isForThisTenant({'company_code': 'PRINTART'}, 'ACME'), isFalse);
    expect(isForThisTenant(<String, dynamic>{}, 'ACME'), isFalse);
    expect(isForThisTenant({'company_code': 'ACME'}, ''), isFalse);
  });

  test('background: our remove is applied, using the stored company code', () async {
    SharedPreferences.setMockInitialValues({
      'company_code': 'ACME',
      PushService.signedInKey: true,
    });
    await handleBackgroundData(removal(), pushNative: native);
    expect(native.calls, ['remove approve:77', 'cancel approve:77', 'badge 3']);
  });

  test('background: a remove while signed out takes the notification off '
      'but sets no badge (the company code survives a sign-out)', () async {
    SharedPreferences.setMockInitialValues({'company_code': 'ACME'});
    await handleBackgroundData(removal(), pushNative: native);
    expect(native.calls, ['remove approve:77', 'cancel approve:77']);
  });

  test('signed out: a remove in the foreground does nothing', () async {
    final push = await started(token: null);
    await push.handleForeground(removal());
    expect(native.calls, isEmpty);
  });

  test('while the sign-out hook runs: a remove, a notice or a reminder in '
      'the foreground does nothing', () async {
    final s = await signedInSession();
    log.unregisterGate = Completer<void>();
    final push = pushService(
      messaging: fcm,
      log: log,
      pushNative: native,
      notifications: bell,
      callTimeout: const Duration(seconds: 3),
      signOutCap: const Duration(seconds: 3),
    );
    s.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(s);
    final out = s.signOut();
    await flush();
    native.calls.clear();
    await push.handleForeground(removal());
    await push.handleForeground(notice());
    await push.handleForeground(reminder());
    expect(native.calls, isEmpty);
    expect(bell.refreshes, 0);
    expect(push.consumeArrivals(), isEmpty);
    log.unregisterGate!.complete();
    await out;
  });

  test('background: another company\'s remove and any show are ignored', () async {
    SharedPreferences.setMockInitialValues({'company_code': 'ACME'});
    await handleBackgroundData(removal(company: 'PRINTART'), pushNative: native);
    await handleBackgroundData(notice(), pushNative: native);
    expect(native.calls, isEmpty);
  });

  test('background: the company code is re-read, not taken from the '
      'isolate\'s old cache (the main isolate switched tenant)', () async {
    SharedPreferences.setMockInitialValues({'company_code': 'ACME'});
    final cached = await SharedPreferences.getInstance();
    // The main isolate signs in to PRINTART; this isolate's cache, kept
    // from an earlier message, still says ACME.
    SharedPreferences.setMockInitialValues({'company_code': 'PRINTART'});
    expect(cached.getString('company_code'), 'ACME');
    Future<String> code() => storedCompanyCode(open: () async => cached);
    // Signed in (the marker is read the same way; here it is stubbed).
    Future<bool> signedIn() async => true;
    await handleBackgroundData(
      removal(),
      pushNative: native,
      companyCode: code,
      signedIn: signedIn,
    );
    expect(native.calls, isEmpty);
    await handleBackgroundData(
      removal(company: 'PRINTART'),
      pushNative: native,
      companyCode: code,
      signedIn: signedIn,
    );
    expect(native.calls, ['remove approve:77', 'cancel approve:77', 'badge 3']);
  });

  test('a remove without a badge only takes the notification off', () async {
    await applyRemove({'omni_key': 'leave:12'}, native);
    expect(native.calls, ['remove leave:12', 'cancel leave:12']);
  });
}
