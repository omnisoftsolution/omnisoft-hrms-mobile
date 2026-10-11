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
