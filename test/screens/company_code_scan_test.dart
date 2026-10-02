import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/activation/invite_scan_screen.dart';
import 'package:omni_hr/screens/company_code/company_code_screen.dart';
import 'package:omni_hr/services/deep_link_service.dart';
import 'package:omni_hr/services/session_service.dart';

const _invite =
    ScannedInvite(ActivationArgs('NOVAWORKS', 'T', login: 'budi.s'));

Future<bool> _yes() async => true;
Future<bool> _no() async => false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester,
      {required Future<bool> Function() hasCamera,
      Future<ScanOutcome?> Function(BuildContext)? scan}) async {
    await tester.pumpWidget(const SizedBox());
    final session = SessionService();
    await session.load();
    await tester.pumpWidget(ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: CompanyCodeScreen(hasCamera: hasCamera, scanInvite: scan),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('scan button hidden without a camera', (tester) async {
    await pump(tester, hasCamera: _no);
    expect(find.byKey(const Key('company_scan')), findsNothing);
  });

  testWidgets('scan button shown with a camera', (tester) async {
    await pump(tester, hasCamera: _yes);
    expect(find.byKey(const Key('company_scan')), findsOneWidget);
    expect(find.text('Scan invite QR'), findsOneWidget);
  });

  testWidgets('scanned invite opens the prefilled activation screen',
      (tester) async {
    await pump(tester, hasCamera: _yes, scan: (_) async => _invite);
    await tester.ensureVisible(find.byKey(const Key('company_scan')));
    await tester.tap(find.byKey(const Key('company_scan')));
    await tester.pumpAndSettle();
    expect(find.text('NOVAWORKS'), findsOneWidget);
    expect(find.byKey(const Key('activation_code')), findsNothing);
  });

  testWidgets('Enter code instead opens the manual activation screen',
      (tester) async {
    await pump(tester,
        hasCamera: _yes, scan: (_) async => const EnterCodeInstead());
    await tester.ensureVisible(find.byKey(const Key('company_scan')));
    await tester.tap(find.byKey(const Key('company_scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activation_code')), findsOneWidget);
  });
}
