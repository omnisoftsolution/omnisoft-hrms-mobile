import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/screens/home/my_day/my_day_colors.dart';

/// WCAG 2.x contrast ratio of [fg] drawn on [bg] (a translucent [fg] is
/// blended onto [bg] first).
double contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// Every text / graphic pair the app draws from the tokens:
/// name → (foreground, background, minimum ratio).
Map<String, (Color, Color, double)> pairsOf(OmniColors c) {
  const text = 4.5;
  const graphic = 3.0;
  final navPill = Color.alphaBlend(c.navIndicator, c.bar);
  return {
    'text/background': (c.text, c.background, text),
    'text/card': (c.text, c.card, text),
    'text/sheet': (c.text, c.sheet, text),
    'text/soft': (c.text, c.soft, text),
    'textSub/card': (c.textSub, c.card, text),
    'textSub/sheet': (c.textSub, c.sheet, text),
    'textSub/soft': (c.textSub, c.soft, text),
    'textMuted/card': (c.textMuted, c.card, text),
    'textMuted/background': (c.textMuted, c.background, text),
    'textMuted/bar': (c.textMuted, c.bar, text),
    'accent/card': (c.accent, c.card, text),
    'accent/background': (c.accent, c.background, text),
    'accent/navIndicator': (c.accent, navPill, text),
    'onAccentTint/accentTint': (c.onAccentTint, c.accentTint, text),
    'onBrandFill/brandFill': (c.onBrandFill, c.brandFill, text),
    'onButton/button': (c.onButton, c.button, text),
    'secondary/card': (c.secondary, c.card, text),
    'onSegmentOn/segmentOn': (c.onSegmentOn, c.segmentOn, text),
    'onPendingTint/pendingTint': (c.onPendingTint, c.pendingTint, text),
    'error/card': (c.error, c.card, text),
    'onErrorTint/errorTint': (c.onErrorTint, c.errorTint, text),
    'white/errorFill': (Colors.white, c.errorFill, text),
    'success/card': (c.success, c.card, text),
    'success/successTint': (c.success, c.successTint, text),
    'warning/warningTint': (c.warning, c.warningTint, text),
    'onBadge/badge': (c.onBadge, c.badge, text),
    'focus/card': (c.focus, c.card, graphic),
    for (final t in c.myDay.all) ...{
      'myDay.${t.kind.name} white/fill': (Colors.white, t.fill, text),
      'myDay.${t.kind.name} onTint/tint': (t.onTint, t.tint, text),
      'myDay.${t.kind.name} fill/tilePill': (t.fill, c.tilePill, text),
      'myDay.${t.kind.name} dot/card': (t.dot, c.card, graphic),
    },
  };
}

Set<String> failuresOf(OmniColors c) => {
      for (final e in pairsOf(c).entries)
        if (contrast(e.value.$1, e.value.$2) < e.value.$3) e.key,
    };

void main() {
  group('contrast', () {
    test('dark: every pair passes (4.5 text, 3 graphics)', () {
      final failing = {
        for (final k in failuresOf(OmniColors.dark))
          k: contrast(pairsOf(OmniColors.dark)[k]!.$1,
                  pairsOf(OmniColors.dark)[k]!.$2)
              .toStringAsFixed(2),
      };
      expect(failing, isEmpty);
    });

    test('light: only the failures the app already had before dark mode', () {
      // Known light failures (dark-mode plan, decision D3). Fixing one
      // means removing it here; a new failure makes this test fail.
      expect(failuresOf(OmniColors.light), {
        'textMuted/background', // 4.27
        'onButton/button', // white on #2BB8C4, 2.40
        'success/successTint', // 4.31
        'focus/card', // #2BB8C4 ring on white, 2.40
        'myDay.late dot/card', // 2.44
        'myDay.waiting dot/card', // 1.70, decorative
      });
    });
  });

  group('tokens', () {
    test('light keeps the pre-dark-mode values', () {
      final c = OmniColors.light;
      expect(c.background, AppTheme.surface);
      expect(c.card, AppTheme.surfaceContainerLowest);
      expect(c.text, AppTheme.onSurface);
      expect(c.textSub, AppTheme.onSurfaceVariant);
      expect(c.textMuted, AppTheme.outline);
      expect(c.line, AppTheme.outlineVariant);
      expect(c.soft, AppTheme.surfaceContainer);
      expect(c.accent, AppTheme.primary);
      expect(c.brandFill, AppTheme.primary);
      expect(c.button, AppTheme.primaryContainer);
      expect(c.secondary, AppTheme.secondary);
      expect(c.error, AppTheme.error);
      expect(c.lineSoft, AppTheme.outline.withValues(alpha: 0.12));
      expect(c.myDay.work.fill, const Color(0xFF006971));
    });

    test('MyDayColors still points at the light tones', () {
      expect(MyDayColors.work, same(MyDayPalette.light.work));
      expect(MyDayColors.missing.tint, const Color(0xFFFFDAD6));
      expect(MyDayColors.holiday.kind, MyDayToneKind.holiday);
    });

    test('palette.of(kind) returns the tone of that kind', () {
      for (final p in [MyDayPalette.light, MyDayPalette.dark]) {
        for (final k in MyDayToneKind.values) {
          expect(p.of(k).kind, k);
        }
      }
    });

    test('lerp ends on each side', () {
      final a = OmniColors.light, b = OmniColors.dark;
      expect(a.lerp(b, 0).background, a.background);
      expect(a.lerp(b, 1).background, b.background);
      expect(a.lerp(b, 1).myDay.late.kind, MyDayToneKind.late);
      expect(a.lerp(b, 0).cardShadow, a.cardShadow);
      expect(a.copyWith(card: Colors.red).card, Colors.red);
    });
  });

  // Building a theme starts google_fonts loads; testWidgets fakes the
  // HTTP they make (a plain test() would hit the network).
  group('themes', () {
    testWidgets('light theme carries the light tokens', (tester) async {
      final t = AppTheme.lightTheme;
      expect(t.brightness, Brightness.light);
      expect(t.extension<OmniColors>(), same(OmniColors.light));
      expect(t.scaffoldBackgroundColor, AppTheme.surface);
      expect(t.colorScheme.primary, AppTheme.primary);
      expect(t.appBarTheme.backgroundColor, Colors.white);
      expect(t.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
          Brightness.dark);
      expect(t.cardTheme.color, Colors.white);
      expect(t.bottomSheetTheme.backgroundColor, isNull);
      expect(t.snackBarTheme.backgroundColor, isNull);
    });

    testWidgets('dark theme carries the dark tokens', (tester) async {
      final t = AppTheme.darkTheme;
      final c = OmniColors.dark;
      expect(t.brightness, Brightness.dark);
      expect(t.extension<OmniColors>(), same(c));
      expect(t.scaffoldBackgroundColor, const Color(0xFF0E1415));
      expect(t.colorScheme.primary, const Color(0xFF58D8E4));
      expect(t.colorScheme.surfaceContainerHigh, c.sheet);
      expect(t.appBarTheme.backgroundColor, c.bar);
      expect(t.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
          Brightness.light);
      expect(t.appBarTheme.systemOverlayStyle?.statusBarBrightness,
          Brightness.dark);
      expect(t.cardTheme.color, c.card);
      expect(t.cardTheme.shadowColor, Colors.transparent);
      expect(t.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
          c.button);
      expect(t.bottomSheetTheme.backgroundColor, c.sheet);
      expect(t.dialogTheme.backgroundColor, c.sheet);
      // Light text on a dark bar, so error snackbars (errorFill) read too.
      expect(t.snackBarTheme.contentTextStyle?.color, c.text);
      expect(contrast(c.text, c.errorFill), greaterThan(4.5));
      expect(contrast(c.text, t.snackBarTheme.backgroundColor!),
          greaterThan(4.5));
    });

    test('the app stays light until every screen reads the tokens', () {
      expect(AppTheme.themeMode, ThemeMode.light);
    });

    testWidgets('context.omni follows the active theme', (tester) async {
      OmniColors? seen;
      Widget app(ThemeMode mode) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: Builder(builder: (context) {
              seen = context.omni;
              return const SizedBox();
            }),
          );
      await tester.pumpWidget(app(ThemeMode.dark));
      expect(seen, same(OmniColors.dark));
      await tester.pumpWidget(app(ThemeMode.light));
      await tester.pumpAndSettle();
      expect(seen, same(OmniColors.light));
    });

    testWidgets('context.omni falls back to light without the extension',
        (tester) async {
      OmniColors? seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.omni;
          return const SizedBox();
        }),
      ));
      expect(seen, same(OmniColors.light));
    });
  });
}
