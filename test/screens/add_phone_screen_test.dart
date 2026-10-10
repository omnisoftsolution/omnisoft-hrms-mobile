import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/company_info.dart';
import 'package:omni_hr/screens/activation/add_phone_screen.dart';
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

    Future<void> pumpScreen(
      WidgetTester tester, {
      String? companyCode,
      String? token,
      String? login,
      required Future<Map<String, dynamic>> Function() onAddDevice,
    }) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionService>.value(value: session),
          ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
        ],
        child: MaterialApp(
          home: AddPhoneScreen(
            companyCode: companyCode,
            token: token,
            login: login,
            apiBuilder: (url, db) {
              builtUrl = url;
              builtDb = db;
              return api = _FakeApi(url, db, onAddDevice);
            },
            homeBuilder: (_) => const Scaffold(body: Text('HOME')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> fillAndSubmit(WidgetTester tester,
        {String? company,
        String? login,
        String? code,
        String password = 'my-app-pw'}) async {
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
      await tester.pumpAndSettle();
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
      (
        ApiException('mobile_not_enabled'),
        'Mobile attendance is not enabled for your profile.'
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
  });
}
