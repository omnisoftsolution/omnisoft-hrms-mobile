import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/push_prefs.dart';
import 'package:omni_hr/screens/profile/notification_settings_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/push_service.dart';

import '../services/push_fakes.dart';

void main() {
  late FakeMessaging fcm;
  late PushApiLog log;
  late int settingsOpened;

  setUp(() {
    fcm = FakeMessaging()..status = AuthorizationStatus.authorized;
    log = PushApiLog()
      ..prefs = const PushPrefs(pushAvailable: true, remindersAvailable: true, muted: {'news'});
    settingsOpened = 0;
  });

  Future<PushService> signedIn({String platform = 'ios'}) async {
    final s = await signedInSession();
    final push = pushService(
      messaging: fcm,
      log: log,
      platform: platform,
      openSettings: () async => settingsOpened++,
    );
    await push.onSignedIn(s);
    return push;
  }

  Iterable<String> sets() => log.calls.where((c) => c.startsWith('prefs/set'));

  Future<void> open(WidgetTester tester, PushService push) async {
    await tester.pumpWidget(MaterialApp(home: NotificationSettingsScreen(push: push)));
    await tester.pumpAndSettle();
  }

  SwitchListTile row(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(ValueKey('push-switch-$key')));

  testWidgets('five switches against the prefs; Security always on', (tester) async {
    await open(tester, await signedIn());
    for (final name in ['My requests', 'Approvals', 'Attendance', 'Check-in reminders', 'Company news', 'Security']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(row(tester, 'requests').value, isTrue);
    expect(row(tester, 'news').value, isFalse);
    expect(row(tester, 'security').value, isTrue);
    expect(row(tester, 'security').onChanged, isNull);
    expect(find.text('Always on'), findsOneWidget);
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('Check-in reminders only when they apply', (tester) async {
    log.prefs = const PushPrefs(pushAvailable: true, remindersAvailable: false, muted: <String>{});
    await open(tester, await signedIn());
    expect(find.text('Check-in reminders'), findsNothing);
    expect(find.text('Company news'), findsOneWidget);
  });

  testWidgets('switching a group off saves the mutes', (tester) async {
    await open(tester, await signedIn());
    await tester.tap(find.byKey(const ValueKey('push-switch-approvals')));
    await tester.pumpAndSettle();
    expect(log.calls.last, 'prefs/set approvals,news');
    expect(row(tester, 'approvals').value, isFalse);
  });

  testWidgets('a failed save puts the switch back and says why', (tester) async {
    log.prefsSetError = ApiException('network_error');
    await open(tester, await signedIn());
    await tester.tap(find.byKey(const ValueKey('push-switch-approvals')));
    await tester.pumpAndSettle();
    expect(row(tester, 'approvals').value, isTrue);
    expect(find.text('No internet connection. Check your network and try again.'), findsOneWidget);
  });

  testWidgets('notifications off, never asked: the button opens the system prompt', (tester) async {
    fcm.status = AuthorizationStatus.notDetermined;
    fcm.afterRequest = AuthorizationStatus.authorized;
    await open(tester, await signedIn());
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(fcm.requests, 1);
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('notifications refused: the button opens the app settings', (tester) async {
    fcm.status = AuthorizationStatus.denied;
    await open(tester, await signedIn());
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(fcm.requests, 0);
  });

  testWidgets('a tenant without push says so', (tester) async {
    log.prefs = const PushPrefs(pushAvailable: false, remindersAvailable: false, muted: <String>{});
    await open(tester, await signedIn());
    expect(find.text("Notifications aren't available for your company yet."), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('Android, refused once: Turn on notifications asks again', (tester) async {
    fcm.status = AuthorizationStatus.denied;
    fcm.afterRequest = AuthorizationStatus.authorized;
    await open(tester, await signedIn(platform: 'android'));
    expect(find.text('Notifications are off'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(fcm.requests, 1);
    expect(settingsOpened, 0);
    expect(find.text('Notifications are off'), findsNothing);
  });

  testWidgets('Android, refused for good (deniedPermanently): Open settings', (tester) async {
    fcm.status = AuthorizationStatus.deniedPermanently;
    await open(tester, await signedIn(platform: 'android'));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(fcm.requests, 0);
  });

  testWidgets('while a change saves every switch waits, so two saves never '
      'overlap; the next change starts from the saved state', (tester) async {
    final gate = Completer<void>();
    log.prefsSetGate = gate;
    await open(tester, await signedIn());
    await tester.tap(find.byKey(const ValueKey('push-switch-approvals')));
    await tester.pump();
    expect(row(tester, 'approvals').value, isFalse);
    expect(row(tester, 'news').onChanged, isNull);
    expect(row(tester, 'requests').onChanged, isNull);
    // A second tap while the first save is out does nothing.
    await tester.tap(find.byKey(const ValueKey('push-switch-news')));
    await tester.pump();
    expect(sets(), ['prefs/set approvals,news']);
    gate.complete();
    await tester.pumpAndSettle();
    expect(row(tester, 'news').onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('push-switch-news')));
    await tester.pumpAndSettle();
    expect(sets(), ['prefs/set approvals,news', 'prefs/set approvals']);
    expect(row(tester, 'approvals').value, isFalse);
    expect(row(tester, 'news').value, isTrue);
  });

  testWidgets('a save that fails after a wait puts back only its own change', (tester) async {
    final gate = Completer<void>();
    log.prefsSetGate = gate;
    log.prefsSetError = ApiException('network_error');
    await open(tester, await signedIn());
    await tester.tap(find.byKey(const ValueKey('push-switch-approvals')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('push-switch-news')));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(sets(), ['prefs/set approvals,news']);
    expect(row(tester, 'approvals').value, isTrue);
    expect(row(tester, 'news').value, isFalse);
    expect(row(tester, 'approvals').onChanged, isNotNull);
    expect(find.text('No internet connection. Check your network and try again.'), findsOneWidget);
  });
}
