import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/login/login_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/primary_button.dart';

import '../services/fake_gate.dart';

/// Scripted /login (one reply per call, in order) and /auth/refresh.
class _FakeApi extends OmniMobileApi {
  _FakeApi({this.loginReplies = const [], this.onRefresh})
      : super(baseUrl: 'https://nova.example', db: 'nova_db', token: '');

  final List<Future<Map<String, dynamic>> Function()> loginReplies;
  final Future<Map<String, dynamic>> Function()? onRefresh;
  final loginCalls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? deviceId,
    String? deviceLabel,
    String? appVersion,
    String? emailCode,
  }) {
    loginCalls.add({'login': login, 'email_code': emailCode});
    return loginReplies[loginCalls.length - 1]();
  }

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
    required String deviceId,
  }) =>
      onRefresh!();
}

/// Routes refresh through the real refreshAccessTokenWith (fake api) and
/// records the call order; /me is stubbed.
class _Session extends SessionService {
  _Session(this.api);
  final _FakeApi api;
  final calls = <String>[];

  @override
  Future<RefreshOutcome> refreshAccessToken(String deviceId,
      {String? refreshToken}) {
    calls.add('refresh');
    return refreshAccessTokenWith(api, deviceId, refreshToken: refreshToken);
  }

  @override
  Future<bool> refreshMe() async {
    calls.add('me');
    return true;
  }
}

Map<String, dynamic> _loginRes({String rt = 'B-R'}) => {
      'success': true,
      'access_token': 'NEW-A',
      'expires_at': '2099-01-01 00:00:00',
      'refresh_token': rt,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'b@b.c', 'name': 'B'},
      'employee': {'id': 6, 'name': 'B'},
    };

Widget _host(SessionService session, BiometricAuthService bio,
        {_FakeApi? api}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(value: session),
        ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
      ],
      child: MaterialApp(
        home: LoginScreen(
          apiBuilder: api == null ? null : (_, _) => api,
          homeBuilder: (_) => const Scaffold(body: Text('HOME')),
        ),
      ),
    );

Future<void> _pumpFrames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _signInEnabled(WidgetTester tester) {
  final b = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
  return b.onPressed != null && !b.loading;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Forgot password gating (legacy connectors)', () {
    testWidgets('hidden when the connector has not shown identity support',
        (tester) async {
      final session = SessionService();
      await session.load();
      final bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await tester.pumpWidget(_host(session, bio));
      await tester.pumpAndSettle();
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Activate with an invite'), findsOneWidget);
    });

    testWidgets('shown when the connector is identity-capable',
        (tester) async {
      SharedPreferences.setMockInitialValues({'identity_capable': true});
      final session = SessionService();
      await session.load();
      final bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await tester.pumpWidget(_host(session, bio));
      await tester.pumpAndSettle();
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Activate with an invite'), findsOneWidget);
    });
  });

  group('Face ID with a refresh credential', () {
    late _FakeApi api;
    late _Session session;
    late BiometricAuthService bio;

    Future<void> setUpWith(
        WidgetTester tester, Future<Map<String, dynamic>> Function() onRefresh)
        async {
      api = _FakeApi(onRefresh: onRefresh);
      session = _Session(api);
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      bio = BiometricAuthService(gate: FakeBiometricGate(available: true));
      await bio.load();
      await bio.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'FACE');
      await tester.pumpWidget(_host(session, bio, api: api));
      await tester.pumpAndSettle();
      final btn = find.text('Sign in with fingerprint');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }

    testWidgets('invalid: Face ID is turned off and the user is asked to sign '
        'in again', (tester) async {
      await setUpWith(tester, () async => throw ApiException('refresh_invalid'));
      expect(session.calls, ['refresh']);
      expect(bio.isEnabled, isFalse);
      expect(find.text('Please sign in again.'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('failed: Face ID stays on and the no-internet message shows',
        (tester) async {
      await setUpWith(tester, () async => throw ApiException('network_error'));
      expect(session.calls, ['refresh']);
      expect(bio.isEnabled, isTrue);
      expect(
          find.text('No internet connection. Check your network and try '
              'again.'),
          findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('ok: /me is re-pulled, then home', (tester) async {
      await setUpWith(
          tester,
          () async => {
                'success': true,
                'access_token': 'NEW-A',
                'expires_at': '2099-01-01 00:00:00',
                'auth_source': 'omni',
              });
      expect(session.calls, ['refresh', 'me']);
      expect(session.accessToken, 'NEW-A');
      expect(session.userLogin, 'a@b.c');
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('password login', () {
    late _FakeApi api;
    late SessionService session;
    late BiometricAuthService bio;

    Future<void> pumpLogin(WidgetTester tester, _FakeApi fake,
        {String login = 'b@b.c'}) async {
      api = fake;
      await tester.pumpWidget(_host(session, bio, api: api));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), login);
      await tester.enterText(find.byType(TextField).at(1), 'secret-pw');
      await tester.tap(find.byType(PrimaryButton));
    }

    setUp(() async {
      session = SessionService();
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      // Device not capable → no opt-in sheet after a successful login.
      bio = BiometricAuthService(gate: FakeBiometricGate(available: false));
      await bio.load();
    });

    testWidgets('new phone: the emailed code is sent on the retry, and Sign '
        'in stays disabled while the retry is pending', (tester) async {
      final retry = Completer<Map<String, dynamic>>();
      await pumpLogin(
          tester,
          _FakeApi(loginReplies: [
            () async => throw ApiException('device_verification_required'),
            () => retry.future,
          ]));
      // The Sign in spinner animates under the dialog: no pumpAndSettle.
      await _pumpFrames(tester);
      expect(find.text('New phone'), findsOneWidget);
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '123456');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _pumpFrames(tester);
      expect(api.loginCalls.length, 2);
      expect(api.loginCalls[1]['email_code'], '123456');
      // I3: the first attempt's `finally` must not re-enable the button
      // while the retry is still in flight.
      expect(_signInEnabled(tester), isFalse);
      retry.complete(_loginRes());
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a wrong code re-opens the dialog with the error; Cancel ends '
        'the loop and re-enables Sign in', (tester) async {
      await pumpLogin(
          tester,
          _FakeApi(loginReplies: [
            () async => throw ApiException('device_verification_required'),
            () async => throw ApiException('verification_code_invalid'),
          ]));
      await _pumpFrames(tester);
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '000000');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await _pumpFrames(tester);
      expect(api.loginCalls.length, 2);
      expect(find.text('New phone'), findsOneWidget);
      expect(find.text('That code is not right or has expired.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New phone'), findsNothing);
      expect(api.loginCalls.length, 2);
      expect(_signInEnabled(tester), isTrue);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('account_locked shows the wait in minutes', (tester) async {
      await pumpLogin(
          tester,
          _FakeApi(loginReplies: [
            () async => throw ApiException('account_locked',
                data: {'retry_after': 900}),
          ]));
      await tester.pumpAndSettle();
      expect(find.text('Too many attempts. Try again in 15 minutes.'),
          findsOneWidget);
    });

    testWidgets('C1: another login on this phone leaves the Face ID owner\'s '
        'credential untouched', (tester) async {
      bio = BiometricAuthService(gate: FakeBiometricGate(available: true));
      await bio.load();
      await bio.enableWithRefreshToken(login: 'a@b.c', refreshToken: 'A-R');
      await pumpLogin(
          tester, _FakeApi(loginReplies: [() async => _loginRes(rt: 'B-R')]));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(session.refreshToken, 'B-R');
      const s = FlutterSecureStorage();
      expect(await s.read(key: 'biometric_login'), 'a@b.c');
      expect(await s.read(key: 'biometric_refresh_token'), 'A-R');
    });

    testWidgets('the typed login reaches /login with its case preserved',
        (tester) async {
      await pumpLogin(
          tester, _FakeApi(loginReplies: [() async => _loginRes()]),
          login: '  Say.Puay@Example.com ');
      await tester.pumpAndSettle();
      expect(api.loginCalls.single['login'], 'Say.Puay@Example.com');
    });
  });
}
