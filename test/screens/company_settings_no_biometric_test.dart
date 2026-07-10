import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/login/company_settings_screen.dart';
import 'package:omni_hr/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Company Settings no longer renders the biometric login switch '
      'or a Security section', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<SessionService>(
        create: (_) => SessionService(),
        child: const CompanySettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Security'), findsNothing);
  });
}
