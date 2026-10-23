import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/widgets/pill_segments.dart';

const _labels = ['30 days', '60 days', '90 days'];

Widget _host({
  int value = 0,
  ValueChanged<int>? onChanged,
  String? semanticsLabel,
}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: PillSegments(
        labels: _labels,
        value: value,
        onChanged: onChanged ?? (_) {},
        semanticsLabel: semanticsLabel,
      ),
    ),
  ),
);

/// The pill fill behind option [label].
Color? _fill(WidgetTester tester, String label) {
  final box = tester.widget<Container>(
    find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  testWidgets('shows every label; the selected one is white and teal', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 1));
    for (final l in _labels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(
      tester.widget<Text>(find.text('60 days')).style!.color,
      AppTheme.primary,
    );
    expect(
      tester.widget<Text>(find.text('30 days')).style!.color,
      AppTheme.onSurfaceVariant,
    );
    expect(_fill(tester, '60 days'), AppTheme.surfaceContainerLowest);
    expect(_fill(tester, '30 days'), Colors.transparent);
  });

  testWidgets('options share the width equally', (tester) async {
    await tester.pumpWidget(_host());
    final a = tester.getSize(find.byKey(const ValueKey('pill-0')));
    final c = tester.getSize(find.byKey(const ValueKey('pill-2')));
    expect(a.width, c.width);
  });

  testWidgets('a tap reports the option index', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_host(onChanged: taps.add));
    await tester.tap(find.byKey(const ValueKey('pill-2')));
    await tester.tap(find.text('60 days'));
    expect(taps, [2, 1]);
  });

  testWidgets('each option is a button that says whether it is selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final taps = <int>[];
    await tester.pumpWidget(_host(value: 1, onChanged: taps.add));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('pill-1'))),
      isSemantics(
        label: '60 days',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('pill-0'))),
      isSemantics(label: '30 days', isButton: true, isSelected: false),
    );
    // One node per option: the label is not read twice.
    expect(find.bySemanticsLabel('60 days'), findsOneWidget);
    // The semantics tap action reaches onChanged too.
    tester.semantics.tap(find.semantics.byLabel('90 days'));
    expect(taps, [2]);
    handle.dispose();
  });

  testWidgets('the group carries its own label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(semanticsLabel: 'How far ahead'));
    expect(find.bySemanticsLabel('How far ahead'), findsOneWidget);
    handle.dispose();
  });
}
