import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/widgets/push_explainer_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_fakes.dart';

void main() {
  testWidgets('the mockup wording; Turn on and Not now call back', (tester) async {
    var on = 0;
    var off = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PushExplainerCard(onTurnOn: () => on++, onNotNow: () => off++),
        ),
      ),
    );
    expect(find.text('Stay on top of your day'), findsOneWidget);
    expect(
      find.text(
        'Get told when your leave is approved, when someone needs your '
        'approval, and when you forget to check in or out.',
      ),
      findsOneWidget,
    );
    expect(find.text('You can change it later in Profile → Notifications.'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.tap(find.text('Not now'));
    expect(on, 1);
    expect(off, 1);
  });

  testWidgets('the buttons clear the home indicator (viewPadding)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            body: PushExplainerCard(onTurnOn: () {}, onNotNow: () {}),
          ),
        ),
      ),
    );
    final padding = tester.widget<Padding>(find.byKey(const ValueKey('push-explainer-body')));
    expect(padding.padding, const EdgeInsets.fromLTRB(24, 24, 24, 58));
  });

  Future<(PushService, FakeMessaging)> signedIn() async {
    final s = await signedInSession();
    final fcm = FakeMessaging()..status = AuthorizationStatus.notDetermined;
    final push = pushService(messaging: fcm, log: PushApiLog(), platform: 'ios');
    await push.onSignedIn(s);
    return (push, fcm);
  }

  Widget opener(PushService push) => MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => showPushExplainer(ctx, push),
          child: const Text('OPEN'),
        ),
      ),
    ),
  );

  testWidgets('Turn on asks the phone, remembers it was shown and closes', (tester) async {
    final (push, fcm) = await signedIn();
    await tester.pumpWidget(opener(push));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Stay on top of your day'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(fcm.requests, 1);
    expect(find.text('Stay on top of your day'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PushService.explainerSeenKey), isTrue);
  });

  testWidgets('Not now closes without the system prompt', (tester) async {
    final (push, fcm) = await signedIn();
    await tester.pumpWidget(opener(push));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(fcm.requests, 0);
    expect(find.text('Stay on top of your day'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PushService.explainerSeenKey), isTrue);
  });
}
