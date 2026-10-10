import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/company_info.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';
import 'package:omni_hr/screens/activation/add_phone_screen.dart';
import 'package:omni_hr/screens/login/login_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../services/fake_gate.dart';

/// BiometricAuthService whose secure-storage steps can be made to fail.
class _Bio extends BiometricAuthService {
  _Bio({super.gate});
  bool throwOnAdopt = false;
  bool throwOnEnable = false;
  int enableCalls = 0;

  @override
  Future<bool> adoptRefreshToken(String refreshToken,
      {required String login}) {
    if (throwOnAdopt) throw StateError('keychain write failed');
    return super.adoptRefreshToken(refreshToken, login: login);
  }

  @override
  Future<bool> enableWithRefreshToken({
    required String login,
    required String refreshToken,
    String? displayName,
  }) {
    enableCalls++;
    if (throwOnEnable) throw StateError('keychain write failed');
    return super.enableWithRefreshToken(
        login: login, refreshToken: refreshToken, displayName: displayName);
  }
}

/// SessionService whose SaaS lookup is scripted (no HTTP).
class _Session extends SessionService {
  _Session({this.info});
  final CompanyInfo? info;
  int lookups = 0;
  String? lastLookupCode;

  /// When true, storing the login response fails (local persistence error).
  bool failSave = false;

  @override
  Future<void> saveLoginResponse(Map<String, dynamic> res) {
    if (failSave) throw StateError('disk full');
    return super.saveLoginResponse(res);
  }

  /// How many saveCompanyInfo calls fail before one succeeds.
  int failCompanySaves = 0;
  int companySaveCalls = 0;

  @override
  Future<void> saveCompanyInfo(CompanyInfo info, {required String saasUrl}) {
    companySaveCalls++;
    if (failCompanySaves > 0) {
      failCompanySaves--;
      throw StateError('disk full');
    }
    return super.saveCompanyInfo(info, saasUrl: saasUrl);
  }

  @override
  Future<CompanyInfo> lookupCompany(String code, {String? saasUrl}) async {
    lookups++;
    lastLookupCode = code;
    return info!;
  }
}

/// Records what auth/add_device was sent.
class _FakeApi extends OmniMobileApi {
  _FakeApi(String baseUrl, String db, this.onAddDevice)
      : super(baseUrl: baseUrl, db: db, token: '');

  final Future<Map<String, dynamic>> Function() onAddDevice;
  final calls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> addDevice({
    required String login,
    String? token,
    String? code,
    required String password,
    required String deviceId,
    String? deviceLabel,
    String? appVersion,
  }) {
    calls.add({
      'login': login,
      'token': token,
      'code': code,
      'password': password,
      'device_id': deviceId,
    });
    return onAddDevice();
  }
}

final _nova = CompanyInfo(
  companyCode: 'NOVAWORKS',
  name: 'Nova Works',
  odooUrl: 'https://nova.example',
  database: 'nova_db',
  features: const {'attendance': true},
);

Map<String, dynamic> _okRes(
        {String token = 'NEW-A', String rt = 'R', String login = 'budi.s'}) =>
    {
      'success': true,
      'access_token': token,
      'expires_at': '2099-01-01 00:00:00',
      'refresh_token': rt,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': login, 'name': 'Budi'},
      'employee': {'id': 6, 'name': 'Budi'},
    };

Finder get _addButton => find.widgetWithText(FilledButton, 'Add this phone');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'link mode: company and login prefilled, no code field; the button '
      'needs the app password', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AddPhoneScreen(
            companyCode: 'NOVAWORKS', token: 'T', login: 'budi.s')));
    expect(find.text('Add this phone to Omni HR'), findsOneWidget);
    expect(find.textContaining('Your other phones stay signed in'),
        findsOneWidget);
    expect(find.text('NOVAWORKS'), findsOneWidget);
    expect(find.text('budi.s'), findsOneWidget);
    expect(find.byKey(const Key('add_phone_company')), findsNothing);
    expect(find.byKey(const Key('add_phone_code')), findsNothing);
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('add_phone_password')), 'my-app-pw');
    await tester.pump();
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
  });

  testWidgets(
      'manual mode asks for company code, login, a 6-digit code and the '
      'app password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AddPhoneScreen()));
    expect(find.byKey(const Key('add_phone_company')), findsOneWidget);
    expect(find.byKey(const Key('add_phone_login')), findsOneWidget);
    expect(find.byKey(const Key('add_phone_code')), findsOneWidget);
    expect(find.byKey(const Key('add_phone_password')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('add_phone_company')), 'NOVAWORKS');
    await tester.enterText(find.byKey(const Key('add_phone_login')), 'budi.s');
    await tester.enterText(find.byKey(const Key('add_phone_code')), '12345');
    await tester.enterText(
        find.byKey(const Key('add_phone_password')), 'my-app-pw');
    await tester.pump();
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('add_phone_code')), '123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
  });

  testWidgets(
      'invited employees are pointed at activation, which the hint opens',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: AddPhoneScreen(companyCode: 'NOVAWORKS')));
    final hint = find.text('New to Omni HR? Use Activate with an invite.');
    expect(hint, findsOneWidget);
    await tester.ensureVisible(hint);
    await tester.tap(hint);
    await tester.pumpAndSettle();
    final screen = tester.widget<ActivationScreen>(find.byType(ActivationScreen));
    expect(screen.companyCode, 'NOVAWORKS');
  });

  testWidgets('a company code from the sign-in screen is shown, not asked',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: AddPhoneScreen(companyCode: 'NOVAWORKS')));
    expect(find.text('NOVAWORKS'), findsOneWidget);
    expect(find.byKey(const Key('add_phone_company')), findsNothing);
    expect(find.byKey(const Key('add_phone_code')), findsOneWidget);
  });

  group('submit', () {
    late _Session session;
    late BiometricAuthService bio;
    _FakeApi? api;
    String? builtUrl;
    String? builtDb;

    /// [realApi]: the real [OmniMobileApi] (answer it with
    /// `http.runWithClient`) instead of [_FakeApi]. [pushed]: the screen
    /// is pushed above a plain, non-reactive root route (like a bare
    /// HomeShell or LoginScreen left by an earlier stack reset).
    Future<void> pumpScreen(
      WidgetTester tester, {
      String? companyCode,
      String? token,
      String? login,
      Future<Map<String, dynamic>> Function()? onAddDevice,
      bool realApi = false,
      bool pushed = false,
    }) async {
      final navKey = GlobalKey<NavigatorState>();
      final screen = AddPhoneScreen(
        companyCode: companyCode,
        token: token,
        login: login,
        apiBuilder: (url, db) {
          builtUrl = url;
          builtDb = db;
          if (realApi) return OmniMobileApi(baseUrl: url, db: db, token: '');
          return api = _FakeApi(url, db, onAddDevice!);
        },
        homeBuilder: (_) => const Scaffold(body: Text('HOME')),
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionService>.value(value: session),
          ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
        ],
        child: MaterialApp(
          navigatorKey: navKey,
          home: pushed ? const Scaffold(body: Text('OLD ROOT')) : screen,
        ),
      ));
      if (pushed) {
        navKey.currentState!.push(MaterialPageRoute(builder: (_) => screen));
      }
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSubmit(WidgetTester tester,
        {String? company,
        String? login,
        String? code,
        String password = 'my-app-pw',
        bool settle = true}) async {
      if (company != null) {
        await tester.enterText(
            find.byKey(const Key('add_phone_company')), company);
      }
      if (login != null) {
        await tester.enterText(find.byKey(const Key('add_phone_login')), login);
      }
      if (code != null) {
        await tester.enterText(find.byKey(const Key('add_phone_code')), code);
      }
      await tester.enterText(
          find.byKey(const Key('add_phone_password')), password);
      await tester.pump();
      await tester.ensureVisible(_addButton);
      await tester.tap(_addButton);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // The spinner keeps animating while a sheet is up.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }

    Future<void> saveNova() => session.saveCompany(
        saasUrl: 'https://saas',
        companyCode: 'NOVAWORKS',
        clientUrl: 'https://nova.example',
        clientDb: 'nova_db');

    setUp(() async {
      session = _Session(info: _nova);
      // Face ID not capable → no opt-in sheet unless a test wants one.
      bio = BiometricAuthService(gate: FakeBiometricGate(available: false));
      await bio.load();
      api = null;
      builtUrl = null;
      builtDb = null;
    });

    testWidgets(
        'link: same company skips the lookup; sends the login, the token '
        'only, the app password and this phone; signs in', (tester) async {
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'novaworks',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => _okRes());
      await fillAndSubmit(tester);
      expect(session.lookups, 0);
      expect(builtUrl, 'https://nova.example');
      expect(builtDb, 'nova_db');
      final sent = api!.calls.single;
      expect(sent['login'], 'budi.s');
      expect(sent['token'], 'T');
      expect(sent['code'], isNull);
      expect(sent['password'], 'my-app-pw');
      expect(sent['device_id'], isNotEmpty);
      expect(session.accessToken, 'NEW-A');
      expect(session.refreshToken, 'R');
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('This phone is added. Your other phones stay signed in.'),
          findsOneWidget);
    });

    testWidgets(
        'manual code: another company is looked up and saved only after '
        'success', (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'OLD',
          clientUrl: 'https://old.example',
          clientDb: 'old_db');
      await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
      await pumpScreen(tester, onAddDevice: () async => _okRes());
      await fillAndSubmit(tester,
          company: ' novaworks ', login: ' budi.s ', code: '123456');
      expect(session.lookups, 1);
      expect(session.lastLookupCode, 'novaworks');
      expect(builtUrl, 'https://nova.example');
      final sent = api!.calls.single;
      expect(sent['login'], 'budi.s');
      expect(sent['code'], '123456');
      expect(sent['token'], isNull);
      expect(session.companyCode, 'NOVAWORKS');
      expect(session.clientUrl, 'https://nova.example');
      expect(session.accessToken, 'NEW-A');
      expect(find.text('HOME'), findsOneWidget);
    });

    for (final (error, text) in <(ApiException, String)>[
      (
        ApiException('invalid_code'),
        'That add-phone code is not right or has expired. Ask HR for a new one.'
      ),
      (ApiException('invalid_credentials'), 'Invalid login or password.'),
      (
        ApiException('account_locked', data: {'retry_after': 120}),
        'Too many attempts. Try again in 2 minutes.'
      ),
      (
        ApiException('not_active'),
        'Your Omni HR account is not active yet. Activate it with the invite '
            'from HR first.'
      ),
      // Add-phone wording, not the attendance one.
      (ApiException('mobile_not_enabled'), 'App access is off for you. Ask HR.'),
      // The request may have reached the server: the pair could be spent.
      (
        ApiException('timeout'),
        'If this phone was added, sign in with your app login and password. '
            'If not, try again.'
      ),
      (
        ApiException('network_error'),
        'If this phone was added, sign in with your app login and password. '
            'If not, try again.'
      ),
    ]) {
      testWidgets('${error.errorCode}: shown in words, nothing saved',
          (tester) async {
        await saveNova();
        await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
        await pumpScreen(tester,
            companyCode: 'NOVAWORKS',
            token: 'T',
            login: 'budi.s',
            onAddDevice: () async => throw error);
        await fillAndSubmit(tester);
        expect(find.text(text), findsOneWidget);
        expect(session.accessToken, 'OLD-A');
        expect(session.refreshToken, 'OLD-R');
        expect(find.text('HOME'), findsNothing);
        expect(tester.widget<FilledButton>(_addButton).onPressed, isNotNull);
      });
    }

    testWidgets(
        'phone added but the local save fails: sign-in guidance, not '
        '"ask HR", and the form cannot post again', (tester) async {
      await saveNova();
      session.failSave = true;
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => _okRes());
      await fillAndSubmit(tester);
      expect(
          find.text(
              'This phone is added. Sign in with your app login and password.'),
          findsOneWidget);
      expect(find.textContaining('Ask HR'), findsNothing);
      expect(find.text('HOME'), findsNothing);
      expect(api!.calls, hasLength(1));
      // The pair is void: the form is disarmed, the password is gone.
      expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const Key('add_phone_password')),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          isEmpty);
    });

    testWidgets(
        'another company, add fails: nothing switched, old company and '
        'tokens survive', (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'OLD',
          clientUrl: 'https://old.example',
          clientDb: 'old_db');
      await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
      await pumpScreen(tester,
          onAddDevice: () async => throw ApiException('invalid_code'));
      await fillAndSubmit(tester,
          company: 'novaworks', login: 'budi.s', code: '123456');
      expect(session.lookups, 1);
      expect(api!.calls, hasLength(1));
      expect(
          find.text(
              'That add-phone code is not right or has expired. Ask HR for a new one.'),
          findsOneWidget);
      expect(session.companyCode, 'OLD');
      expect(session.clientUrl, 'https://old.example');
      expect(session.accessToken, 'OLD-A');
      expect(session.refreshToken, 'OLD-R');
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('Face ID already on for this login adopts the new token',
        (tester) async {
      bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await bio.enableWithRefreshToken(login: 'budi.s', refreshToken: 'OLD');
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => _okRes(rt: 'NEW'));
      await fillAndSubmit(tester);
      const s = FlutterSecureStorage();
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'Face ID opt-in storage fails: one add_device call, the user still '
        'lands on Home', (tester) async {
      final b = _Bio(gate: FakeBiometricGate())..throwOnEnable = true;
      await b.load();
      bio = b;
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => _okRes());
      await fillAndSubmit(tester, settle: false);
      // The one-time offer is up; the session is already saved.
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(session.accessToken, 'NEW-A');
      await tester.tap(find.textContaining('Enable '));
      await tester.pumpAndSettle();
      expect(b.enableCalls, 1);
      expect(api!.calls, hasLength(1));
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('Sign in with your app login'), findsNothing);
    });

    testWidgets(
        'adopting the refresh token fails after the save: Home, not the '
        'sign-in message', (tester) async {
      final b = _Bio(gate: FakeBiometricGate(available: false))
        ..throwOnAdopt = true;
      await b.load();
      bio = b;
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => _okRes());
      await fillAndSubmit(tester);
      expect(api!.calls, hasLength(1));
      expect(session.accessToken, 'NEW-A');
      expect(find.text('HOME'), findsOneWidget);
      expect(find.textContaining('Sign in with your app login'), findsNothing);
    });

    testWidgets(
        'success replaces the whole stack with the session-aware root: when '
        'HR later revokes this phone, sign-in replaces Home', (tester) async {
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          pushed: true,
          onAddDevice: () async => _okRes());
      expect(find.text('OLD ROOT'), findsNothing); // covered by the screen
      await fillAndSubmit(tester);
      expect(find.text('HOME'), findsOneWidget);
      // invalid_session → main.dart's onInvalidSession clears the session.
      await session.clearSession();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('OLD ROOT'), findsNothing);
    });

    // A 2.61 connector has no auth/add_device.
    for (final (label, answer) in <(String, http.Response Function())>[
      (
        'an HTML 404',
        () => http.Response('<!doctype html><title>404 Not Found</title>', 404,
            headers: {'content-type': 'text/html'})
      ),
      (
        'a JSON unknown_route',
        () => http.Response('{"success": false, "error": "unknown_route"}', 404,
            headers: {'content-type': 'application/json'})
      ),
    ]) {
      testWidgets(
          'an older connector ($label): "not available yet", the existing '
          'session survives', (tester) async {
        await saveNova();
        await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
        await pumpScreen(tester,
            companyCode: 'NOVAWORKS',
            token: 'T',
            login: 'budi.s',
            realApi: true);
        await http.runWithClient(() => fillAndSubmit(tester),
            () => MockClient((_) async => answer()));
        expect(
            find.text(
                "Adding a phone isn't available for your company yet. Ask HR."),
            findsOneWidget);
        expect(session.accessToken, 'OLD-A');
        expect(session.refreshToken, 'OLD-R');
        expect(find.text('HOME'), findsNothing);
      });
    }

    testWidgets(
        'a lost answer, then invalid_code: "may already be added", not '
        '"ask HR"', (tester) async {
      await saveNova();
      var attempt = 0;
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          onAddDevice: () async => throw ApiException(
              ++attempt == 1 ? 'timeout' : 'invalid_code'));
      await fillAndSubmit(tester);
      expect(find.textContaining('If not, try again.'), findsOneWidget);
      await fillAndSubmit(tester);
      expect(api!.calls, hasLength(1)); // a fresh fake per attempt
      expect(attempt, 2);
      expect(
          find.text('This phone may already be added. Sign in with your app '
              'login and password.'),
          findsOneWidget);
      expect(find.textContaining('Ask HR'), findsNothing);
    });

    group('another company: the switch fails after clearing the session', () {
      Future<void> signedInElsewhere() async {
        await session.saveCompany(
            saasUrl: 'https://saas',
            companyCode: 'OLD',
            clientUrl: 'https://old.example',
            clientDb: 'old_db');
        await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
      }

      testWidgets('one failed save is retried: Home on the new company',
          (tester) async {
        await signedInElsewhere();
        session.failCompanySaves = 1;
        await pumpScreen(tester, onAddDevice: () async => _okRes());
        await fillAndSubmit(tester,
            company: 'novaworks', login: 'budi.s', code: '123456');
        expect(session.companySaveCalls, 2);
        expect(session.companyCode, 'NOVAWORKS');
        expect(session.accessToken, 'NEW-A');
        expect(find.text('HOME'), findsOneWidget);
      });

      testWidgets('the retry fails too: the message names the new company',
          (tester) async {
        await signedInElsewhere();
        session.failCompanySaves = 2;
        await pumpScreen(tester, onAddDevice: () async => _okRes());
        await fillAndSubmit(tester,
            company: 'novaworks', login: 'budi.s', code: '123456');
        expect(session.companySaveCalls, 2);
        expect(session.accessToken, isEmpty); // the old session was cleared
        expect(
            find.text('This phone is added to Nova Works (NOVAWORKS). Choose '
                'that company and sign in.'),
            findsOneWidget);
        expect(find.text('HOME'), findsNothing);
        expect(api!.calls, hasLength(1));
        expect(tester.widget<FilledButton>(_addButton).onPressed, isNull);
      });
    });

    testWidgets('a real server error (HTML 500) keeps the generic words',
        (tester) async {
      await saveNova();
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          login: 'budi.s',
          realApi: true);
      await http.runWithClient(
          () => fillAndSubmit(tester),
          () => MockClient((_) async =>
              http.Response('<!doctype html><title>500</title>', 500)));
      expect(
          find.text(
              'Something went wrong on our end. Please try again in a moment.'),
          findsOneWidget);
    });
  });
}
