import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/login/login_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/session_service.dart';

import '../services/fake_gate.dart';

Widget _host(SessionService session, BiometricAuthService bio,
        {Widget home = const LoginScreen()}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(value: session),
        ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
      ],
      child: MaterialApp(home: home),
    );

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
}
