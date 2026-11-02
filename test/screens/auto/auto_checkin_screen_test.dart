import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/auto_attendance_config.dart';
import 'package:omni_hr/screens/auto/auto_checkin_screen.dart';
import 'package:omni_hr/screens/auto/auto_setup_card.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';

import '../../fixtures/fake_auto.dart';

class _Auto extends FakeAuto {
  _Auto(AutoPhoneState initial, {super.config}) : super(initial: initial);
  int turnOffs = 0;

  @override
  Future<void> turnOffOnThisPhone() async {
    turnOffs++;
    setState(AutoPhoneState.optedOut);
  }
}

Widget _app(_Auto auto, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: mode,
  home: AutoCheckinScreen(auto: auto, requestPermission: (_) async => 'denied'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('shows office, area, trigger and permission', (tester) async {
    await tester.pumpWidget(_app(_Auto(AutoPhoneState.on)));
    expect(find.text('HQ'), findsOneWidget);
    expect(find.text('150 m around the office'), findsOneWidget);
    expect(find.text('Location + Wi-Fi'), findsOneWidget);
    expect(find.text('Always allowed'), findsOneWidget);
    expect(find.text('Fix permission'), findsNothing);
  });

  testWidgets(
    'F-c: an office without a Wi-Fi list triggers on location alone',
    (tester) async {
      final config = AutoAttendanceConfig.fromJson({
        'trigger': 'location_wifi',
        'dwell_min': 5,
        'exit_min': 10,
        'office': {
          'name': 'HQ',
          'latitude': 1.3,
          'longitude': 103.8,
          'area_m': 150,
        },
        'wifi_required': false,
      })!;
      await tester.pumpWidget(_app(_Auto(AutoPhoneState.on, config: config)));
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Location + Wi-Fi'), findsNothing);
    },
  );

  testWidgets('F-a: no Always permission reads as needing it, not paused', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Auto(AutoPhoneState.needsAlways)));
    expect(find.text('Needs location access'), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing);
  });

  testWidgets('turn off asks first and calls turnOffOnThisPhone', (
    tester,
  ) async {
    final auto = _Auto(AutoPhoneState.on);
    await tester.pumpWidget(_app(auto));
    await tester.tap(find.byKey(const ValueKey('auto-turnoff-button')));
    await tester.pumpAndSettle();
    expect(find.text('Turn off on this phone?'), findsOneWidget);
    expect(auto.turnOffs, 0);

    await tester.tap(find.byKey(const ValueKey('auto-turnoff-cancel')));
    await tester.pumpAndSettle();
    expect(auto.turnOffs, 0);

    await tester.tap(find.byKey(const ValueKey('auto-turnoff-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-turnoff-confirm')));
    await tester.pumpAndSettle();
    expect(auto.turnOffs, 1);
    // Now off here: the way back is offered.
    expect(find.text('Turn on again'), findsOneWidget);
    expect(find.text('Turn off on this phone'), findsNothing);
  });

  testWidgets('turn on again calls turnOnAgain', (tester) async {
    final auto = _Auto(AutoPhoneState.optedOut);
    await tester.pumpWidget(_app(auto));
    await tester.tap(find.byKey(const ValueKey('auto-turnon-button')));
    await tester.pump();
    expect(auto.turnOns, 1);
  });

  testWidgets('needsAlways offers Fix permission, which opens the setup', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Auto(AutoPhoneState.needsAlways)));
    expect(find.text('Needs "Always"'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auto-fix-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auto-disclosure')), findsOneWidget);
  });

  testWidgets('needsSetup shows the signed-in-phone text and no buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Auto(AutoPhoneState.needsSetup)));
    expect(find.text(autoNeedsThisPhoneText), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('dark theme', (tester) async {
    await tester.pumpWidget(
      _app(_Auto(AutoPhoneState.needsAlways), mode: ThemeMode.dark),
    );
    expect(find.byKey(const ValueKey('auto-fix-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
