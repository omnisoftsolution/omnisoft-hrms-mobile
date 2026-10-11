import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:omni_hr/screens/login/company_settings_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/biometric_types.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:provider/provider.dart';

import '../services/push_fakes.dart';

/// No biometrics on this phone: LoginScreen (shown after the switch)
/// never reaches local_auth.
class _NoBiometrics implements BiometricGate {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<BiometricType>> enrolledTypes() async => const [];

  @override
  Future<BiometricAuthOutcome> authenticate(String localizedReason) async =>
      BiometricAuthOutcome.canceled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switching company in Company Settings unregisters at the old '
      'company with the old token; nothing goes to the new company', (
    tester,
  ) async {
    final session = await signedInSession();
    final log = PushApiLog();
    final fcm = FakeMessaging();
    final push = pushService(messaging: fcm, log: log);
    session.onSessionClearing = push.onSessionCleared;
    await push.init();
    await push.onSignedIn(session);
    log.calls.clear();
    final seen = <String>[];

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SessionService>.value(value: session),
              ChangeNotifierProvider<BiometricAuthService>.value(
                value: BiometricAuthService(gate: _NoBiometrics()),
              ),
            ],
            child: const MaterialApp(home: CompanySettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        // SaaS URL is the first field, Company Code the second.
        await tester.enterText(find.byType(TextField).at(1), 'BETA');
        await tester.tap(find.text('RESOLVE COMPANY'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch company'));
        await tester.pumpAndSettle();
      },
      () => MockClient((req) async {
        seen.add(req.url.toString());
        return http.Response(
          jsonEncode({
            'success': true,
            'client': {
              'company_code': 'BETA',
              'name': 'Beta',
              'odoo_url': 'https://beta.test',
              'database': 'beta',
              'features': <String, dynamic>{},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(seen, ['https://saas.test/omni_hrms/resolve_company']);
    expect(log.calls, ['unregister https://acme.test tok-1']);
    expect(fcm.deleteCalls, 1);
    expect(session.clientUrl, 'https://beta.test');
    expect(session.isLoggedIn, isFalse);
  });
}
