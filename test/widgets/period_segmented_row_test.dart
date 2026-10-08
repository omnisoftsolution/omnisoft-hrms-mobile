import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/widgets/period_segmented_row.dart';

/// A sheet-like host: the apply / edit sheets pad the form by 24 px.
Widget host({double textScale = 1.0, ValueChanged<String>? onChanged}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 640),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                PeriodSegmentedRow(
                  label: 'Start period',
                  value: 'am',
                  onChanged: onChanged ?? (_) {},
                ),
                PeriodSegmentedRow(
                  label: 'End period',
                  value: 'pm',
                  onChanged: onChanged ?? (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

void setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('at 320 px (text x$scale) no overflow, labels on one line', (
      tester,
    ) async {
      setWidth(tester, 320);
      await tester.pumpWidget(host(textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final word in ['Morning', 'Afternoon']) {
        final texts = find.text(word);
        expect(texts, findsNWidgets(2));
        for (final e in texts.evaluate()) {
          final box = e.renderObject! as RenderBox;
          // One line of 12 px text (FlutterTest font: line = font size);
          // a mid-word wrap would be two.
          expect(box.size.height, lessThan(2 * 12 * scale), reason: word);
        }
      }
      // Too narrow for icons + check marks.
      expect(find.byIcon(Icons.wb_twilight), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
    });
  }

  testWidgets('a roomy row keeps the icons, and taps select a half', (
    tester,
  ) async {
    setWidth(tester, 600);
    final picked = <String>[];
    await tester.pumpWidget(host(onChanged: picked.add));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 'am' selected on the first row shows the check mark; the second
    // row's 'pm' likewise; the unselected halves show their icons.
    expect(find.byIcon(Icons.wb_twilight), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    await tester.tap(find.text('Afternoon').first);
    await tester.pumpAndSettle();
    expect(picked, ['pm']);
  });
}
