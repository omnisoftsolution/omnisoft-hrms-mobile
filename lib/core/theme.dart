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
  /// What the app follows: the phone's light / dark setting (dark mode
  /// M5, 2026-10-26). There is deliberately no in-app Appearance setting.
  static const ThemeMode themeMode = ThemeMode.system;

  // ---- Light colour scheme inputs (design.md) ---------------------------
  // Private since dark mode M5: only [lightTheme]'s ColorScheme reads them.
  // Screens take every colour from `context.omni`.
  static const Color _primary = Color(0xFF006971);
  static const Color _onPrimary = Color(0xFFFFFFFF);
  /// Lighter teal used for the primary call-to-action and focus accents.
  static const Color _primaryContainer = Color(0xFF2BB8C4);
  static const Color _onPrimaryContainer = Color(0xFF004449);
  static const Color _secondary = Color(0xFF395F97);
  static const Color _onSecondary = Color(0xFFFFFFFF);
  static const Color _surface = Color(0xFFF7F9FB);
  static const Color _onSurface = Color(0xFF191C1E);
  static const Color _onSurfaceVariant = Color(0xFF3D494A);
  static const Color _error = Color(0xFFBA1A1A);
  static const Color _outline = Color(0xFF6C797B);
  static const Color _outlineVariant = Color(0xFFBCC9CA);



  static ThemeData get lightTheme => _build(
        OmniColors.light,
        const ColorScheme.light(
          primary: _primary,
          onPrimary: _onPrimary,
          primaryContainer: _primaryContainer,
          onPrimaryContainer: _onPrimaryContainer,
          secondary: _secondary,
          onSecondary: _onSecondary,
          surface: _surface,
          onSurface: _onSurface,
          onSurfaceVariant: _onSurfaceVariant,
          error: _error,
          outline: _outline,
          outlineVariant: _outlineVariant,
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

  /// [sheets]: give bottom sheets, dialogs and snackbars dark colours.
  /// Off for light, which keeps Material's defaults as before dark mode.
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
      // Dark snackbars are a raised dark grey with light text (not
      // Material's inverse light bar), so an error snackbar on
      // `errorFill` keeps readable text too.
      snackBarTheme: sheets
          ? SnackBarThemeData(
              backgroundColor: const Color(0xFF2A3334),
              contentTextStyle: GoogleFonts.inter(fontSize: 14, color: c.text),
              actionTextColor: c.accent,
            )
          : null,
    );
  }
}
