import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'omni_colors.dart';

/// Omni HR design system — see DESIGN.md from the design source folder.
///
/// One builder makes both themes from an [OmniColors] token set, which
/// is also attached as a theme extension: screens read their colours
/// with `context.omni`. The Material 3 ColorScheme is mapped from the
/// same tokens so dialogs, pickers, snackbars and sheets follow too.
class AppTheme {
  /// What the app follows. Held on light until every screen reads
  /// `context.omni` (dark mode M1–M4); M5 flips it to
  /// [ThemeMode.system] so the app follows the phone.
  static const ThemeMode themeMode = ThemeMode.light;

  // ---- Light colour constants (design.md) ------------------------------
  // Light-only: they don't change with the phone's setting. New code uses
  // `context.omni`; these go away in dark mode M5.
  static const Color primary = Color(0xFF006971);
  static const Color onPrimary = Color(0xFFFFFFFF);
  /// Lighter teal used for the primary call-to-action and focus accents.
  static const Color primaryContainer = Color(0xFF2BB8C4);
  static const Color onPrimaryContainer = Color(0xFF004449);
  static const Color secondary = Color(0xFF395F97);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF3D494A);
  static const Color error = Color(0xFFBA1A1A);
  static const Color outline = Color(0xFF6C797B);
  static const Color outlineVariant = Color(0xFFBCC9CA);
  static const Color surfaceContainer = Color(0xFFECEEF0);
  static const Color inversePrimary = Color(0xFF58D8E4);

  /// Soft blue-tinted ambient shadow used by cards and inputs (light).
  /// Per DESIGN.md: 0px 4px 20px rgba(80, 117, 175, 0.08).
  static List<BoxShadow> get glassShadow => OmniColors.light.cardShadow;

  /// Stronger glow used by the primary CTA button (light).
  /// Per DESIGN.md: 0px 10px 30px rgba(43, 184, 196, 0.30).
  static List<BoxShadow> get primaryGlow => OmniColors.light.buttonGlow;

  static ThemeData get lightTheme => _build(
        OmniColors.light,
        const ColorScheme.light(
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: primaryContainer,
          onPrimaryContainer: onPrimaryContainer,
          secondary: secondary,
          onSecondary: onSecondary,
          surface: surface,
          onSurface: onSurface,
          onSurfaceVariant: onSurfaceVariant,
          error: error,
          outline: outline,
          outlineVariant: outlineVariant,
        ),
        // Dark status-bar icons on the white AppBar.
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // Android
          statusBarBrightness: Brightness.light, // iOS
        ),
      );

  static ThemeData get darkTheme {
    final c = OmniColors.dark;
    return _build(
      c,
      ColorScheme.dark(
        primary: c.accent,
        onPrimary: c.onButton,
        primaryContainer: c.brandFill,
        onPrimaryContainer: c.onAccentTint,
        secondary: c.secondary,
        onSecondary: const Color(0xFF0E2F5E),
        secondaryContainer: c.segmentOn,
        onSecondaryContainer: c.onPendingTint,
        surface: c.background,
        onSurface: c.text,
        onSurfaceVariant: c.textSub,
        surfaceContainerLowest: const Color(0xFF0A0F10),
        surfaceContainerLow: c.bar,
        surfaceContainer: c.card,
        surfaceContainerHigh: c.sheet,
        surfaceContainerHighest: c.soft,
        error: c.error,
        onError: c.onBadge,
        errorContainer: c.errorTint,
        onErrorContainer: c.onErrorTint,
        outline: c.textMuted,
        outlineVariant: c.line,
        inverseSurface: c.text,
        onInverseSurface: const Color(0xFF2B3132),
        inversePrimary: const Color(0xFF006971),
      ),
      // Light status-bar icons on the dark AppBar.
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS
      ),
      sheets: true,
    );
  }

  /// [sheets]: give bottom sheets and dialogs the `sheet` token. Off for
  /// light, which keeps Material's defaults as before dark mode.
  static ThemeData _build(
    OmniColors c,
    ColorScheme scheme,
    SystemUiOverlayStyle statusBar, {
    bool sheets = false,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
    );

    final inter = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      extensions: [c],
      textTheme: inter.copyWith(
        // Tighter, heavier display variants per design tokens.
        displaySmall: inter.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: c.text,
        ),
        headlineLarge: inter.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: c.text,
        ),
        headlineMedium: inter.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: c.text,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: c.text,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bar,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        systemOverlayStyle: statusBar,
        iconTheme: IconThemeData(color: c.textSub, size: 22),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.text,
          letterSpacing: -0.2,
        ),
        shape: Border(
          bottom: BorderSide(color: c.lineSoft, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: c.cardShadowColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: c.card,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.button,
          foregroundColor: c.onButton,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          // We render our own glow via the PrimaryButton widget; keep
          // Material's elevated button shadow off here so we don't get
          // double-shadow stacking.
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.button,
          foregroundColor: c.onButton,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.focus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        prefixIconColor: c.textSub,
        suffixIconColor: c.textSub,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: c.textSub,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.focus,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.bar,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.lineSoft,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: sheets
          ? BottomSheetThemeData(
              backgroundColor: c.sheet,
              modalBackgroundColor: c.sheet,
            )
          : null,
      dialogTheme: sheets ? DialogThemeData(backgroundColor: c.sheet) : null,
    );
  }
}
