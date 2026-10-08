import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/widgets/omni_app_bar.dart';

Widget _host(int unread, VoidCallback onPressed) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [OmniBellButton(unreadCount: unread, onPressed: onPressed)],
    ),
  ),
);

void main() {
  testWidgets('a tap on the unread badge opens Notifications (APP-3)', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(8, () => taps++));
    expect(find.text('8'), findsOneWidget);
    // tapAt, not tap(find.text('8')): the badge must let the tap through
    // to the bell's IconButton underneath.
    await tester.tapAt(tester.getCenter(find.text('8')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a tap on the bell glyph still opens Notifications', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(8, () => taps++));
    await tester.tap(find.byIcon(Icons.notifications_rounded));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('no badge without unread notifications', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(0, () => taps++));
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('0'), findsNothing);
    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });
}
