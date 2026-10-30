import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/auto/auto_setup_card.dart';
import 'package:omni_hr/screens/auto/auto_setup_screen.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../fixtures/fake_auto.dart';

const _card = ValueKey('auto-setup-card');
const _disclosure = ValueKey('auto-disclosure');

/// Records the steps asked for and answers [answers] in turn.
class _Perm {
  _Perm(this.answers);

  final List<String> answers;
  final steps = <String>[];

  Future<String> call(String step) async {
    steps.add(step);
    return answers.isEmpty ? 'denied' : answers.removeAt(0);
  }
}

Widget _app(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: mode,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The card on a page of its own; its "Set up" pushes the setup screen.
Widget _cardApp(
  FakeAuto auto,
  _Perm perm, {
  bool ios = true,
  ThemeMode mode = ThemeMode.light,
}) => _app(
  AutoSetupCard(auto: auto, requestPermission: perm.call, isIos: ios),
  mode: mode,
);

Widget _screenApp(
  FakeAuto auto,
  _Perm perm, {
  bool ios = true,
  ThemeMode mode = ThemeMode.light,
}) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: mode,
  home: AutoSetupScreen(auto: auto, requestPermission: perm.call, isIos: ios),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('card', () {
    testWidgets('shows for needsSetup, needsAlways and optedOut', (
      tester,
    ) async {
      for (final s in [
        AutoPhoneState.needsSetup,
        AutoPhoneState.needsAlways,
        AutoPhoneState.optedOut,
      ]) {
        await tester.pumpWidget(_cardApp(FakeAuto(initial: s), _Perm([])));
        expect(find.byKey(_card), findsOneWidget, reason: '$s');
        expect(find.text('Automatic check-in'), findsOneWidget);
      }
    });

    testWidgets('hides for on, waitingWifi and off', (tester) async {
      for (final s in [
        AutoPhoneState.on,
        AutoPhoneState.waitingWifi,
        AutoPhoneState.off,
      ]) {
        await tester.pumpWidget(_cardApp(FakeAuto(initial: s), _Perm([])));
        expect(find.byKey(_card), findsNothing, reason: '$s');
      }
    });

    testWidgets('appears and disappears with the service state', (
      tester,
    ) async {
      final auto = FakeAuto(initial: AutoPhoneState.off);
      await tester.pumpWidget(_cardApp(auto, _Perm([])));
      expect(find.byKey(_card), findsNothing);
      auto.setState(AutoPhoneState.needsAlways);
      await tester.pump();
      expect(find.byKey(_card), findsOneWidget);
      auto.setState(AutoPhoneState.on);
      await tester.pump();
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('text names the office; Set up opens the disclosure', (
      tester,
    ) async {
      final perm = _Perm([]);
      await tester.pumpWidget(_cardApp(FakeAuto(), perm));
      expect(
        find.text(
          'Your HR turned it on. Set it up once and Omni HR checks you in '
          'and out at HQ.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      expect(find.byKey(_disclosure), findsOneWidget);
      expect(perm.steps, isEmpty); // nothing is asked before Continue
    });

    testWidgets('opted-out card turns it on again, then sets up if needed', (
      tester,
    ) async {
      final auto = FakeAuto(initial: AutoPhoneState.optedOut)
        ..afterTurnOn = AutoPhoneState.needsAlways;
      await tester.pumpWidget(_cardApp(auto, _Perm([])));
      await tester.tap(find.byKey(const ValueKey('auto-setup-button')));
      await tester.pumpAndSettle();
      expect(auto.turnOns, 1);
      expect(find.byKey(_disclosure), findsOneWidget);
    });

    testWidgets('opted-out card with permission already there just turns on', (
      tester,
    ) async {
      final auto = FakeAuto(initial: AutoPhoneState.optedOut)
        ..afterTurnOn = AutoPhoneState.on;
      await tester.pumpWidget(_cardApp(auto, _Perm([])));
      await tester.tap(find.byKey(const ValueKey('auto-setup-button')));
      await tester.pumpAndSettle();
      expect(auto.turnOns, 1);
      expect(find.byKey(_disclosure), findsNothing);
      expect(find.byKey(_card), findsNothing);
    });
  });

  group('disclosure', () {
    testWidgets('says location and even when the app is closed or not in use', (
      tester,
    ) async {
      await tester.pumpWidget(_screenApp(FakeAuto(), _Perm([])));
      final text = tester
          .widget<Text>(find.byKey(_disclosure))
          .textSpan!
          .toPlainText();
      expect(text, contains('location'));
      expect(text, contains('even when the app is closed or not in use'));
      expect(
        text,
        'Omni HR collects your location to check you in when you arrive at '
        'HQ and out when you leave, even when the app is closed or not in '
        'use. Only your office area is watched. Every automatic check-in '
        'shows you a notice with Undo.',
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('Not now leaves the state unchanged', (tester) async {
      final auto = FakeAuto();
      final perm = _Perm([]);
      await tester.pumpWidget(
        _app(AutoSetupCard(auto: auto, requestPermission: perm.call)),
      );
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(_disclosure), findsNothing);
      expect(find.byKey(_card), findsOneWidget);
      expect(perm.steps, isEmpty);
      expect(auto.syncs, 0);
      expect(auto.state, AutoPhoneState.needsAlways);
    });
  });

  group('permission steps', () {
    testWidgets('iPhone: while using, then Always, then the result', (
      tester,
    ) async {
      final auto = FakeAuto()..afterSync = AutoPhoneState.on;
      final perm = _Perm(['while_using', 'always']);
      await tester.pumpWidget(_screenApp(auto, perm));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(perm.steps, ['while_using']);
      expect(auto.syncs, 0);
      expect(
        find.textContaining('choose Change to Always Allow'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('auto-always-button')));
      await tester.pumpAndSettle();
      expect(perm.steps, ['while_using', 'always']);
      expect(auto.syncs, 1);
      expect(
        find.text("You're set. Omni HR checks you in at HQ."),
        findsOneWidget,
      );
    });

    testWidgets('android: Allow all the time step opens settings; resume '
        're-checks', (tester) async {
      final auto = FakeAuto()..afterSync = AutoPhoneState.on;
      final perm = _Perm(['while_using', 'denied']);
      await tester.pumpWidget(_screenApp(auto, perm, ios: false));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Allow all the time'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(auto.syncs, 0);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(perm.steps, ['while_using', 'settings']);
      expect(auto.syncs, 0); // waits for the user to come back

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auto.syncs, 1);
      expect(
        find.text("You're set. Omni HR checks you in at HQ."),
        findsOneWidget,
      );
    });

    testWidgets('android: a resume before settings was opened is ignored', (
      tester,
    ) async {
      final auto = FakeAuto();
      await tester.pumpWidget(
        _screenApp(auto, _Perm(['while_using']), ios: false),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auto.syncs, 0);
      expect(find.text('Choose Allow all the time'), findsOneWidget);
    });

    testWidgets('Always already granted skips the extra step', (tester) async {
      final auto = FakeAuto()..afterSync = AutoPhoneState.on;
      final perm = _Perm(['always']);
      await tester.pumpWidget(_screenApp(auto, perm));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(perm.steps, ['while_using']);
      expect(auto.syncs, 1);
      expect(find.textContaining("You're set"), findsOneWidget);
    });

    testWidgets('while using denied shows the paused result', (tester) async {
      final auto = FakeAuto();
      final perm = _Perm(['denied']);
      await tester.pumpWidget(_screenApp(auto, perm));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auto.syncs, 1);
      expect(find.text('Automatic check-in is paused'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('result', () {
    testWidgets('paused when Always is denied; Try again asks again', (
      tester,
    ) async {
      final auto = FakeAuto(); // stays needsAlways after sync
      final perm = _Perm(['while_using', 'denied', 'always']);
      await tester.pumpWidget(_screenApp(auto, perm));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auto-always-button')));
      await tester.pumpAndSettle();
      expect(find.text('Automatic check-in is paused'), findsOneWidget);
      expect(find.textContaining("You're set"), findsNothing);
      expect(auto.syncs, 1);

      auto.afterSync = AutoPhoneState.on;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(perm.steps, ['while_using', 'always', 'while_using']);
      expect(auto.syncs, 2);
      expect(find.textContaining("You're set"), findsOneWidget);
    });

    testWidgets('waiting for Wi-Fi counts as set', (tester) async {
      final auto = FakeAuto()..afterSync = AutoPhoneState.waitingWifi;
      await tester.pumpWidget(_screenApp(auto, _Perm(['always'])));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining("You're set"), findsOneWidget);
    });

    testWidgets('Done closes the screen', (tester) async {
      final auto = FakeAuto()..afterSync = AutoPhoneState.on;
      await tester.pumpWidget(
        _app(
          AutoSetupCard(auto: auto, requestPermission: _Perm(['always']).call),
        ),
      );
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AutoSetupScreen), findsNothing);
    });
  });

  group('dark theme', () {
    testWidgets('card and every setup step render from the dark palette', (
      tester,
    ) async {
      final dark = OmniColors.dark;
      final auto = FakeAuto();
      await tester.pumpWidget(_cardApp(auto, _Perm([]), mode: ThemeMode.dark));
      final box = tester.widget<Container>(find.byKey(_card));
      expect((box.decoration! as BoxDecoration).color, dark.accentTint);

      // Disclosure, iOS step, result (paused), all under the dark theme.
      final perm = _Perm(['while_using', 'denied']);
      await tester.pumpWidget(_screenApp(auto, perm, mode: ThemeMode.dark));
      expect(find.byKey(_disclosure), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Change to Always Allow'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auto-always-button')));
      await tester.pumpAndSettle();
      expect(find.text('Automatic check-in is paused'), findsOneWidget);
      expect(tester.takeException(), isNull);

      auto.afterSync = AutoPhoneState.on;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("You're set"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
