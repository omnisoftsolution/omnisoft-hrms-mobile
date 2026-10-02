import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/company_info.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../services/fake_gate.dart';

/// SessionService whose SaaS lookup is scripted (no HTTP).
class _Session extends SessionService {
  _Session({this.info});
  final CompanyInfo? info;
  int lookups = 0;
  String? lastLookupCode;

  @override
  Future<CompanyInfo> lookupCompany(String code, {String? saasUrl}) async {
    lookups++;
    lastLookupCode = code;
    return info!;
  }
}

/// Records how it was built and what /auth/activate was sent.
class _FakeApi extends OmniMobileApi {
  _FakeApi(String baseUrl, String db, this.onActivate)
      : super(baseUrl: baseUrl, db: db, token: '');

  final Future<Map<String, dynamic>> Function() onActivate;
  final calls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> activate({
    required String login,
    String? token,
    String? code,
    required String password,
    required String deviceId,
    String? deviceLabel,
    String? appVersion,
    String? newLogin,
  }) {
    calls.add({
      'login': login,
      'token': token,
      'code': code,
      'password': password,
      'device_id': deviceId,
      'new_login': newLogin,
    });
    return onActivate();
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
        {String token = 'NEW-A', String rt = 'R', String login = 'a@b.c'}) =>
    {
      'success': true,
      'access_token': token,
      'expires_at': '2099-01-01 00:00:00',
      'refresh_token': rt,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': login, 'name': 'A'},
      'employee': {'id': 6, 'name': 'A'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'prefilled token hides the code field and asks for login + password',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: ActivationScreen(companyCode: 'NOVAWORKS', token: 'T')));
    expect(find.byKey(const Key('activation_code')), findsNothing);
    expect(find.byKey(const Key('activation_login')), findsOneWidget);
    expect(find.byKey(const Key('activation_password')), findsOneWidget);
    expect(find.text('NOVAWORKS'), findsOneWidget);
  });
  testWidgets(
      'manual mode shows company code, login, code, password; '
      'button disabled until valid', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    expect(find.byKey(const Key('activation_company')), findsOneWidget);
    expect(find.byKey(const Key('activation_code')), findsOneWidget);
    final btn = find.widgetWithText(FilledButton, 'Activate');
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('activation_company')), 'NOVAWORKS');
    await tester.enterText(find.byKey(const Key('activation_login')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('activation_code')), '123456');
    await tester.enterText(
        find.byKey(const Key('activation_password')), 'longenough');
    await tester.enterText(
        find.byKey(const Key('activation_password2')), 'longenough');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
  });

  testWidgets(
      'the login field has no email keyboard or @ requirement',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
    // LabeledField renders its label upper-cased.
    expect(find.text('APP LOGIN'), findsOneWidget);
    expect(find.text('WORK EMAIL'), findsNothing);
    await tester.enterText(
        find.byKey(const Key('activation_company')), 'NOVAWORKS');
    await tester.enterText(
        find.byKey(const Key('activation_login')), '6591062006');
    await tester.enterText(find.byKey(const Key('activation_code')), '123456');
    await tester.enterText(
        find.byKey(const Key('activation_password')), 'longenough');
    await tester.enterText(
        find.byKey(const Key('activation_password2')), 'longenough');
    await tester.pump();
    final btn = find.widgetWithText(FilledButton, 'Activate');
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
  });

  group('submit', () {
    late _Session session;
    late BiometricAuthService bio;
    _FakeApi? api;
    String? builtUrl;
    String? builtDb;

    Future<void> pumpScreen(
      WidgetTester tester, {
      String? companyCode,
      String? token,
      String? login,
      required Future<Map<String, dynamic>> Function() onActivate,
    }) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionService>.value(value: session),
          ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
        ],
        child: MaterialApp(
          home: ActivationScreen(
            companyCode: companyCode,
            token: token,
            login: login,
            apiBuilder: (url, db) {
              builtUrl = url;
              builtDb = db;
              return api = _FakeApi(url, db, onActivate);
            },
            homeBuilder: (_) => const Scaffold(body: Text('HOME')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSubmit(WidgetTester tester,
        {String? company,
        String login = '  A@B.C ',
        String? code,
        bool settle = true}) async {
      if (company != null) {
        await tester.enterText(
            find.byKey(const Key('activation_company')), company);
      }
      if (login.isNotEmpty) {
        await tester.enterText(
            find.byKey(const Key('activation_login')), login);
      }
      if (code != null) {
        await tester.enterText(find.byKey(const Key('activation_code')), code);
      }
      await tester.enterText(
          find.byKey(const Key('activation_password')), 'longenough');
      await tester.enterText(
          find.byKey(const Key('activation_password2')), 'longenough');
      await tester.pump();
      final btn = find.widgetWithText(FilledButton, 'Activate');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // The submit spinner keeps animating under an open sheet.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }

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
        'same company (case-insensitive) skips the lookup; sends the '
        'trimmed lowercased login, the token only, a device id, and '
        '(no link login) the typed text as new_login',
        (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      await pumpScreen(tester,
          companyCode: 'novaworks', token: 'T', onActivate: () async => _okRes());
      await fillAndSubmit(tester);
      expect(session.lookups, 0);
      expect(builtUrl, 'https://nova.example');
      expect(builtDb, 'nova_db');
      final sent = api!.calls.single;
      expect(sent['login'], 'a@b.c');
      expect(sent['token'], 'T');
      expect(sent['code'], isNull);
      expect(sent['device_id'], isNotEmpty);
      expect(sent['new_login'], 'A@B.C');
      expect(session.accessToken, 'NEW-A');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'a different company is looked up, activated against the looked-up '
        'URL, and saved only after success (signed-in session cleared first)',
        (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'OLD',
          clientUrl: 'https://old.example',
          clientDb: 'old_db');
      await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
      await pumpScreen(tester, onActivate: () async => _okRes());
      await fillAndSubmit(tester, company: ' novaworks ', code: '123456');
      expect(session.lookups, 1);
      expect(session.lastLookupCode, 'novaworks');
      expect(builtUrl, 'https://nova.example');
      expect(builtDb, 'nova_db');
      final sent = api!.calls.single;
      expect(sent['code'], '123456');
      expect(sent['token'], isNull);
      expect(session.companyCode, 'NOVAWORKS');
      expect(session.clientUrl, 'https://nova.example');
      expect(session.clientDb, 'nova_db');
      expect(session.accessToken, 'NEW-A');
      expect(session.refreshToken, 'R');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'a failed activation for a different company leaves the saved '
        'company and session exactly as they were', (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'OLD',
          clientUrl: 'https://old.example',
          clientDb: 'old_db');
      await session.saveLoginResponse(_okRes(token: 'OLD-A', rt: 'OLD-R'));
      await pumpScreen(tester,
          onActivate: () async => throw ApiException('activation_invalid'));
      await fillAndSubmit(tester, company: 'NOVAWORKS', code: '123456');
      expect(session.lookups, 1);
      expect(session.companyCode, 'OLD');
      expect(session.clientUrl, 'https://old.example');
      expect(session.clientDb, 'old_db');
      expect(session.accessToken, 'OLD-A');
      expect(session.refreshToken, 'OLD-R');
      expect(find.textContaining('This invite is not valid'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('activation_attempts_exceeded disables the code field and '
        'the button', (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      await pumpScreen(tester,
          onActivate: () async =>
              throw ApiException('activation_attempts_exceeded'));
      await fillAndSubmit(tester, company: 'NOVAWORKS', code: '123456');
      final field = tester.widget<TextField>(find.descendant(
          of: find.byKey(const Key('activation_code')),
          matching: find.byType(TextField)));
      expect(field.enabled, isFalse);
      final btn = find.widgetWithText(FilledButton, 'Activate');
      expect(tester.widget<FilledButton>(btn).onPressed, isNull);
      expect(find.textContaining('Too many wrong codes'), findsOneWidget);
    });

    testWidgets('a connector without /auth/activate (HTML 404 → server_error) '
        'says activation is not available yet', (tester) async {
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS',
          token: 'T',
          onActivate: () async => throw ApiException('server_error'));
      await fillAndSubmit(tester);
      expect(
          find.text('Activation is not available for your company yet. '
              'Ask HR.'),
          findsOneWidget);
    });

    testWidgets(
        'Face ID already on for this login adopts the new token and '
        'skips the opt-in offer', (tester) async {
      bio = BiometricAuthService(gate: FakeBiometricGate(available: true));
      await bio.load();
      await bio.enable(login: 'a@b.c', password: 'old-pw');
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', onActivate: () async => _okRes());
      await fillAndSubmit(tester);
      const s = FlutterSecureStorage();
      expect(await s.read(key: 'biometric_refresh_token'), 'R');
      expect(await s.read(key: 'biometric_password'), isNull);
      expect(bio.usesRefreshToken, isTrue);
      // No opt-in sheet: straight to home.
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'Face ID off: the opt-in offer comes after the session is saved',
        (tester) async {
      bio = BiometricAuthService(gate: FakeBiometricGate(available: true));
      await bio.load();
      await session.saveCompany(
          saasUrl: 'https://saas',
          companyCode: 'NOVAWORKS',
          clientUrl: 'https://nova.example',
          clientDb: 'nova_db');
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', onActivate: () async => _okRes());
      await fillAndSubmit(tester, settle: false);
      // The sheet is up and the session is already signed in.
      expect(find.text('HOME'), findsNothing);
      expect(session.accessToken, 'NEW-A');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('token link prefills the App login; unchanged means no rename',
        (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: '6591062006',
          onActivate: () async => _okRes(login: '6591062006'));
      expect(find.text('6591062006'), findsOneWidget);
      await fillAndSubmit(tester, login: '');
      expect(api!.calls.single['new_login'], isNull);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('same login in another format is not a rename', (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: '6591062006',
          onActivate: () async => _okRes(login: '6591062006'));
      await fillAndSubmit(tester, login: '+65 9106 2006');
      expect(api!.calls.single['new_login'], isNull);
      expect(find.textContaining('Your app login is'), findsNothing);
    });

    testWidgets('a changed login is sent as new_login', (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: '6591062006',
          onActivate: () async => _okRes(login: 'arjun'));
      await fillAndSubmit(tester, login: 'Arjun');
      expect(api!.calls.single['new_login'], 'Arjun');
      expect(find.textContaining('Your app login is'), findsNothing);
    });

    testWidgets('old link without l and empty field keeps HR login',
        (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T',
          onActivate: () async => _okRes(login: 'hr.login'));
      await fillAndSubmit(tester, login: '');
      expect(api!.calls.single['new_login'], isNull);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets(
        'an older connector ignoring new_login shows the real login',
        (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: 'a@b.c',
          onActivate: () async => _okRes(login: 'a@b.c'));
      await fillAndSubmit(tester, login: 'arjun');
      expect(find.text('Your app login is a@b.c.'), findsOneWidget);
    });

    testWidgets(
        'HR renamed the login after the QR was printed: no rename '
        'requested, but the server login differs from the link',
        (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: 'old.login',
          onActivate: () async => _okRes(login: 'new.login'));
      await fillAndSubmit(tester, login: ''); // field untouched
      expect(api!.calls.single['new_login'], isNull);
      expect(find.text('Your app login is new.login.'), findsOneWidget);
    });

    testWidgets(
        'a hidden Odoo user login is never shown or adopted by Face ID',
        (tester) async {
      bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await bio.enableWithRefreshToken(login: 'arjun', refreshToken: 'OLD');
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: '6591062006',
          onActivate: () async =>
              _okRes(login: 'omni+7@omnihr.invalid', rt: 'NEW'));
      await fillAndSubmit(tester, login: 'arjun');
      expect(api!.calls.single['new_login'], 'arjun');
      expect(find.textContaining('omnihr.invalid'), findsNothing);
      const s = FlutterSecureStorage();
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
    });

    testWidgets('code path: login required; a different login is optional',
        (tester) async {
      await pumpScreen(tester, onActivate: () async => _okRes(login: 'new.one'));
      await tester.tap(find.byKey(const Key('activation_use_different_login')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('activation_new_login')), 'New.One');
      await fillAndSubmit(tester,
          company: 'NOVAWORKS', login: '+65 9106 2006', code: '123456');
      final sent = api!.calls.single;
      expect(sent['login'], '+65 9106 2006');
      expect(sent['new_login'], 'New.One');
    });

    testWidgets('Face ID is keyed to the login the server returned',
        (tester) async {
      // Typed text ('+65 9106 2006') differs from the stored login; only
      // keying on the server's login lets Face ID adopt the new token.
      // Today's code (typed text) leaves the old token: this test fails.
      bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await bio.enableWithRefreshToken(login: '6591062006', refreshToken: 'OLD');
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T',
          onActivate: () async => _okRes(login: '6591062006', rt: 'NEW'));
      await fillAndSubmit(tester, login: '+65 9106 2006');
      expect(api!.calls.single['new_login'], '+65 9106 2006');
      expect(find.textContaining('Your app login is'), findsNothing);
      const s = FlutterSecureStorage();
      expect(await s.read(key: 'biometric_refresh_token'), 'NEW');
    });

    testWidgets('login_taken is shown in words', (tester) async {
      await pumpScreen(tester,
          companyCode: 'NOVAWORKS', token: 'T', login: 'a',
          onActivate: () async =>
              throw ApiException('login_taken'));
      await fillAndSubmit(tester, login: 'taken');
      expect(find.text('That login is already used. Choose another.'),
          findsOneWidget);
    });
  });
}
