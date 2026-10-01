import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/activation/activation_screen.dart';
import 'package:omni_hr/screens/activation/invite_scan_screen.dart';
import 'package:omni_hr/screens/login/login_screen.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/deep_link_service.dart';
import 'package:omni_hr/services/session_service.dart';

import '../services/fake_gate.dart';

const _invite = ScannedInvite(
    ActivationArgs('NOVAWORKS', 'T', login: 'budi.s'));

Future<bool> _yes() async => true;
Future<bool> _no() async => false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('invite screen', () {
    testWidgets('shows Scan invite QR in manual mode when a camera exists',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: ActivationScreen(hasCamera: _yes)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activation_scan')), findsOneWidget);
      expect(find.text('Scan invite QR'), findsOneWidget);
    });

    testWidgets('hidden without a camera, and when the link is prefilled',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: ActivationScreen(hasCamera: _no)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activation_scan')), findsNothing);
      await tester.pumpWidget(const MaterialApp(
          home: ActivationScreen(
              companyCode: 'NOVAWORKS', token: 'T', hasCamera: _yes)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activation_scan')), findsNothing);
    });

    testWidgets('a scanned invite replaces the screen with the prefilled one',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: ActivationScreen(
              hasCamera: _yes, scanInvite: (_) async => _invite)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activation_scan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activation_code')), findsNothing);
      expect(find.text('NOVAWORKS'), findsOneWidget);
      expect(find.text('budi.s'), findsOneWidget);
    });
  });

  group('login screen', () {
    Future<void> pumpLogin(WidgetTester tester,
        {required Future<bool> Function() hasCamera,
        Future<ScanOutcome?> Function(BuildContext)? scan}) async {
      // Unmount any previous screen so initState (the camera probe) re-runs.
      await tester.pumpWidget(const SizedBox());
      final session = SessionService();
      await session.load();
      final bio = BiometricAuthService(gate: FakeBiometricGate());
      await bio.load();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionService>.value(value: session),
          ChangeNotifierProvider<BiometricAuthService>.value(value: bio),
        ],
        child: MaterialApp(
          home: LoginScreen(hasCamera: hasCamera, scanInvite: scan),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('QR icon in the Login field only with a camera',
        (tester) async {
      await pumpLogin(tester, hasCamera: _no);
      expect(find.byKey(const Key('login_scan')), findsNothing);
      await pumpLogin(tester, hasCamera: _yes);
      expect(find.byKey(const Key('login_scan')), findsOneWidget);
      expect(find.byTooltip('Scan invite QR'), findsOneWidget);
    });

    testWidgets('scanned invite opens the prefilled activation screen',
        (tester) async {
      await pumpLogin(tester, hasCamera: _yes, scan: (_) async => _invite);
      await tester.tap(find.byKey(const Key('login_scan')));
      await tester.pumpAndSettle();
      expect(find.text('Activate Omni HR'), findsOneWidget);
      expect(find.text('NOVAWORKS'), findsOneWidget);
      expect(find.byKey(const Key('activation_code')), findsNothing);
    });

    testWidgets('Enter code instead opens the manual activation screen',
        (tester) async {
      await pumpLogin(tester,
          hasCamera: _yes, scan: (_) async => const EnterCodeInstead());
      await tester.tap(find.byKey(const Key('login_scan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activation_code')), findsOneWidget);
    });
  });
}
