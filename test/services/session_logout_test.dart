import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';

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
}
