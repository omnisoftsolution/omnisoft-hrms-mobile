import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearSession runs onSessionClearing first, with the session intact', () async {
    final s = await signedInSession();
    final seen = <String>[];
    s.onSessionClearing = () async => seen.add('${s.clientUrl} ${s.token}');
    await s.clearSession();
    expect(seen, ['https://acme.test tok-1']);
    expect(s.token, isEmpty);
  });

  test('logout runs it once, before the company routing is wiped', () async {
    final s = await signedInSession();
    final seen = <String>[];
    s.onSessionClearing = () async => seen.add('${s.clientUrl} ${s.token}');
    await s.logout();
    expect(seen, ['https://acme.test tok-1']);
    expect(s.hasCompany, isFalse);
  });

  test('signOut runs it once', () async {
    final s = await signedInSession();
    var runs = 0;
    s.onSessionClearing = () async => runs++;
    await s.signOut();
    expect(runs, 1);
  });

  test('a failing hook does not stop the sign-out', () async {
    final s = await signedInSession();
    s.onSessionClearing = () async => throw StateError('boom');
    await s.clearSession();
    expect(s.isLoggedIn, isFalse);
  });

  test('two clearSession calls at once run the hook once; the second waits '
      'for the first instead of wiping the session early', () async {
    final s = await signedInSession();
    final hook = Completer<void>();
    var runs = 0;
    s.onSessionClearing = () async {
      runs++;
      await hook.future;
    };
    final first = s.clearSession();
    final second = s.clearSession();
    await flush();
    expect(s.isLoggedIn, isTrue);
    expect(s.isClearing, isTrue);
    var secondDone = false;
    unawaited(second.then((_) => secondDone = true));
    await flush();
    expect(secondDone, isFalse);
    hook.complete();
    await Future.wait([first, second]);
    expect(runs, 1);
    expect(s.isLoggedIn, isFalse);
    expect(s.isClearing, isFalse);
  });

  test('a sign-in completed while the hook runs is newer than the sign-out '
      'and is kept', () async {
    final s = await signedInSession();
    final hook = Completer<void>();
    s.onSessionClearing = () => hook.future;
    final out = s.clearSession();
    await flush();
    await s.saveSession(
      accessToken: 'tok-b',
      userId: 2,
      userLogin: 'budi',
      userName: 'Budi',
      employeeId: 2,
      employeeName: 'Budi',
    );
    hook.complete();
    await out;
    expect(s.isLoggedIn, isTrue);
    expect(s.token, 'tok-b');
    expect(s.userLogin, 'budi');
  });

  test('a clearSession started inside the hook does not run it again', () async {
    final s = await signedInSession();
    var runs = 0;
    s.onSessionClearing = () async {
      runs++;
      await s.clearSession();
    };
    await s.clearSession();
    expect(runs, 1);
    expect(s.isLoggedIn, isFalse);
  });
}
