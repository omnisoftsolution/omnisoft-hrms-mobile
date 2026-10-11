import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/session_service.dart';

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

  // Fix round 2 (Codex r2 MAJOR): the wipe and a sign-in never interleave
  // their storage writes.
  test('a sign-in while the wipe is deleting storage: B is what a fresh '
      'SessionService loads afterwards', () async {
    final s = await signedInSession();
    final wiping = Completer<void>();
    final release = Completer<void>();
    s.debugWipeStoragePause = () {
      wiping.complete();
      return release.future;
    };
    final out = s.clearSession();
    await wiping.future;
    var signedIn = false;
    final signIn = s
        .saveSession(
          accessToken: 'tok-b',
          userId: 2,
          userLogin: 'budi',
          userName: 'Budi',
          employeeId: 2,
          employeeName: 'Budi',
        )
        .then((_) => signedIn = true);
    await flush();
    release.complete();
    await out;
    await signIn;
    expect(signedIn, isTrue);
    expect(s.token, 'tok-b');
    final reloaded = SessionService();
    await reloaded.load();
    expect(reloaded.token, 'tok-b');
    expect(reloaded.userLogin, 'budi');
    expect(reloaded.employeeName, 'Budi');
    expect(reloaded.isLoggedIn, isTrue);
  });

  test('logout joins a clearSession already running, and a clearSession '
      'during logout joins it: the hook runs once each', () async {
    final s = await signedInSession();
    final hooks = [Completer<void>(), Completer<void>()];
    var runs = 0;
    s.onSessionClearing = () async {
      runs++;
      await hooks[runs - 1].future;
    };
    final clear = s.clearSession();
    final reset = s.logout();
    await flush();
    expect(runs, 1);
    hooks[0].complete();
    await clear;
    await flush();
    // logout's own hook is running now; an invalid_session clear joins it.
    expect(runs, 2);
    final late = s.clearSession();
    var lateDone = false;
    unawaited(late.then((_) => lateDone = true));
    await flush();
    expect(lateDone, isFalse);
    hooks[1].complete();
    await Future.wait([reset, late]);
    expect(runs, 2);
    expect(s.hasCompany, isFalse);
    expect(s.isLoggedIn, isFalse);
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
