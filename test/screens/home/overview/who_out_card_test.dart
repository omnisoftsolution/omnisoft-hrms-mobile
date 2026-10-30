import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/who_out_card.dart';

Widget _card(String scope) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        child: WhoOutCard(
          whoOut: const WhoOut(),
          scopeLabel: scope,
          today: DateTime(2026, 10, 30),
          canOpenPerson: false,
          onPerson: (_) {},
          onSeeOutlook: () {},
        ),
      ),
    ),
  ),
);

void main() {
  // Device test 2026-10-30 (Samsung, Maxhill): a long company name squeezed
  // the "Who's out" title to one letter per line.
  testWidgets('a long scope keeps the title on one line and shortens itself', (
    tester,
  ) async {
    await tester.pumpWidget(_card('SG'));
    final oneLine = tester.getSize(find.text("Who's out"));
    await tester.pumpWidget(
      _card('MAXHILL MANAGEMENT SERVICES PTE LTD'),
    );
    expect(tester.getSize(find.text("Who's out")), oneLine);
    final scope = tester.widget<Text>(
      find.text('everyone in MAXHILL MANAGEMENT SERVICES PTE LTD'),
    );
    expect(scope.maxLines, 1);
    expect(scope.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short scope shows in full', (tester) async {
    await tester.pumpWidget(_card('SG Company'));
    expect(find.text('everyone in SG Company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
