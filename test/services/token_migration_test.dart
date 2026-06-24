import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('token migration', () {
    test('moves a legacy SharedPreferences token into secure storage', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'LEGACY-TOKEN'});
      final svc = SessionService();
      await svc.load();
      expect(svc.accessToken, 'LEGACY-TOKEN');           // still logged in
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'access_token'), 'LEGACY-TOKEN');  // now in secure store
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), isNull);   // legacy key cleared
    });

    test('reads a token already in secure storage', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'access_token': 'SECURE-TOKEN'});
      final svc = SessionService();
      await svc.load();
      expect(svc.accessToken, 'SECURE-TOKEN');
    });

    test('no token anywhere → logged out, no crash', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = SessionService();
      await svc.load();
      expect(svc.accessToken, '');
    });

    test('saveSession stores token in secure storage, not plaintext prefs', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final svc = SessionService();
      await svc.load();
      await svc.saveSession(
        accessToken: 'NEW-TOKEN',
        userId: 1,
        userLogin: 'test@example.com',
        userName: 'Test User',
        employeeId: 42,
        employeeName: 'Test Employee',
      );
      const secure = FlutterSecureStorage();
      expect(await secure.read(key: 'access_token'), 'NEW-TOKEN');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), isNull);
    });
  });
}
