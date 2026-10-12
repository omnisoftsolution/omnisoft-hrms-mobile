import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/arrival_snack_tracker.dart';

SnackBar _bar(String text, Widget Function(Widget) wrap) =>
    SnackBar(content: wrap(Text(text)));

void main() {
  test('a tap on the notice whose arrival snackbar is on screen hides it, '
      'once (F1)', () {
    final t = ArrivalSnackTracker();
    t.shown(11);
    expect(t.visible(11), isFalse);
    expect(t.takeIfShowing(12), isFalse);
    expect(t.takeIfShowing(11), isTrue);
    expect(t.takeIfShowing(11), isFalse);
  });

  test('a tap on a notice whose arrival is still queued asks it to go as '
      'soon as it shows', () {
    final t = ArrivalSnackTracker();
    t.shown(11);
    expect(t.takeIfShowing(11), isFalse); // not on screen yet
    expect(t.visible(11), isTrue); // shows: hide it now
  });

  test('a reminder that replaced the arrival on screen means a tap on the '
      'old notice hides nothing', () {
    final t = ArrivalSnackTracker();
    t.shown(11);
    t.visible(11);
    t.replaced();
    expect(t.takeIfShowing(11), isFalse);
  });

  test('a closed arrival snackbar is no longer on screen; a late close of an '
      'older one does not clear a newer one', () {
    final t = ArrivalSnackTracker();
    final closeOld = t.shown(11);
    t.visible(11);
    closeOld();
    expect(t.takeIfShowing(11), isFalse);

    final closeA = t.shown(11);
    t.shown(12); // a newer arrival replaced it
    t.visible(12);
    closeA(); // the old snackbar's close lands late
    expect(t.takeIfShowing(12), isTrue);
  });

  testWidgets('an arrival never clears queued snackbars (an UNDO confirmation '
      'stays); a tap while the arrival is queued hides the arrival when it '
      'shows, not the bar on screen (Codex r3 #2, #3)', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: key,
      home: const Scaffold(body: SizedBox()),
    ));
    final m = key.currentState!;
    m.showSnackBar(const SnackBar(content: Text('Checked in')));
    m.showSnackBar(const SnackBar(content: Text('Checked in · UNDO')));
    await tester.pumpAndSettle();
    final t = ArrivalSnackTracker();
    showArrivalSnack(m, t, 11, (wrap) => _bar('Arrival 11', wrap));
    await tester.pumpAndSettle();
    // The arrival replaced the bar on screen only; the queued UNDO bar is
    // now current and the arrival waits behind it.
    expect(find.text('Checked in · UNDO'), findsOneWidget);
    expect(find.text('Arrival 11'), findsNothing);

    // The push tap on notice 11 arrives now.
    expect(t.takeIfShowing(11), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Checked in · UNDO'), findsOneWidget); // untouched

    m.hideCurrentSnackBar(); // the UNDO bar ends
    await tester.pumpAndSettle();
    expect(find.text('Arrival 11'), findsNothing); // went as it showed
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a tap on the arrival on screen hides it', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: key,
      home: const Scaffold(body: SizedBox()),
    ));
    final m = key.currentState!;
    final t = ArrivalSnackTracker();
    showArrivalSnack(m, t, 11, (wrap) => _bar('Arrival 11', wrap));
    await tester.pumpAndSettle();
    expect(find.text('Arrival 11'), findsOneWidget);
    expect(t.takeIfShowing(11), isTrue);
    m.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
