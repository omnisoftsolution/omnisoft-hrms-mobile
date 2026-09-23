import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/profile/profile_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/security_privacy_card.dart';

import '../services/fake_gate.dart';

class _FakeApi extends OmniMobileApi {
  _FakeApi({this.onLogin, this.logoutError})
      : super(baseUrl: '', db: '', token: '');

  final Future<Map<String, dynamic>> Function()? onLogin;
  final Object? logoutError;
  String? lastDeviceLabel;
  String? lastLogin;
  bool? lastForgetDevice;

  @override
  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? deviceId,
    String? deviceLabel,
    String? appVersion,
    String? emailCode,
  }) {
    lastLogin = login;
    lastDeviceLabel = deviceLabel;
    return onLogin!();
  }

  @override
  Future<Map<String, dynamic>> logout({bool forgetDevice = false}) async {
    lastForgetDevice = forgetDevice;
    if (logoutError != null) throw logoutError!;
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('checkPasswordWith (profile password re-check)', () {
    test('account_locked maps to the lockout wait, not a connection error',
        () async {
      final session = SessionService();
      await session.setUserLogin('a@b.c');
      final api = _FakeApi(
          onLogin: () async => throw ApiException('account_locked',
              data: {'retry_after': 900}));
      final check = await checkPasswordWith(api, session, 'pw',
          deviceId: 'd', deviceLabel: 'Pixel 8');
      expect(check, isNot(PasswordCheck.ok));
      expect(check.message, 'Too many attempts. Try again in 15 minutes.');
    });

    test('success saves the response and sends the device label', () async {
      final session = SessionService();
      await session.setUserLogin('a@b.c');
      final api = _FakeApi(
          onLogin: () async => {
                'success': true,
                'access_token': 'A2',
                'auth_source': 'omni',
                'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
                'employee': {'id': 6, 'name': 'A'},
              });
      final check = await checkPasswordWith(api, session, 'pw',
          deviceId: 'd', deviceLabel: 'Pixel 8');
      expect(check, PasswordCheck.ok);
      expect(api.lastDeviceLabel, 'Pixel 8');
      expect(api.lastLogin, 'a@b.c');
      expect(session.accessToken, 'A2');
    });

    test('wrong password and rate limit keep their outcomes', () async {
      final session = SessionService();
      expect(
          await checkPasswordWith(
              _FakeApi(
                  onLogin: () async =>
                      throw ApiException('invalid_credentials')),
              session,
              'pw',
              deviceId: 'd'),
          PasswordCheck.wrongPassword);
      expect(
          await checkPasswordWith(
              _FakeApi(
                  onLogin: () async =>
                      throw ApiException('rate_limit_exceeded')),
              session,
              'pw',
              deviceId: 'd'),
          PasswordCheck.rateLimited);
      expect(
          await checkPasswordWith(
              _FakeApi(onLogin: () async => throw ApiException('network_error')),
              session,
              'pw',
              deviceId: 'd'),
          PasswordCheck.error);
    });
  });

  group('logoutWith', () {
    late SessionService session;
    late BiometricAuthService bio;

    Future<void> run(WidgetTester tester, _FakeApi api,
        {required bool forgetDevice}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => logoutWith(ctx,
                  session: session,
                  bio: bio,
                  api: api,
                  forgetDevice: forgetDevice,
                  loginBuilder: (_) => const Scaffold(body: Text('LOGIN'))),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      session = SessionService();
      await session.saveLoginResponse({
        'access_token': 'A',
        'auth_source': 'omni',
        'refresh_token': 'R',
        'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
        'employee': {'id': 6, 'name': 'A'},
      });
      bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await bio.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'R');
    });

    testWidgets('forget this phone offline: still clears locally and tells '
        'the user to remove the phone later', (tester) async {
      final api = _FakeApi(logoutError: ApiException('network_error'));
      await run(tester, api, forgetDevice: true);
      expect(api.lastForgetDevice, isTrue);
      expect(session.accessToken, '');
      expect(bio.isEnabled, isFalse);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(
          find.text('Could not reach the server. Remove this phone later '
              'under Your devices.'),
          findsOneWidget);
    });

    testWidgets('forget this phone online: no warning', (tester) async {
      await run(tester, _FakeApi(), forgetDevice: true);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(bio.isEnabled, isFalse);
    });

    testWidgets('plain sign-out offline: no warning, Face ID kept',
        (tester) async {
      await run(tester, _FakeApi(logoutError: ApiException('network_error')),
          forgetDevice: false);
      expect(find.text('LOGIN'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(bio.isEnabled, isTrue);
      expect(session.accessToken, '');
    });
  });
}
