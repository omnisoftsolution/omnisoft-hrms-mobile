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

  test('saveLoginResponse maps token, user and employee fields', () async {
    final session = SessionService();
    await session.saveLoginResponse({
      'access_token': 'tok123',
      'expires_at': '2026-08-01T00:00:00',
      'user': {'id': 7, 'login': 'budi@acme.sg', 'name': 'Budi'},
      'employee': {
        'id': 42,
        'name': 'Budi Santoso',
        'job_title': 'Engineer',
        'company_name': 'Acme',
      },
    });

    expect(session.accessToken, 'tok123');
    expect(session.userId, 7);
    expect(session.userLogin, 'budi@acme.sg');
    expect(session.userName, 'Budi');
    expect(session.employeeId, 42);
    expect(session.employeeName, 'Budi Santoso');
    expect(session.employeeJobTitle, 'Engineer');
    expect(session.employeeCompanyName, 'Acme');
    expect(session.expiresAt, DateTime.parse('2026-08-01T00:00:00'));
  });

  test('saveLoginResponse tolerates missing user/employee maps', () async {
    final session = SessionService();
    await session.saveLoginResponse({'access_token': 'tok'});
    expect(session.accessToken, 'tok');
    expect(session.userLogin, '');
    expect(session.employeeId, 0);
    expect(session.expiresAt, isNull);
  });
}
