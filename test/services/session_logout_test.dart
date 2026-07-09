import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('logout() fires onLogout', () async {
    final svc = SessionService();
    await svc.load();
    var fired = 0;
    svc.onLogout = () => fired++;
    await svc.logout();
    expect(fired, 1);
  });

  test('clearSession() does NOT fire onLogout', () async {
    final svc = SessionService();
    await svc.load();
    var fired = 0;
    svc.onLogout = () => fired++;
    await svc.clearSession();
    expect(fired, 0);
  });

  test('signOut() fires onLogout', () async {
    final svc = SessionService();
    await svc.load();
    var fired = 0;
    svc.onLogout = () => fired++;
    await svc.signOut();
    expect(fired, 1);
  });

  test('signOut() clears the access token', () async {
    final svc = SessionService();
    await svc.load();
    await svc.saveSession(
      accessToken: 'tok123',
      userId: 1,
      userLogin: 'user@example.com',
      userName: 'User',
      employeeId: 1,
      employeeName: 'Employee',
    );
    expect(svc.token, isNotEmpty);
    await svc.signOut();
    expect(svc.token, isEmpty);
  });

  test('clearSession() keeps the biometric credential (onLogout not fired)',
      () async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final session = SessionService();
    await session.load();
    final bio = BiometricAuthService();
    await bio.load();
    session.onLogout = () => bio.disable();
    expect(bio.isEnabled, isTrue);

    await session.clearSession(); // what Profile "Log out" now calls
    expect(bio.isEnabled, isTrue); // credential survives a manual logout
  });

  test('signOut() wipes the biometric credential (onLogout fired)', () async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    final session = SessionService();
    await session.load();
    final bio = BiometricAuthService();
    await bio.load();
    // onLogout fires disable() fire-and-forget (void callback); capture the
    // future so the assertion is deterministic rather than delay-based.
    Future<void>? disableFuture;
    session.onLogout = () => disableFuture = bio.disable();
    expect(bio.isEnabled, isTrue);

    await session.signOut(); // what Delete account / company-change call
    await disableFuture; // await the fire-and-forget disable()
    expect(bio.isEnabled, isFalse);
  });
}
