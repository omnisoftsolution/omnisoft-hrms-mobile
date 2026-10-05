import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/home_body.dart';

Widget host({required bool attendanceEnabled}) => MaterialApp(
      home: Scaffold(
        body: HomeBody(
          attendanceEnabled: attendanceEnabled,
          approvalsCard: const Text('APPROVALS CARD'),
          lockedPane: const Text('LOCKED PANE'),
          onRefresh: () async {},
          children: const [Text('ATTENDANCE CONTENT')],
        ),
      ),
    );

void main() {
  testWidgets('attendance off: the approvals card shows above the locked pane',
      (tester) async {
    await tester.pumpWidget(host(attendanceEnabled: false));
    expect(find.text('APPROVALS CARD'), findsOneWidget);
    expect(find.text('LOCKED PANE'), findsOneWidget);
    expect(find.text('ATTENDANCE CONTENT'), findsNothing);
    expect(tester.getTopLeft(find.text('APPROVALS CARD')).dy,
        lessThan(tester.getTopLeft(find.text('LOCKED PANE')).dy));
  });

  testWidgets('attendance on: the card is first, before the attendance content',
      (tester) async {
    await tester.pumpWidget(host(attendanceEnabled: true));
    expect(find.text('LOCKED PANE'), findsNothing);
    expect(find.text('ATTENDANCE CONTENT'), findsOneWidget);
    expect(tester.getTopLeft(find.text('APPROVALS CARD')).dy,
        lessThan(tester.getTopLeft(find.text('ATTENDANCE CONTENT')).dy));
  });
}
