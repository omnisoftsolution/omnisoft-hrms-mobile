import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/widgets/info_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders without a secondary icon by default', (tester) async {
    await tester.pumpWidget(_wrap(const InfoCard(
      icon: Icons.near_me_rounded,
      label: 'GPS Status',
      value: 'Office',
    )));
    expect(find.byIcon(Icons.near_me_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_rounded), findsNothing);
  });

  testWidgets('renders the secondary icon beside the primary one',
      (tester) async {
    await tester.pumpWidget(_wrap(const InfoCard(
      icon: Icons.near_me_rounded,
      label: 'GPS Status',
      value: 'Office',
      secondaryIcon: Icons.wifi_rounded,
      secondaryIconColor: Color(0xFF22C55E),
    )));
    expect(find.byIcon(Icons.near_me_rounded), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.wifi_rounded));
    expect(icon.color, const Color(0xFF22C55E));
  });
}
