import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/widgets/coming_soon_pane.dart';
import 'package:omni_hr/widgets/employee_avatar.dart';
import 'package:omni_hr/widgets/error_state_view.dart';
import 'package:omni_hr/widgets/labeled_field.dart';
import 'package:omni_hr/widgets/omni_app_bar.dart';
import 'package:omni_hr/widgets/primary_button.dart';

/// Dark mode M1: the shared widgets take their colours from the theme.
Widget _app(Widget child, {bool dark = true}) => MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: Center(child: child)),
);

BoxDecoration _decorationAbove(WidgetTester tester, Finder f) =>
    tester
            .widget<Container>(
              find.ancestor(of: f, matching: find.byType(Container)).first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  final dark = OmniColors.dark;
  final light = OmniColors.light;

  group('PrimaryButton', () {
    testWidgets('dark: button colours, no glow', (tester) async {
      await tester.pumpWidget(
        _app(PrimaryButton(label: 'Submit', onPressed: () {})),
      );
      final style = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!;
      expect(style.backgroundColor!.resolve({}), dark.button);
      expect(style.foregroundColor!.resolve({}), dark.onButton);
      expect(
        _decorationAbove(tester, find.byType(ElevatedButton)).boxShadow,
        isNull,
      );
    });

    testWidgets('dark: danger is the red fill with white text', (tester) async {
      await tester.pumpWidget(
        _app(
          PrimaryButton(
            label: 'Cancel leave',
            onPressed: () {},
            variant: PrimaryButtonVariant.danger,
          ),
        ),
      );
      final style = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!;
      expect(style.backgroundColor!.resolve({}), dark.errorFill);
      expect(style.foregroundColor!.resolve({}), Colors.white);
    });

    testWidgets('light: unchanged teal with its glow', (tester) async {
      await tester.pumpWidget(
        _app(PrimaryButton(label: 'Submit', onPressed: () {}), dark: false),
      );
      final style = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!;
      expect(style.backgroundColor!.resolve({}), AppTheme.primaryContainer);
      expect(style.foregroundColor!.resolve({}), Colors.white);
      final glow = _decorationAbove(
        tester,
        find.byType(ElevatedButton),
      ).boxShadow!;
      expect(
        glow.single.color,
        AppTheme.primaryContainer.withValues(alpha: 0.30),
      );
    });
  });

  testWidgets('bell badge uses the badge colours', (tester) async {
    await tester.pumpWidget(
      _app(OmniBellButton(unreadCount: 3, onPressed: () {})),
    );
    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('bell-badge')),
    );
    final deco = badge.decoration! as BoxDecoration;
    expect(deco.color, dark.badge);
    expect((deco.border! as Border).top.color, dark.bar);
    expect(tester.widget<Text>(find.text('3')).style!.color, dark.onBadge);
    expect(tester.widget<Icon>(find.byType(Icon)).color, dark.accent);
  });

  testWidgets('avatar fallback and online ring follow the theme', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const EmployeeAvatar(name: '', online: true)));
    final decos = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(decos.any((d) => d.color == dark.brandFill), isTrue);
    expect(
      decos.any(
        (d) =>
            d.border is Border && (d.border! as Border).top.color == dark.bar,
      ),
      isTrue,
    );
  });

  testWidgets('labeled field: muted label, no shadow in dark', (tester) async {
    await tester.pumpWidget(_app(const LabeledField(label: 'Email')));
    expect(
      tester.widget<Text>(find.text('EMAIL')).style!.color,
      dark.textMuted,
    );
    expect(_decorationAbove(tester, find.byType(TextField)).boxShadow, isEmpty);
  });

  testWidgets('light labeled field keeps the glass shadow', (tester) async {
    await tester.pumpWidget(
      _app(const LabeledField(label: 'Email'), dark: false),
    );
    expect(
      tester.widget<Text>(find.text('EMAIL')).style!.color,
      AppTheme.outline,
    );
    expect(
      _decorationAbove(tester, find.byType(TextField)).boxShadow,
      light.cardShadow,
    );
  });

  testWidgets('coming soon + error state read the tokens', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 300,
              child: ComingSoonPane(featureName: 'Payroll'),
            ),
            ErrorStateView(message: 'Something went wrong'),
          ],
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('Payroll coming soon')).style!.color,
      dark.text,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.engineering_rounded)).color,
      dark.accent,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
      dark.error,
    );
  });
}
