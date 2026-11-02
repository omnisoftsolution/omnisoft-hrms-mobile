import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/my_day_screen.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';
import 'package:omni_hr/services/my_day_memory.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../../fixtures/fake_auto.dart';
import '../../fixtures/my_day_fixture.dart';

class _Api extends OmniMobileApi {
  _Api() : super(baseUrl: '', db: '', token: '');

  @override
  Future<MyDay> fetchMyDay() async => sampleMyDay();
}

Widget _host(FakeAuto? auto, {ThemeMode mode = ThemeMode.light}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>(create: (_) => SessionService()),
        if (auto != null)
          ChangeNotifierProvider<AutoAttendanceService>.value(value: auto),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: MyDayScreen(
          apiBuilder: (_) => _Api(),
          appBar: AppBar(title: const Text('TEST BAR')),
        ),
      ),
    );

const _line = ValueKey('auto-line');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    MyDayMemory.clear();
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('the line says what automatic check-in is doing, under the '
      'status tile', (tester) async {
    tall(tester);
    final auto = FakeAuto(initial: AutoPhoneState.on);
    await tester.pumpWidget(_host(auto));
    await tester.pumpAndSettle();
    expect(find.text('Auto check-in on · HQ'), findsOneWidget);
    final tile = tester.getBottomLeft(
      find.byKey(const ValueKey('status-tile')),
    );
    expect(
      tester.getTopLeft(find.text('Auto check-in on · HQ')).dy,
      greaterThan(tile.dy),
    );

    auto.setState(AutoPhoneState.waitingWifi);
    await tester.pump();
    expect(find.text('Waiting for office Wi-Fi'), findsOneWidget);

    auto.setState(AutoPhoneState.needsAlways);
    await tester.pump();
    // F-a: also shown before setup was ever done, so not "Paused".
    expect(find.text('Needs location access'), findsOneWidget);
    expect(find.textContaining('Paused'), findsNothing);
  });

  testWidgets('no line for off, optedOut, needsSetup or without the service', (
    tester,
  ) async {
    tall(tester);
    for (final s in [
      AutoPhoneState.off,
      AutoPhoneState.optedOut,
      AutoPhoneState.needsSetup,
    ]) {
      await tester.pumpWidget(_host(FakeAuto(initial: s)));
      await tester.pumpAndSettle();
      expect(find.byKey(_line), findsNothing, reason: '$s');
    }
    await tester.pumpWidget(_host(null));
    await tester.pumpAndSettle();
    expect(find.byKey(_line), findsNothing);
  });

  testWidgets('the line reads in the dark theme', (tester) async {
    tall(tester);
    await tester.pumpWidget(
      _host(FakeAuto(initial: AutoPhoneState.on), mode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto check-in on · HQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
