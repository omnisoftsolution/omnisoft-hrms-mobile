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

  test(
      'clearSession() removes the tenant+employee-scoped announcement '
      'cache entry (regression: shared-device employee-switch leak)',
      () async {
    final session = SessionService();
    await session.load();
    await session.saveCompany(
      saasUrl: 'https://saas.example',
      companyCode: 'ACME',
      clientUrl: 'https://acme.example',
      clientDb: 'acme_db',
    );
    await session.saveSession(
      accessToken: 'tok123',
      userId: 1,
      userLogin: 'user@example.com',
      userName: 'User',
      employeeId: 42,
      employeeName: 'Employee',
    );
    final cacheKey = session.announcementCacheKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, '{"announcements":[]}');
    expect(prefs.getString(cacheKey), isNotNull);

    await session.clearSession();

    expect(prefs.getString(cacheKey), isNull);
  });

  test(
      'logout() removes the announcement cache under the pre-logout '
      'tenant+employee key (regression: company-switch orphaned the '
      'cache because _clientDb was already wiped before the key was '
      'captured)', () async {
    final session = SessionService();
    await session.load();
    await session.saveCompany(
      saasUrl: 'https://saas.example',
      companyCode: 'ACME',
      clientUrl: 'https://acme.example',
      clientDb: 'acme_db',
    );
    await session.saveSession(
      accessToken: 'tok123',
      userId: 1,
      userLogin: 'user@example.com',
      userName: 'User',
      employeeId: 42,
      employeeName: 'Employee',
    );
    // The key as actually written by HomeScreen while acme_db/employee
    // 42 were the live session — captured up front so the assertion
    // below doesn't depend on session state that logout() is about to
    // clear.
    final cacheKey = session.announcementCacheKey;
    expect(cacheKey, 'announcement_list_cache_acme_db_42');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, '{"announcements":[]}');
    expect(prefs.getString(cacheKey), isNotNull);

    await session.logout(); // company-switch path (company_settings_screen)

    expect(prefs.getString(cacheKey), isNull);
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
