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

  testWidgets('a "9+" badge never covers the bell glyph centre (APP-6)', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(12, () => taps++));
    expect(find.text('9+'), findsOneWidget);
    final badge = tester.getRect(find.byKey(const ValueKey('bell-badge')));
    final glyph = tester.getCenter(find.byIcon(Icons.notifications_rounded));
    expect(badge.contains(glyph), isFalse, reason: '$badge vs $glyph');
    // It sits on the glyph's top-right corner: right of and above centre.
    expect(badge.left, greaterThan(glyph.dx));
    expect(badge.top, lessThan(glyph.dy));
    // APP-3 still holds: a tap on the badge opens Notifications.
    await tester.tapAt(tester.getCenter(find.text('9+')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a single-digit badge stays off the glyph centre too', (
    tester,
  ) async {
    await tester.pumpWidget(_host(3, () {}));
    final badge = tester.getRect(find.byKey(const ValueKey('bell-badge')));
    final glyph = tester.getCenter(find.byIcon(Icons.notifications_rounded));
    expect(badge.contains(glyph), isFalse);
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
