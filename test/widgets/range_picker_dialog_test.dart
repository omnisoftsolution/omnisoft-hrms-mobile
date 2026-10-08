import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/widgets/range_picker_dialog.dart';

Widget host({double textScale = 1.0}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: RangePickerDialog(
      initialStart: DateTime(2026, 10, 26),
      initialEnd: DateTime(2026, 10, 26),
      firstDate: DateTime(2026, 10, 1),
      lastDate: DateTime(2026, 12, 31),
    ),
  ),
);

void tall(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('month arrows are labelled buttons that turn the page', (
    tester,
  ) async {
    tall(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Previous month'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    expect(
      tester.getSemantics(find.byTooltip('Next month')),
      isSemantics(tooltip: 'Next month', isButton: true),
    );
    expect(find.text('October 2026'), findsOneWidget);

    IconButton button(String tip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tip),
        matching: find.byType(IconButton),
      ),
    );
    // October is the first allowed month: nothing to go back to.
    expect(button('Previous month').onPressed, isNull);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(button('Previous month').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
    // December is the last allowed month.
    expect(button('Next month').onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    semantics.dispose();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('weekday header is not clipped (text x$scale)', (tester) async {
      tall(tester, width: 600);
      await tester.pumpWidget(host(textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final day in ['Sun', 'Mon', 'Sat']) {
        final p = tester.renderObject<RenderParagraph>(find.text(day));
        // A clipped paragraph is laid out shorter than its text …
        expect(p.size.height, greaterThanOrEqualTo(p.textSize.height),
            reason: day);
        // … and a squeezed one is drawn smaller than the font.
        expect(tester.getRect(find.text(day)).height,
            greaterThanOrEqualTo(13 * scale - 0.01), reason: day);
      }
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('a narrow phone shrinks weekdays, never wraps (x$scale)', (
      tester,
    ) async {
      tall(tester, width: 320);
      await tester.pumpWidget(host(textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final p = tester.renderObject<RenderParagraph>(find.text('Wed'));
      expect(p.textSize.height, lessThan(2 * 13 * scale)); // one line
    });
  }

  test('weekday row grows with the text size', () {
    expect(weekdayRowHeight(TextScaler.noScaling), greaterThan(16));
    expect(
      weekdayRowHeight(const TextScaler.linear(1.3)),
      greaterThan(weekdayRowHeight(TextScaler.noScaling)),
    );
  });
}
