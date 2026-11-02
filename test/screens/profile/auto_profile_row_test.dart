import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/profile/profile_screen.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';
import 'package:omni_hr/services/biometric_auth_service.dart';
import 'package:omni_hr/services/face_recognition_service.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/services/session_service.dart';

import '../../fixtures/fake_auto.dart';
import '../../services/fake_gate.dart';

/// A [FakeAuto] without a config: most employees.
class _NoConfigAuto extends FakeAuto {
  _NoConfigAuto() : super(initial: AutoPhoneState.off);

  @override
  get config => null;
}

Widget _host(AutoAttendanceService? auto, {ThemeMode mode = ThemeMode.light}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>(create: (_) => SessionService()),
        ChangeNotifierProvider<FaceRecognitionService>(
          create: (_) => FaceRecognitionService(),
        ),
        ChangeNotifierProvider<PushService>(create: (_) => PushService()),
        ChangeNotifierProvider<BiometricAuthService>(
          create: (_) => BiometricAuthService(gate: FakeBiometricGate()),
        ),
        if (auto != null)
          ChangeNotifierProvider<AutoAttendanceService>.value(value: auto),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: const ProfileScreen(),
      ),
    );

const _row = ValueKey('profile-auto-checkin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('row hidden without config or without the service', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_NoConfigAuto()));
    await tester.pump();
    expect(find.byKey(_row), findsNothing);
    await tester.pumpWidget(_host(null));
    await tester.pump();
    expect(find.byKey(_row), findsNothing);
  });

  testWidgets('subtitle per state', (tester) async {
    final auto = FakeAuto(initial: AutoPhoneState.on);
    await tester.pumpWidget(_host(auto));
    await tester.pump();
    expect(find.byKey(_row), findsOneWidget);
    expect(find.text('Automatic check-in'), findsOneWidget);
    const expected = {
      AutoPhoneState.on: 'On · HQ',
      AutoPhoneState.waitingWifi: 'Waiting for office Wi-Fi',
      AutoPhoneState.needsAlways: 'Needs location access',
      AutoPhoneState.optedOut: 'Off on this phone',
      AutoPhoneState.needsSetup: 'Not set up',
    };
    for (final e in expected.entries) {
      auto.setState(e.key);
      await tester.pump();
      expect(find.text(e.value), findsOneWidget, reason: '${e.key}');
    }
  });

  testWidgets('row opens the status screen', (tester) async {
    await tester.pumpWidget(_host(FakeAuto(initial: AutoPhoneState.on)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(_row));
    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();
    expect(find.text('Turn off on this phone'), findsOneWidget);
  });

  testWidgets('row in the dark theme', (tester) async {
    await tester.pumpWidget(
      _host(FakeAuto(initial: AutoPhoneState.on), mode: ThemeMode.dark),
    );
    await tester.pump();
    expect(find.byKey(_row), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
