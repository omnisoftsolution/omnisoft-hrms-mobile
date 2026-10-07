import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/leave_tab_icon.dart';

Widget _host({
  required int count,
  bool selected = false,
  bool reduceMotion = false,
  GlobalKey<LeaveTabIconState>? key,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: MaterialApp(
    home: Scaffold(
      body: LeaveTabIcon(
        key: key,
        count: count,
        selected: selected,
        icon: const Icon(Icons.event_note_outlined),
      ),
    ),
  ),
);

void main() {
  testWidgets('badge shows the count, hidden at zero', (tester) async {
    await tester.pumpWidget(_host(count: 0));
    expect(find.text('0'), findsNothing);
    await tester.pumpWidget(_host(count: 3));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('wiggles once when the count goes up', (tester) async {
    final key = GlobalKey<LeaveTabIconState>();
    await tester.pumpWidget(_host(count: 0, key: key));
    expect(key.currentState!.wiggling, isFalse);
    await tester.pumpWidget(_host(count: 1, key: key));
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.wiggling, isTrue);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(key.currentState!.wiggling, isFalse);
  });

  testWidgets('no wiggle on a drop, on the Leave tab, or with reduced motion', (
    tester,
  ) async {
    final key = GlobalKey<LeaveTabIconState>();
    await tester.pumpWidget(_host(count: 2, key: key));
    await tester.pumpWidget(_host(count: 1, key: key));
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.wiggling, isFalse);

    await tester.pumpWidget(_host(count: 2, key: key, selected: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.wiggling, isFalse);

    await tester.pumpWidget(_host(count: 3, key: key, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.wiggling, isFalse);
    expect(find.text('3'), findsOneWidget);
  });
}
